import 'dart:io';
import 'dart:typed_data';

import 'package:ova_core/ova_core.dart';

/// Stands in for the native engine: writes a real WAV when a take stops.
class FakeInput implements AudioInput {
  String? _path;
  int frames = 4800;
  bool writeFile = true;
  bool loseDevice = false;
  var activity = CaptureActivity.closed;
  var outcome = TakeOutcome.ok;
  int? lastChannel;
  int? lastPreRollMs;
  int? lastTrimEndMs;
  int starts = 0;

  @override
  List<InputDeviceInfo> listDevices() => const [
    InputDeviceInfo(index: 0, name: 'Fake mic', isDefault: true),
    InputDeviceInfo(index: 1, name: 'Other mic', isDefault: false),
  ];

  @override
  InputFormat open({int? deviceIndex, required bool exclusive}) {
    activity = CaptureActivity.armed;
    return InputFormat(
      isFloat: false,
      bitDepth: 16,
      sampleRateHz: 48000,
      channels: 2,
      exclusive: exclusive,
      rawMode: true,
    );
  }

  @override
  void close() => activity = CaptureActivity.closed;

  @override
  void startTake(String wavPath, {required int channel, int preRollMs = 0}) {
    _path = wavPath;
    lastChannel = channel;
    lastPreRollMs = preRollMs;
    starts++;
    activity = CaptureActivity.recording;
  }

  @override
  void requestStop({int trimEndMs = 0}) {
    lastTrimEndMs = trimEndMs;
    if (writeFile) writeTestWav(_path!, frames: frames);
    activity = CaptureActivity.armed;
  }

  @override
  CaptureSnapshot status() => CaptureSnapshot(
    activity: activity,
    peaks: const [0.5, 0.25],
    framesWritten: frames,
    droppedFrames: 0,
    clippedSamples: 0,
    deviceLost: loseDevice,
    lastOutcome: outcome,
  );

  @override
  int recoverPartial(String partialPath) {
    File(partialPath).renameSync(partialPath.replaceAll('.partial', ''));
    return frames;
  }
}

/// A 16-bit mono WAV with a varying signal, so each file hashes differently.
void writeTestWav(String path, {int frames = 4800, int rate = 48000}) {
  final dataBytes = frames * 2;
  final bytes = ByteData(44 + dataBytes);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  final seed = DateTime.now().microsecondsSinceEpoch & 0x3FFF;
  for (var i = 0; i < frames; i++) {
    bytes.setInt16(44 + i * 2, (seed + i * 7) & 0x3FFF, Endian.little);
  }
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
}
