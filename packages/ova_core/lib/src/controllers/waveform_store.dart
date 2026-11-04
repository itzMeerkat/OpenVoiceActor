import 'dart:async';
import 'dart:isolate';

import '../format/waveform.dart';
import 'notifier.dart';

Future<List<double>> _load(String path) =>
    Isolate.run(() => readWavPeaks(path));

/// Loads take waveforms in the background and remembers them. Screens ask for
/// one, draw a placeholder until it arrives, and rebuild when notified.
class WaveformStore extends Notifier {
  final _peaks = <String, List<double>>{};
  final _loading = <String>{};

  List<double>? peaksFor(String takeId, String path) {
    final known = _peaks[takeId];
    if (known != null) return known;
    if (_loading.add(takeId)) unawaited(_fetch(takeId, path));
    return null;
  }

  Future<void> _fetch(String takeId, String path) async {
    try {
      _peaks[takeId] = await _load(path);
    } catch (_) {
      // A missing or damaged file just has no picture. Elsewhere it's reported.
      _peaks[takeId] = const [];
    }
    _loading.remove(takeId);
    notifyListeners();
  }
}
