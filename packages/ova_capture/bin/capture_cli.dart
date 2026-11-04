// Command-line harness for checks that need a real device or a real crash.
//
//   dart run ova_capture:capture_cli devices
//   dart run ova_capture:capture_cli record <out.wav> <seconds> [--exclusive]
//       [--device=N] [--channel=N]
//   dart run ova_capture:capture_cli analyze <file.wav>
//   dart run ova_capture:capture_cli crash-take <out.wav>
//   dart run ova_capture:capture_cli recover <file.wav.partial>
import 'dart:io';

import 'package:ova_capture/ova_capture.dart';

int? _intOption(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return int.parse(arg.split('=').last);
  }
  return null;
}

void _printDevices() {
  for (final d in Capture.listDevices()) {
    print('[${d.index}] ${d.name}${d.isDefault ? ' (default)' : ''}');
    for (final f in d.formats) {
      print('    $f');
    }
  }
}

Future<void> _record(List<String> args) async {
  final out = args[1];
  final seconds = int.parse(args[2]);
  if (_intOption(args, 'device') != null) Capture.listDevices();
  Capture.open(
    deviceIndex: _intOption(args, 'device'),
    exclusive: args.contains('--exclusive'),
  );
  print('session: ${Capture.sessionFormat()}');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  Capture.startTake(out, selectedChannel: _intOption(args, 'channel') ?? 0);
  await Future<void>.delayed(Duration(seconds: seconds));
  final end = await Capture.stopTake();
  print(
    'take: ${end.lastTakeResult.name}, frames ${end.framesWritten}, '
    'dropped ${end.droppedFrames}, clipped ${end.clippedSamples}',
  );
  Capture.close();
  print('file: ${analyzeWav(out)}');
}

/// Records until killed. Prints "recording" once audio has reached the disk.
Future<void> _crashTake(String out) async {
  Capture.openSynthetic(
    format: SampleFormat.s24,
    sampleRate: 48000,
    channels: 1,
  );
  Capture.startTake(out, preRollMs: 0);
  while (Capture.status().framesWritten < 48000) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  print('recording');
  await Future<void>.delayed(const Duration(minutes: 5));
}

Future<void> main(List<String> args) async {
  switch (args.firstOrNull) {
    case 'devices':
      _printDevices();
    case 'record':
      await _record(args);
    case 'analyze':
      print(analyzeWav(args[1]));
    case 'crash-take':
      await _crashTake(args[1]);
    case 'recover':
      print('recovered ${Capture.recoverPartial(args[1])} frames');
    default:
      stderr.writeln('Usage: see the top of bin/capture_cli.dart');
      exitCode = 64;
  }
}
