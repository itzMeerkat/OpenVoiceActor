import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:ova_core/ova_core.dart';
import 'package:ova_core/src/format/packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_support.dart';

const projectId = '3f1c9a52-6a0e-4c58-9d0b-2f6d3f0b7a11';
const takeId = 'e2c4a8d6-3b1f-4e70-a9c5-7f1d2b6e8a40';

Json manifest(String kind, {String version = '0.1'}) => {
  'format': 'openvoiceactor',
  'formatVersion': version,
  'kind': kind,
};

void writeZip(String path, Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, data) => archive.add(ArchiveFile.bytes(name, data)));
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
}

List<int> jsonBytes(Object json) => utf8.encode(jsonEncode(json));

Json projectJson({String id = projectId, int revision = 1}) => {
  'id': id,
  'title': 'T',
  'revision': revision,
  'sourceLanguage': 'en',
  'languages': ['en'],
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ova_format_test'));
  tearDown(() => dir.deleteSync(recursive: true));
  String at(String name) => p.join(dir.path, name);

  Future<SubmissionImport> importInto(
    String path, {
    Set<String> knownTakes = const {},
    int? freeBytes,
  }) => importSubmissionPackage(
    path: path,
    projectId: projectId,
    audioDir: at('audio'),
    knownTakeIds: knownTakes,
    knownLineIds: const {'known'},
    freeBytes: freeBytes,
  );

  /// A submission with one take, whose fields can be broken by a test.
  Future<String> makeSubmission({
    String id = takeId,
    String? file,
    String? sha,
    String lineId = 'known',
    int bitDepth = 16,
    bool omitAudio = false,
  }) async {
    final wav = at('source.wav');
    writeTestWav(wav);
    final entry = file ?? 'audio/$id.wav';
    final hash = sha ?? await sha256OfFile(wav);
    final path = at('s.ovasubmission');
    writeZip(path, {
      'manifest.json': jsonBytes(manifest('submission')),
      'submission.json': jsonBytes({
        'id': 'sub',
        'projectId': projectId,
        'projectRevision': 1,
        'actor': {'id': 'a', 'displayName': 'Alex'},
        'takes': [
          {
            'id': id,
            'lineId': lineId,
            'language': 'en',
            'recordedAt': '2026-11-03T11:40:12Z',
            'spokenText': 'Hi',
            'textVersion': 1,
            'file': entry,
            'sha256': hash,
            'audio': {
              'container': 'wav',
              'sampleFormat': 'int',
              'bitDepth': bitDepth,
              'sampleRateHz': 48000,
              'channels': 1,
              'durationMs': 100,
            },
          },
        ],
      }),
      if (!omitAudio && !entry.contains('..') && !entry.startsWith('/'))
        entry: File(wav).readAsBytesSync(),
    });
    return path;
  }

  group('model', () {
    test('unknown fields survive a rewrite at every level', () {
      final json = {
        ...projectJson(),
        'future': {'x': 1},
        'characters': [
          {'id': 'c', 'name': 'C', 'future': 2},
        ],
        'scenes': [
          {'id': 's', 'title': 'S', 'order': 1, 'future': 3},
        ],
        'lines': [
          {
            'id': 'l',
            'characterId': 'c',
            'order': 1,
            'future': 4,
            'text': {
              'en': {'value': 'v', 'version': 1},
            },
          },
        ],
        'usageTerms': {'version': 1, 'text': 't', 'future': 5},
      };
      final out = Project.fromJson(json).toJson();
      expect(out['future'], {'x': 1});
      expect((out['characters'] as List).single['future'], 2);
      expect((out['scenes'] as List).single['future'], 3);
      expect((out['lines'] as List).single['future'], 4);
      expect((out['usageTerms'] as Json)['future'], 5);
    });

    test('lines sort by scene, then order, with no scene last', () {
      final project = Project.fromJson({
        ...projectJson(),
        'scenes': [
          {'id': 'b', 'title': 'B', 'order': 20},
          {'id': 'a', 'title': 'A', 'order': 10},
        ],
        'lines': [
          {'id': '1', 'characterId': 'c', 'order': 1},
          {'id': '2', 'characterId': 'c', 'sceneId': 'b', 'order': 1},
          {'id': '3', 'characterId': 'c', 'sceneId': 'a', 'order': 2},
          {'id': '4', 'characterId': 'c', 'sceneId': 'a', 'order': 1},
          {'id': '5', 'characterId': 'c', 'order': 2, 'retired': true},
        ],
      });
      expect(project.orderedLines().map((l) => l.id), ['4', '3', '2', '1']);
      expect(project.orderedLines(includeRetired: true), hasLength(5));
    });

    test('generated ids skip those in use', () {
      expect(nextSequentialId('L', ['L000009', 'other']), 'L000010');
      expect(nextSequentialId('L', []), 'L000001');
    });
  });

  group('project packages', () {
    test('round trip', () async {
      final project = Project.fromJson(projectJson());
      await writeProjectPackage(project, at('p.ovaproject'));
      final read = await readProjectPackage(at('p.ovaproject'));
      expect(read.id, projectId);
      expect(File(at('p.ovaproject.tmp')).existsSync(), isFalse);
    });

    Future<void> expectRefused(Map<String, List<int>> entries) async {
      writeZip(at('p.ovaproject'), entries);
      await expectLater(
        readProjectPackage(at('p.ovaproject')),
        throwsA(isA<PackageException>()),
      );
    }

    test('refuses a file that is not a ZIP', () async {
      File(at('p.ovaproject')).writeAsStringSync('hello');
      await expectLater(
        readProjectPackage(at('p.ovaproject')),
        throwsA(isA<PackageException>()),
      );
    });

    test(
      'refuses the wrong kind',
      () => expectRefused({
        'manifest.json': jsonBytes(manifest('submission')),
        'project.json': jsonBytes(projectJson()),
      }),
    );

    test(
      'refuses a newer format',
      () => expectRefused({
        'manifest.json': jsonBytes(manifest('project', version: '0.2')),
        'project.json': jsonBytes(projectJson()),
      }),
    );

    test(
      'refuses missing fields',
      () => expectRefused({
        'manifest.json': jsonBytes(manifest('project')),
        'project.json': jsonBytes({'id': projectId}),
      }),
    );

    test(
      'refuses bad JSON',
      () => expectRefused({
        'manifest.json': jsonBytes(manifest('project')),
        'project.json': utf8.encode('{nope'),
      }),
    );

    test(
      'refuses a project id that could become a path',
      () => expectRefused({
        'manifest.json': jsonBytes(manifest('project')),
        'project.json': jsonBytes(projectJson(id: '../../evil')),
      }),
    );
  });

  group('submission import', () {
    test('imports a valid take', () async {
      final result = await importInto(await makeSubmission());
      expect(result.imported.single.id, takeId);
      expect(result.rejected, isEmpty);
      expect(File(p.join(at('audio'), '$takeId.wav')).existsSync(), isTrue);
    });

    test('skips takes it already has', () async {
      final result = await importInto(
        await makeSubmission(),
        knownTakes: {takeId},
      );
      expect(result.imported, isEmpty);
      expect(result.alreadyImported, 1);
    });

    test('rejects a checksum mismatch and leaves nothing behind', () async {
      final result = await importInto(await makeSubmission(sha: 'bad'));
      expect(result.imported, isEmpty);
      expect(result.rejected.single.reason, contains('checksum'));
      expect(Directory(at('audio')).listSync(), isEmpty);
    });

    test('rejects a header that disagrees with the metadata', () async {
      final result = await importInto(await makeSubmission(bitDepth: 24));
      expect(result.rejected.single.reason, contains('description'));
    });

    test('rejects a take id that could become a path', () async {
      final result = await importInto(await makeSubmission(id: '../../evil'));
      expect(result.imported, isEmpty);
      expect(result.rejected, hasLength(1));
      expect(File(p.join(dir.path, 'evil.wav')).existsSync(), isFalse);
    });

    for (final bad in [
      '../evil.wav',
      '/evil.wav',
      'C:/evil.wav',
      'a/../../evil.wav',
      'a\\evil.wav',
    ]) {
      test('rejects the path $bad', () async {
        expect(isSafeEntryPath(bad), isFalse);
        final result = await importInto(await makeSubmission(file: bad));
        expect(result.imported, isEmpty);
        expect(result.rejected, hasLength(1));
      });
    }

    test('a missing audio file rejects the take', () async {
      final result = await importInto(await makeSubmission(omitAudio: true));
      expect(result.imported, isEmpty);
      expect(result.rejected.single.reason, contains('missing'));
    });

    test('keeps a take for an unknown line and reports it', () async {
      final result = await importInto(await makeSubmission(lineId: 'gone'));
      expect(result.imported, hasLength(1));
      expect(result.unassigned.single.lineId, 'gone');
    });

    test('refuses another project', () async {
      final path = await makeSubmission();
      await expectLater(
        importSubmissionPackage(
          path: path,
          projectId: '00000000-0000-0000-0000-000000000000',
          audioDir: at('audio'),
          knownTakeIds: const {},
          knownLineIds: const {},
        ),
        throwsA(isA<PackageException>()),
      );
    });

    test('refuses when the disk is too full', () async {
      await expectLater(
        importInto(await makeSubmission(), freeBytes: 10),
        throwsA(
          isA<PackageException>().having(
            (e) => e.message,
            'message',
            contains('disk space'),
          ),
        ),
      );
    });
  });

  group('WAV headers', () {
    test('reads a valid file', () {
      writeTestWav(at('a.wav'), frames: 48000);
      final info = readWavInfo(at('a.wav'));
      expect(info.bitDepth, 16);
      expect(info.isFloat, isFalse);
      expect(info.channels, 1);
      expect(info.durationMs, 1000);
    });

    test('peaks follow the signal in each slice, for every sample format', () {
      // Quiet first half, loud second half.
      void write(String name, int bits, bool isFloat) {
        const frames = 1000;
        final bytesPerSample = bits ~/ 8;
        final out = BytesBuilder();
        void u16(int v) => out.add([v & 255, v >> 8]);
        void u32(int v) =>
            out.add([for (var i = 0; i < 4; i++) (v >> (8 * i)) & 255]);
        out.add('RIFF'.codeUnits);
        u32(36 + frames * bytesPerSample);
        out.add('WAVEfmt '.codeUnits);
        u32(16);
        u16(isFloat ? 3 : 1);
        u16(1);
        u32(48000);
        u32(48000 * bytesPerSample);
        u16(bytesPerSample);
        u16(bits);
        out.add('data'.codeUnits);
        u32(frames * bytesPerSample);
        for (var i = 0; i < frames; i++) {
          final level = i < frames / 2 ? -0.25 : 0.5;
          final bytes = ByteData(bytesPerSample);
          if (isFloat) {
            bytes.setFloat32(0, level, Endian.little);
          } else {
            final v = (level * (1 << (bits - 1))).toInt();
            for (var b = 0; b < bytesPerSample; b++) {
              bytes.setUint8(b, (v >> (8 * b)) & 255);
            }
          }
          out.add(bytes.buffer.asUint8List());
        }
        File(at(name)).writeAsBytesSync(out.toBytes());
      }

      for (final (bits, isFloat) in [
        (16, false),
        (24, false),
        (32, false),
        (32, true),
      ]) {
        final name = 'p$bits$isFloat.wav';
        write(name, bits, isFloat);
        final peaks = readWavPeaks(at(name), buckets: 10);
        expect(peaks, hasLength(10));
        expect(peaks.first, closeTo(0.25, 0.001), reason: '$bits $isFloat');
        expect(peaks.last, closeTo(0.5, 0.001), reason: '$bits $isFloat');
      }
    });

    test('refuses a truncated file', () {
      writeTestWav(at('a.wav'));
      final bytes = File(at('a.wav')).readAsBytesSync();
      File(at('a.wav')).writeAsBytesSync(bytes.sublist(0, 100));
      expect(() => readWavInfo(at('a.wav')), throwsFormatException);
    });

    test('refuses something else', () {
      File(at('a.wav')).writeAsStringSync('not a wav file at all');
      expect(() => readWavInfo(at('a.wav')), throwsFormatException);
    });
  });
}
