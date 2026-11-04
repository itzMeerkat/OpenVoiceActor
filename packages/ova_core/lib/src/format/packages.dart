/// Reads and writes `.ovaproject` and `.ovasubmission` packages. See spec
/// sections 2 and 6. Packages may come from strangers, so nothing in them is
/// trusted. These functions block on disk, so controllers run them in isolates.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../model/project.dart';
import '../model/submission.dart';
import 'wav_info.dart';

const formatName = 'openvoiceactor';
const formatVersion = '0.1';
const appVersion = '0.1.0';
const _createdBy = 'OpenVoiceActor $appVersion';
const _maxJsonBytes = 64 * 1024 * 1024;
const _maxEntries = 500000;

class PackageException implements Exception {
  PackageException(this.message);
  final String message;

  @override
  String toString() => message;
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Ids that are safe to use in a file path. Only UUIDs are ever used that way.
bool isUuid(String value) => _uuid.hasMatch(value);

/// Rejects absolute paths and anything that could climb out of a folder.
bool isSafeEntryPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) return false;
  if (path.contains(':') || path.contains('\u0000')) return false;
  return !path.split('/').any((s) => s.isEmpty || s == '.' || s == '..');
}

Json _manifest(String kind, DateTime now) => {
  'format': formatName,
  'formatVersion': formatVersion,
  'kind': kind,
  'createdBy': _createdBy,
  'createdAt': now.toUtc().toIso8601String(),
};

void _checkManifest(Json manifest, String kind) {
  if (manifest['format'] != formatName) {
    throw PackageException('This file is not an OpenVoiceActor package.');
  }
  if (manifest['kind'] != kind) {
    throw PackageException(
      'Expected a $kind package, but this is a ${manifest['kind']} package.',
    );
  }
  final parts = '${manifest['formatVersion']}'.split('.');
  final major = int.tryParse(parts.first);
  final minor = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  if (major == null || minor == null) {
    throw PackageException('This package has an unreadable format version.');
  }
  final supported = formatVersion.split('.').map(int.parse).toList();
  final tooNew =
      major > supported[0] ||
      (supported[0] == 0 && major == 0 && minor > supported[1]);
  if (tooNew) {
    throw PackageException(
      'This package needs a newer version of OpenVoiceActor '
      '(format ${manifest['formatVersion']}).',
    );
  }
}

Json _readJsonEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) throw PackageException('The package has no $name.');
  if (entry.size > _maxJsonBytes) {
    throw PackageException('$name in this package is too large.');
  }
  final bytes = entry.readBytes();
  if (bytes == null || bytes.length > _maxJsonBytes) {
    throw PackageException('$name in this package could not be read.');
  }
  return jsonDecode(utf8.decode(bytes)) as Json;
}

/// Opens a package and runs [read]. Malformed content of any kind becomes a
/// [PackageException] with a message fit to show the user.
Future<T> _withArchive<T>(
  String path,
  Future<T> Function(Archive archive) read,
) async {
  final input = InputFileStream(path);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (_) {
      throw PackageException('This file is not a valid package.');
    }
    if (archive.files.length > _maxEntries) {
      throw PackageException('This package has too many files.');
    }
    return await read(archive);
  } on PackageException {
    rethrow;
  } on FormatException catch (e) {
    throw PackageException('This package is damaged: ${e.message}');
  } on TypeError {
    throw PackageException('This package has missing or invalid fields.');
  } finally {
    await input.close();
  }
}

/// Writes next to the destination and renames at the end, so a failed export
/// never leaves something that looks like a finished package.
Future<void> _writeZip(
  String path,
  Future<void> Function(ZipFileEncoder encoder) write,
) async {
  final temp = '$path.tmp';
  final encoder = ZipFileEncoder()..create(temp, level: ZipFileEncoder.store);
  var closed = false;
  try {
    await write(encoder);
    closed = true;
    await encoder.close();
    File(temp).renameSync(path);
  } catch (_) {
    if (!closed) await encoder.close();
    final leftover = File(temp);
    if (leftover.existsSync()) leftover.deleteSync();
    rethrow;
  }
}

void _addJson(ZipFileEncoder encoder, String name, Json json) {
  encoder.addArchiveFile(
    ArchiveFile.string(name, const JsonEncoder.withIndent('  ').convert(json)),
  );
}

Future<void> writeProjectPackage(Project project, String path) {
  return _writeZip(path, (encoder) async {
    _addJson(encoder, 'manifest.json', _manifest('project', DateTime.now()));
    _addJson(encoder, 'project.json', project.toJson());
  });
}

Future<Project> readProjectPackage(String path) {
  return _withArchive(path, (archive) async {
    _checkManifest(_readJsonEntry(archive, 'manifest.json'), 'project');
    final project = Project.fromJson(_readJsonEntry(archive, 'project.json'));
    if (!isUuid(project.id)) {
      throw PackageException('This project has an invalid id.');
    }
    if (project.revision < 1) {
      throw PackageException('This project has an invalid revision.');
    }
    return project;
  });
}

