/// Connects the native engine to the ports `ova_core` depends on.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:ova_core/ova_core.dart';

import 'ova_capture.dart';
import 'ova_capture_bindings.dart' as native;

int _bitDepth(SampleFormat format) => switch (format) {
  SampleFormat.u8 => 8,
  SampleFormat.s16 => 16,
  SampleFormat.s24 => 24,
  SampleFormat.s32 || SampleFormat.f32 => 32,
  SampleFormat.native => 0,
};

class WindowsAudioInput implements AudioInput {
  /// A hot restart can leave the native session running, so start from closed.
  WindowsAudioInput() {
    Capture.close();
  }

  @override
  List<InputDeviceInfo> listDevices() => [
    for (final d in Capture.listDevices())
      InputDeviceInfo(index: d.index, name: d.name, isDefault: d.isDefault),
  ];

  @override
  InputFormat open({int? deviceIndex, required bool exclusive}) {
    Capture.open(deviceIndex: deviceIndex, exclusive: exclusive);
    return _sessionFormat();
  }

  InputFormat _sessionFormat() {
    final session = Capture.sessionFormat();
    return InputFormat(
      isFloat: session.format == SampleFormat.f32,
      bitDepth: _bitDepth(session.format),
      sampleRateHz: session.sampleRate,
      channels: session.channels,
      exclusive: session.exclusive,
      rawMode: session.rawMode,
    );
  }

  @override
  void close() => Capture.close();

  @override
  void startTake(String wavPath, {required int channel, int preRollMs = 0}) =>
      Capture.startTake(
        wavPath,
        selectedChannel: channel,
        preRollMs: preRollMs,
      );

  @override
  void requestStop({int trimEndMs = 0}) {
    final code = Capture.requestStop(tailMs: -trimEndMs);
    if (code != 0) throw CaptureException('The stop was refused', code);
  }

  @override
  CaptureSnapshot status() {
    final status = Capture.status();
    return CaptureSnapshot(
      activity: switch (status.state) {
        CaptureState.closed => CaptureActivity.closed,
        CaptureState.armed => CaptureActivity.armed,
        CaptureState.recording => CaptureActivity.recording,
        CaptureState.stopping => CaptureActivity.stopping,
      },
      peaks: status.peaks,
      framesWritten: status.framesWritten,
      droppedFrames: status.droppedFrames,
      clippedSamples: status.clippedSamples,
      deviceLost: status.deviceLost,
      lastOutcome: switch (status.lastTakeResult) {
        TakeResult.ok => TakeOutcome.ok,
        TakeResult.deviceLost => TakeOutcome.deviceLost,
        TakeResult.sizeLimit => TakeOutcome.sizeLimit,
        TakeResult.diskError => TakeOutcome.diskError,
        TakeResult.none => TakeOutcome.unknown,
      },
    );
  }

  @override
  int recoverPartial(String partialPath) => Capture.recoverPartial(partialPath);
}

/// The same input, fed by a generated signal, so the whole flow can be tested
/// with no hardware.
class SyntheticAudioInput extends WindowsAudioInput {
  SyntheticAudioInput({
    this.format = SampleFormat.s24,
    this.sampleRate = 48000,
    this.channels = 2,
    this.speed = 1,
  });

  final SampleFormat format;
  final int sampleRate;
  final int channels;
  final int speed;

  @override
  List<InputDeviceInfo> listDevices() => const [
    InputDeviceInfo(index: 0, name: 'Generated signal', isDefault: true),
  ];

  @override
  InputFormat open({int? deviceIndex, required bool exclusive}) {
    Capture.openSynthetic(
      format: format,
      sampleRate: sampleRate,
      channels: channels,
      speed: speed,
    );
    return _sessionFormat();
  }
}

class WindowsAudioOutput implements AudioOutput {
  @override
  void play(String wavPath) {
    using((arena) {
      final code = native.ova_play_start(
        wavPath.toNativeUtf8(allocator: arena),
      );
      if (code != 0) throw CaptureException('Failed to play the file', code);
    });
  }

  @override
  void stop() => native.ova_play_stop();

  @override
  PlaybackSnapshot status() {
    return using((arena) {
      final ffi.Pointer<native.OvaPlayStateNative> out = arena();
      native.ova_play_status(out);
      final r = out.ref;
      final rate = r.sampleRate > 0 ? r.sampleRate : 1;
      return PlaybackSnapshot(
        PlaybackActivity.values[r.state],
        r.positionFrames * 1000 ~/ rate,
        r.totalFrames * 1000 ~/ rate,
      );
    });
  }
}

/// Null when Windows can't say, in which case imports skip the space check.
int? freeDiskBytes(String path) {
  return using((arena) {
    final bytes = native.ova_free_disk_bytes(
      path.toNativeUtf8(allocator: arena),
    );
    return bytes < 0 ? null : bytes;
  });
}
