import 'dart:async';

import '../model/local_data.dart';
import '../model/project.dart';
import '../model/submission.dart';
import '../ports/audio_ports.dart';
import 'actor_controller.dart';
import 'notifier.dart';

const _pollInterval = Duration(milliseconds: 50);
const _peakFalloff = 0.85;
const _stopTimeout = Duration(seconds: 5);

// Pressing a mouse button or key is audible to the mic, so a take must not
// include it. These work together: the take starts [defaultCountIn] after the
// press, and its pre-roll is short enough to stay clear of that press, so it
// holds only room tone and any word begun a little early. Stopping removes what
// was heard just before the stop, which is where that press landed.
const defaultCountIn = Duration(seconds: 1);
const _preRollMs = 300;
const _stopTrimMs = 200;

/// Drives the input device: device choice, meters, and starting and stopping
/// takes. It keeps no project data, handing finished takes to [ActorController].
class RecordingController extends Notifier {
  RecordingController(
    this.input,
    this.actor, {
    this.onBeforeTake,
    this.countIn = defaultCountIn,
  });

  final AudioInput input;
  final ActorController actor;

  /// Runs before each take, such as to stop playback from reaching the mic.
  final void Function()? onBeforeTake;

  /// How long after the press a take begins. Zero starts it at once.
  final Duration countIn;

  List<InputDeviceInfo> devices = [];
  InputDeviceInfo? device;
  InputFormat? format;
  List<double> meters = [];
  CaptureActivity activity = CaptureActivity.closed;
  bool deviceLost = false;
  double elapsedSeconds = 0;
  int droppedFrames = 0;
  int clippedSamples = 0;
  String? error;

  /// Set after a take that ended by itself, such as on a lost device.
  String? takeNotice;

  /// The line being recorded, so screens can keep it on show while recording.
  String? recordingLineId;

  /// True from the press until capture begins. Stopping now cancels the take.
  bool isCountingIn = false;

  Timer? _timer;
  Timer? _countInTimer;
  PendingTake? _pending;
  bool _finishing = false;
  DateTime? _stopRequestedAt;

  bool get isOpen => format != null;

  /// True from the press until the take is saved, including the count-in.
  bool get isRecording => _pending != null || isCountingIn;
  bool get exclusive => actor.settings.exclusiveMode;
  int get channel => actor.settings.inputChannel;

  /// A reason to warn the actor, who may still record (spec section 3).
  String? get audioRequestWarning {
    final request = actor.project.audioRequest;
    final current = format;
    if (request == null || current == null) return null;
    final problems = [
      if (request.minSampleRateHz != null &&
          current.sampleRateHz < request.minSampleRateHz!)
        '${request.minSampleRateHz} Hz',
      if (request.minBitDepth != null &&
          current.bitDepth < request.minBitDepth!)
        '${request.minBitDepth}-bit',
    ];
    if (problems.isEmpty) return null;
    return 'This project asks for at least ${problems.join(' and ')}, '
        'and this input is below that.';
  }

  /// Lists devices and opens the last used one, or the default.
  void start() {
    refreshDevices();
    final current = device;
    if (current != null) open(current);
  }

  void refreshDevices() {
    if (isRecording) return;
    error = null;
    try {
      devices = input.listDevices();
      final saved = actor.settings.inputDeviceName;
      device =
          devices.where((d) => d.name == saved).firstOrNull ??
          devices.where((d) => d.isDefault).firstOrNull ??
          devices.firstOrNull;
      if (device == null) error = 'No input devices found.';
    } catch (e) {
      error = 'Could not list input devices: $e';
    }
    notifyListeners();
  }

  void open(InputDeviceInfo target) {
    if (isRecording) return;
    _closeDevice();
    device = target;
    error = null;
    deviceLost = false;
    try {
      final opened = input.open(
        deviceIndex: target.index,
        exclusive: exclusive,
      );
      format = opened;
      meters = List.filled(opened.channels, 0);
      if (channel >= opened.channels) actor.settings.inputChannel = 0;
      actor.settings.inputDeviceName = target.name;
      actor.workspace.saveSettings(actor.settings);
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    } catch (e) {
      error = exclusive
          ? 'Could not open ${target.name}. Another app may be using it. '
                'Try turning off exclusive mode.'
          : 'Could not open ${target.name}: $e';
    }
    notifyListeners();
  }

  void setExclusive(bool value) {
    if (isRecording || value == exclusive) return;
    actor.settings.exclusiveMode = value;
    actor.workspace.saveSettings(actor.settings);
    final current = device;
    if (current != null) open(current);
    notifyListeners();
  }