Future<String> sha256OfFile(String path) async {
  final digest = await crypto.sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// A take that wasn't included, and why, for the report shown to the user.
class SkippedTake {
  const SkippedTake(this.takeId, this.reason);
  final String takeId;
  final String reason;
}

/// Writes a submission whose audio comes from `<audioRoot>/<take.file>`. A take
/// whose file fails its checksum is left out and reported rather than sent.
Future<(Set<String>, List<SkippedTake>)> writeSubmissionPackage({
  required Submission submission,
  required String audioRoot,
  required String path,
}) async {
  final included = <Take>[];
  final skipped = <SkippedTake>[];
  for (final take in submission.takes) {
    final file = p.join(audioRoot, take.file);
    try {
      if (await sha256OfFile(file) == take.sha256) {
        included.add(take);
      } else {
        skipped.add(SkippedTake(take.id, 'The audio file changed on disk.'));
      }
    } on FileSystemException {
      skipped.add(SkippedTake(take.id, 'The audio file is missing.'));
    }
  }

  final toWrite = Submission(
    id: submission.id,
    projectId: submission.projectId,
    projectRevision: submission.projectRevision,
    actor: submission.actor,
    usageTermsAcceptance: submission.usageTermsAcceptance,
    takes: included,
    extra: submission.extra,
  );
  await _writeZip(path, (encoder) async {
    _addJson(encoder, 'manifest.json', _manifest('submission', DateTime.now()));
    _addJson(encoder, 'submission.json', toWrite.toJson());
    for (final take in included) {
      await encoder.addFile(
        File(p.join(audioRoot, take.file)),
        take.file,
        ZipFileEncoder.store,
      );
    }
  });
  return ({for (final t in included) t.id}, skipped);
}

class SubmissionImport {
  SubmissionImport({
    required this.submission,
    required this.imported,
    required this.alreadyImported,
    required this.rejected,
    required this.unassigned,
  });

  final Submission submission;
  final List<Take> imported;
  final int alreadyImported;
  final List<SkippedTake> rejected;

  /// Imported takes whose line isn't in the project. Kept, per the spec.
  final List<Take> unassigned;
}

/// Extracts new takes from a submission into [audioDir], as `<takeId>.wav`.
/// Writes nothing to the caller's records; it reports what it found.
Future<SubmissionImport> importSubmissionPackage({
  required String path,
  required String projectId,
  required String audioDir,
  required Set<String> knownTakeIds,
  required Set<String> knownLineIds,
  int? freeBytes,
}) {
  return _withArchive(path, (archive) async {
    _checkManifest(_readJsonEntry(archive, 'manifest.json'), 'submission');
    final submission = Submission.fromJson(
      _readJsonEntry(archive, 'submission.json'),
    );
    if (submission.projectId != projectId) {
      throw PackageException('This submission belongs to a different project.');
    }

    final seen = {...knownTakeIds};
    final fresh = <(Take, ArchiveFile)>[];
    final rejected = <SkippedTake>[];
    var alreadyImported = 0;
    var bytesNeeded = 0;
    for (final take in submission.takes) {
      if (!isUuid(take.id)) {
        rejected.add(SkippedTake(take.id, 'The take has an invalid id.'));
      } else if (seen.contains(take.id)) {
        alreadyImported++;
      } else if (!isSafeEntryPath(take.file)) {
        rejected.add(SkippedTake(take.id, 'The take has an unsafe file path.'));
      } else {
        final entry = archive.find(take.file);
        if (entry == null) {
          rejected.add(SkippedTake(take.id, 'The audio file is missing.'));
        } else {
          seen.add(take.id);
          fresh.add((take, entry));
          bytesNeeded += entry.size;
        }
      }
    }
    if (freeBytes != null && bytesNeeded > freeBytes) {
      throw PackageException(
        'Not enough disk space: this submission needs '
        '${bytesNeeded ~/ (1 << 20)} MB and ${freeBytes ~/ (1 << 20)} MB is free.',
      );
    }

    Directory(audioDir).createSync(recursive: true);
    final imported = <Take>[];
    for (final (take, entry) in fresh) {
      final finalPath = p.join(audioDir, '${take.id}.wav');
      final temp = '$finalPath.import';
      try {
        final output = OutputFileStream(temp);
        entry.writeContent(output);
        await output.close();
        if (await sha256OfFile(temp) != take.sha256) {
          throw const FormatException('The audio failed its checksum.');
        }
        if (!readWavInfo(temp).matches(take.audio)) {
          throw const FormatException(
            'The audio does not match its description.',
          );
        }
        File(temp).renameSync(finalPath);
        imported.add(take);
      } catch (e) {
        final reason = e is FormatException
            ? e.message
            : 'It could not be read.';
        rejected.add(SkippedTake(take.id, reason));
        final leftover = File(temp);
        if (leftover.existsSync()) leftover.deleteSync();
      }
    }

    return SubmissionImport(
      submission: submission,
      imported: imported,
      alreadyImported: alreadyImported,
      rejected: rejected,
      unassigned: [
        for (final t in imported)
          if (!knownLineIds.contains(t.lineId)) t,
      ],
    );
  });
}
