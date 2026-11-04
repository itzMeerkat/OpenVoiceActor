import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'ova_capture_bindings.dart';

export 'wav_analysis.dart';

enum SampleFormat {
  native(0, 'native'),
  u8(1, '8-bit'),
  s16(2, '16-bit'),
  s24(3, '24-bit'),
  s32(4, '32-bit int'),
  f32(5, '32-bit float');

  const SampleFormat(this.value, this.label);
  final int value;
  final String label;

  static SampleFormat fromValue(int value) =>
      SampleFormat.values.firstWhere((f) => f.value == value);
}

enum CaptureState { closed, armed, recording, stopping }

enum TakeResult { none, ok, deviceLost, sizeLimit, diskError }

class CaptureException implements Exception {
  CaptureException(this.message, this.code);
  final String message;
  final int code;

  @override
  String toString() => 'CaptureException: $message (code $code)';
}

class DeviceFormat {
  DeviceFormat(this.format, this.channels, this.sampleRate, this.exclusive);
  final SampleFormat format;
  final int channels;
  final int sampleRate;
  final bool exclusive;

  @override
  String toString() =>
      '${format.label}, $sampleRate Hz, $channels ch'
      '${exclusive ? ' (exclusive)' : ' (shared)'}';
}

class InputDevice {
  InputDevice(this.index, this.name, this.isDefault, this.formats);
  final int index;
  final String name;
  final bool isDefault;
  final List<DeviceFormat> formats;
}

class SessionFormat {
  SessionFormat(
    this.format,
    this.sampleRate,
    this.channels,
    this.exclusive,
    this.deviceFormat,
    this.deviceRate,
    this.deviceChannels,
    this.rawMode,
  );
  final SampleFormat format;
  final int sampleRate;
  final int channels;
  final bool exclusive;
  final SampleFormat deviceFormat;
  final int deviceRate;
  final int deviceChannels;
  final bool rawMode;

  @override
  String toString() =>
      '${format.label}, $sampleRate Hz, $channels ch, '
      '${exclusive ? 'exclusive' : 'shared'} '
      '(device: ${deviceFormat.label}, $deviceRate Hz, $deviceChannels ch), '
      'raw mode ${rawMode ? 'on' : 'off'}';
}

class CaptureStatus {
  CaptureStatus(
    this.state,
    this.lastTakeResult,
    this.deviceLost,
    this.peaks,
    this.framesWritten,
    this.droppedFrames,
    this.clippedSamples,
  );
  final CaptureState state;
  final TakeResult lastTakeResult;
  final bool deviceLost;
  final List<double> peaks;
  final int framesWritten;
  final int droppedFrames;
  final int clippedSamples;
}

/// The Dart interface the app depends on. The rest of the app never touches
/// the native backend directly, so other platforms can be added behind this.
class Capture {
  static void _check(int code, String action) {
    if (code < 0) throw CaptureException('Failed to $action', code);
  }

  static List<InputDevice> listDevices() {
    final count = ova_devices_refresh();
    _check(count, 'list input devices');
    return using((arena) {
      final name = arena<ffi.Uint8>(512).cast<Utf8>();
      final format = arena<ffi.Int32>();
      final channels = arena<ffi.Int32>();
      final rate = arena<ffi.Int32>();
      final exclusive = arena<ffi.Int32>();
      return [
        for (var i = 0; i < count; i++)
          () {
            final isDefault = ova_device_name(i, name, 512);
            _check(isDefault, 'read a device name');
            final formats = <DeviceFormat>[];
            final formatCount = ova_device_format_count(i);
            for (var f = 0; f < formatCount; f++) {
              if (ova_device_format(i, f, format, channels, rate, exclusive) ==
                  0) {
                formats.add(
                  DeviceFormat(
                    SampleFormat.fromValue(format.value),
                    channels.value,
                    rate.value,
                    exclusive.value != 0,
                  ),
                );
              }
            }
            return InputDevice(i, name.toDartString(), isDefault == 1, formats);
          }(),
      ];
    });
  }

  /// Opens a device and starts metering. Zero values take the device's native
  /// setting, which is the policy for real recording.
  static void open({
    int? deviceIndex,
    bool exclusive = false,
    SampleFormat format = SampleFormat.native,
    int sampleRate = 0,
    int channels = 0,
  }) {
    _check(
      ova_open(
        deviceIndex ?? -1,
        exclusive ? 1 : 0,
        format.value,
        sampleRate,
        channels,
      ),
      'open the input device',
    );
  }

  /// Opens a generated signal instead of a device, for tests.
  static void openSynthetic({
    required SampleFormat format,
    required int sampleRate,
    required int channels,
    int speed = 1,
  }) {
    _check(
      ova_open_synthetic(format.value, sampleRate, channels, speed),
      'open the synthetic source',
    );
  }

  static SessionFormat sessionFormat() {
    return using((arena) {
      final out = arena<OvaSessionFormatNative>();
      _check(ova_session_info(out), 'read the session format');
      final r = out.ref;
      return SessionFormat(
        SampleFormat.fromValue(r.format),
        r.sampleRate,
        r.channels,
        r.exclusive != 0,
        SampleFormat.fromValue(r.deviceFormat),
        r.deviceRate,
        r.deviceChannels,
        r.rawMode != 0,
      );
    });
  }

  static void close() => ova_close();

  static void startTake(
    String path, {
    int selectedChannel = -1,
    int preRollMs = 250,
  }) {
    using((arena) {
      _check(
        ova_record_start(
          path.toNativeUtf8(allocator: arena),
          selectedChannel,
          preRollMs,
        ),
        'start the take',
      );
    });
  }

  /// A negative [tailMs] ends the take now and removes that much from its end.
  static int requestStop({int tailMs = 250}) => ova_record_stop(tailMs);

  static CaptureStatus status() {
    return using((arena) {
      final out = arena<OvaStatusNative>();
      ova_get_status(out);
      final r = out.ref;
      return CaptureStatus(
        CaptureState.values[r.state],
        TakeResult.values[r.lastTakeResult],
        r.deviceLost != 0,
        [for (var c = 0; c < ovaMaxMeterChannels; c++) r.peaks[c]],
        r.framesWritten,
        r.droppedFrames,
        r.clippedSamples,
      );
    });
  }

  /// Requests a stop and waits for the take to finish.
  static Future<CaptureStatus> stopTake({int tailMs = 250}) async {
    // A stop can be refused until the writer has picked up the start.
    final refusedUntil = DateTime.now().add(const Duration(seconds: 2));
    while (requestStop(tailMs: tailMs) != 0) {
      final current = status();
      if (current.state != CaptureState.recording) return current;
      if (DateTime.now().isAfter(refusedUntil)) {
        throw CaptureException('Failed to stop the take', -2);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return waitForTakeEnd();
  }

  static Future<CaptureStatus> waitForTakeEnd() async {
    while (true) {
      final current = status();
      if (current.state != CaptureState.recording &&
          current.state != CaptureState.stopping) {
        return current;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Makes the session behave as if its device disappeared, for tests.
  static void testLoseDevice() => ova_test_lose_device();

  /// Repairs a `.partial` file left behind by a crash. Returns frames saved.
  static int recoverPartial(String partialPath) {
    return using((arena) {
      final frames = ova_recover_partial(
        partialPath.toNativeUtf8(allocator: arena),
      );
      _check(frames, 'recover $partialPath');
      return frames;
    });
  }
}
