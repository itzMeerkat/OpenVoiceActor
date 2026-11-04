// Check 13: can a Dart package write and read a submission over 4 GB without
// loading it into memory? Slow and disk-hungry, so it only runs when asked:
//   dart test test/zip64_test.dart --run-skipped
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:test/test.dart';

const _fileCount = 5;
const _fileBytes = 1024 * 1024 * 1024;
const _memoryLimitBytes = 500 * 1024 * 1024;

void _writePatternFile(String path, int seed) {
  final block = Uint8List(1024 * 1024);
  final out = File(path).openSync(mode: FileMode.write);
  for (var written = 0; written < _fileBytes; written += block.length) {
    block.fillRange(0, block.length, (seed + written ~/ block.length) & 255);
    block[0] = seed;
    out.writeFromSync(block);
  }
  out.closeSync();
}

void main() {
  test('submission over 4 GB round trips with bounded memory', () async {
    final dir = Directory.systemTemp.createTempSync('ova_zip64_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sep = Platform.pathSeparator;
    final zipPath = '${dir.path}${sep}big.ovasubmission';

    final encoder = ZipFileEncoder()..create(zipPath, level: 0);
    for (var i = 0; i < _fileCount; i++) {
      final source = '${dir.path}${sep}take_$i.wav';
      _writePatternFile(source, i + 1);
      await encoder.addFile(File(source), 'audio/take_$i.wav');
      File(source).deleteSync();
    }
    await encoder.close();
    final zipBytes = File(zipPath).lengthSync();
    print('archive: ${zipBytes / (1 << 30)} GiB');
    expect(zipBytes, greaterThan(0xFFFFFFFF));
    expect(ProcessInfo.maxRss, lessThan(_memoryLimitBytes));

    // An independent reader must agree, not just this package's own decoder.
    final listing = Process.runSync('tar', ['-tf', zipPath]);
    expect(listing.exitCode, 0, reason: '${listing.stderr}');
    expect('${listing.stdout}'.trim().split(RegExp(r'\r?\n')).length, _fileCount);

    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);
    expect(archive.files.length, _fileCount);

    // The last entry starts past 4 GB, the case that needs ZIP64 offsets.
    final last = archive.files.last;
    expect(last.name, 'audio/take_${_fileCount - 1}.wav');
    expect(last.size, _fileBytes);
    final extracted = '${dir.path}${sep}extracted.wav';
    final output = OutputFileStream(extracted);
    last.writeContent(output);
    await output.close();
    await input.close();

    final raf = File(extracted).openSync();
    expect(raf.lengthSync(), _fileBytes);
    expect(raf.readByteSync(), _fileCount);
    raf.setPositionSync(_fileBytes - 1);
    expect(raf.readByteSync(), (_fileCount + 1023) & 255);
    raf.closeSync();

    print('peak memory: ${ProcessInfo.maxRss ~/ (1 << 20)} MiB');
    expect(ProcessInfo.maxRss, lessThan(_memoryLimitBytes));
  }, timeout: const Timeout(Duration(minutes: 20)), skip: 'Run with --run-skipped');
}
