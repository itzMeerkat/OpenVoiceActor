/// What the logic needs from audio hardware. `ova_capture` implements these on
/// Windows, tests use fakes, and other platforms can be added behind them.
library;

class InputDeviceInfo {
  const InputDeviceInfo({
    required this.index,
    required this.name,
    required this.isDefault,
  });

  final int index;
  final String name;
  final bool isDefault;
}

/// The format a device actually opened in.
class InputFormat {
  const InputFormat({
    required this.isFloat,
    required this.bitDepth,
    required this.sampleRateHz,
    required this.channels,
    required this.exclusive,
    required this.rawMode,
  });

  final bool isFloat;
  final int bitDepth;
  final int sampleRateHz;
  final int channels;
  final bool exclusive;
  final bool rawMode;
}

enum CaptureActivity { closed, armed, recording, stopping }

enum TakeOutcome { ok, deviceLost, sizeLimit, diskError, unknown }

class CaptureSnapshot {
  const CaptureSnapshot({
    required this.activity,
    required this.peaks,
    required this.framesWritten,
    required this.droppedFrames,
    required this.clippedSamples,
    required this.deviceLost,
    required this.lastOutcome,
  });

  final CaptureActivity activity;
  final List<double> peaks;
  final int framesWritten;
  final int droppedFrames;
  final int clippedSamples;
  final bool deviceLost;
  final TakeOutcome lastOutcome;
}

abstract interface class AudioInput {
  List<InputDeviceInfo> listDevices();

  /// Opens a device and starts metering, in its native format.
  InputFormat open({int? deviceIndex, required bool exclusive});
  void close();

  /// Records [channel] as a mono file at [wavPath]. The file only appears there
  /// once the take finishes; until then it's at `<wavPath>.partial`. It begins
  /// with the [preRollMs] of audio heard just before this call.
  void startTake(String wavPath, {required int channel, int preRollMs = 0});

  /// Ends the take, removing the last [trimEndMs] of what was heard before now.
  void requestStop({int trimEndMs = 0});
  CaptureSnapshot status();

  /// Repairs a `.partial` file left by a crash. Returns the frames saved.
  int recoverPartial(String partialPath);
}

enum PlaybackActivity { idle, playing, finished }

class PlaybackSnapshot {
  const PlaybackSnapshot(this.activity, this.positionMs, this.durationMs);

  final PlaybackActivity activity;
  final int positionMs;
  final int durationMs;
}

abstract interface class AudioOutput {
  void play(String wavPath);
  void stop();
  PlaybackSnapshot status();
}

/// Free space on the disk holding [path], or null when it can't be determined.
typedef FreeSpaceLookup = int? Function(String path);