  void selectChannel(int value) {
    if (isRecording) return;
    actor.settings.inputChannel = value;
    actor.workspace.saveSettings(actor.settings);
    notifyListeners();
  }

  void startTake(Line line) {
    if (!isOpen || isRecording || deviceLost) return;
    onBeforeTake?.call();
    error = null;
    takeNotice = null;
    elapsedSeconds = 0;
    recordingLineId = line.id;
    if (countIn == Duration.zero) {
      _beginCapture(line);
      return;
    }
    isCountingIn = true;
    _countInTimer = Timer(countIn, () {
      isCountingIn = false;
      _countInTimer = null;
      _beginCapture(line);
    });
    notifyListeners();
  }

  void _beginCapture(Line line) {
    if (!isOpen || deviceLost) {
      recordingLineId = null;
      notifyListeners();
      return;
    }
    final (pending, path) = actor.beginTake(
      line,
      inputDeviceName: device?.name,
    );
    try {
      input.startTake(path, channel: channel, preRollMs: _preRollMs);
      _pending = pending;
      elapsedSeconds = 0;
      droppedFrames = 0;
      clippedSamples = 0;
    } catch (e) {
      error = 'Could not start recording: $e';
      recordingLineId = null;
      unawaited(actor.finishTake(pending));
    }
    notifyListeners();
  }

  void _cancelCountIn() {
    _countInTimer?.cancel();
    _countInTimer = null;
    isCountingIn = false;
    recordingLineId = null;
  }

  /// The take finishes a moment later, once the writer has caught up.
  void stopTake() {
    if (isCountingIn) {
      _cancelCountIn();
      notifyListeners();
      return;
    }
    if (!isRecording) return;
    _stopRequestedAt ??= DateTime.now();
    try {
      input.requestStop(trimEndMs: _stopTrimMs);
    } catch (_) {
      // A stop can be refused until the writer picks up the start. Polling
      // tries again, and the take can also end by itself.
    }
  }

  void _poll() {
    final CaptureSnapshot status;
    try {
      status = input.status();
    } catch (e) {
      error = 'Lost contact with the input: $e';
      notifyListeners();
      return;
    }
    activity = status.activity;
    deviceLost = status.deviceLost;
    for (var c = 0; c < meters.length && c < status.peaks.length; c++) {
      meters[c] = status.peaks[c] > meters[c]
          ? status.peaks[c]
          : meters[c] * _peakFalloff;
    }
    if (_pending != null) {
      elapsedSeconds = status.framesWritten / format!.sampleRateHz;
      droppedFrames = status.droppedFrames;
      clippedSamples = status.clippedSamples;
      _checkTakeEnd(status);
    }
    notifyListeners();
  }

  void _checkTakeEnd(CaptureSnapshot status) {
    final stopAt = _stopRequestedAt;
    if (status.activity == CaptureActivity.recording && stopAt != null) {
      if (DateTime.now().difference(stopAt) > _stopTimeout) {
        error = 'The recording did not stop in time.';
        _stopRequestedAt = DateTime.now();
      }
      try {
        input.requestStop(trimEndMs: _stopTrimMs);
      } catch (_) {
        // Still refused. The next poll tries again.
      }
    }
    final ended =
        status.activity == CaptureActivity.armed ||
        status.activity == CaptureActivity.closed;
    if (!ended || _finishing) return;
    unawaited(_finish(status));
  }

  Future<void> _finish(CaptureSnapshot status) async {
    _finishing = true;
    final pending = _pending!;
    final Take? take = await actor.finishTake(
      pending,
      droppedFrames: status.droppedFrames,
      clippedSamples: status.clippedSamples,
    );
    _pending = null;
    recordingLineId = null;
    _stopRequestedAt = null;
    _finishing = false;
    takeNotice = switch (status.lastOutcome) {
      TakeOutcome.ok || TakeOutcome.unknown => null,
      TakeOutcome.deviceLost =>
        take == null
            ? 'The input device stopped before anything was recorded.'
            : 'The input device stopped. What was recorded has been saved.',
      TakeOutcome.sizeLimit =>
        'The take reached the 4 GB WAV limit and was saved.',
      TakeOutcome.diskError => 'The disk could not keep up or is full. What was written has been saved.',
    };
    notifyListeners();
  }

  void _closeDevice() {
    _cancelCountIn();
    _timer?.cancel();
    _timer = null;
    input.close();
    format = null;
    meters = [];
    activity = CaptureActivity.closed;
  }

  /// Closes the device. A take in progress is stopped and saved first.
  Future<void> shutdown() async {
    if (isRecording) {
      stopTake();
      final deadline = DateTime.now().add(_stopTimeout);
      while (isRecording && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(_pollInterval);
      }
    }
    _closeDevice();
  }
}
