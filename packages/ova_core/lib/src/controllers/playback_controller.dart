import 'dart:async';

import '../ports/audio_ports.dart';
import 'notifier.dart';

const _pollInterval = Duration(milliseconds: 50);

/// Plays one take at a time. Screens ask which take is playing to show it.
class PlaybackController extends Notifier {
  PlaybackController(this.output);

  final AudioOutput output;

  String? playingTakeId;
  int positionMs = 0;
  int durationMs = 0;
  String? error;

  Timer? _timer;

  /// Plays a take, or stops it if it's the one already playing.
  void toggle(String takeId, String path) {
    if (playingTakeId == takeId) {
      stop();
      return;
    }
    stop();
    error = null;
    try {
      output.play(path);
      playingTakeId = takeId;
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    } catch (e) {
      error = 'Could not play this take: $e';
    }
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (playingTakeId != null) output.stop();
    playingTakeId = null;
    positionMs = 0;
    durationMs = 0;
    notifyListeners();
  }

  void _poll() {
    final status = output.status();
    if (status.activity != PlaybackActivity.playing) {
      stop();
      return;
    }
    positionMs = status.positionMs;
    durationMs = status.durationMs;
    notifyListeners();
  }
}
