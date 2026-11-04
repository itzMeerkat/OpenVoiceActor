import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ova_capture/ova_capture.dart';
import 'package:record/record.dart' as baseline;

const _meterPollInterval = Duration(milliseconds: 50);
const _baselineSeconds = 3;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final baselineDir = args
      .where((a) => a.startsWith('--baseline-test='))
      .map((a) => a.split('=').last)
      .firstOrNull;
  if (baselineDir != null) {
    await _runBaselineTest(baselineDir);
    exit(0);
  }
  runApp(const TestBenchApp());
}

/// Records with the `record` package at each requested setting and reports what
/// was really written. Prints to a file, since a Windows GUI app has no stdout.
Future<void> _runBaselineTest(String dir) async {
  final report = StringBuffer();
  for (final rate in [48000, 96000]) {
    final path = '$dir${Platform.pathSeparator}record_$rate.wav';
    final recorder = baseline.AudioRecorder();
    try {
      await recorder.start(
        baseline.RecordConfig(
          encoder: baseline.AudioEncoder.wav,
          sampleRate: rate,
          numChannels: 1,
        ),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: _baselineSeconds));
      await recorder.stop();
      report.writeln('requested $rate Hz: ${analyzeWav(path)}');
    } catch (e) {
      report.writeln('requested $rate Hz: FAILED $e');
    }
    await recorder.dispose();
  }
  File('$dir${Platform.pathSeparator}baseline_report.txt')
      .writeAsStringSync(report.toString());
}

class TestBenchApp extends StatelessWidget {
  const TestBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OVA Capture Test Bench',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const TestBenchPage(),
    );
  }
}

class Take {
  Take(this.path, this.report, this.status);
  final String path;
  final String report;
  final String status;
}

class TestBenchPage extends StatefulWidget {
  const TestBenchPage({super.key});

  @override
  State<TestBenchPage> createState() => _TestBenchPageState();
}

class _TestBenchPageState extends State<TestBenchPage> {
  final _takes = <Take>[];
  late final Directory _outDir;
  Timer? _timer;

  List<InputDevice> _devices = [];
  int? _deviceIndex;
  bool _exclusive = false;
  int _channel = 0;
  SessionFormat? _session;
  CaptureStatus? _status;
  List<double> _meter = [];
  int _clipsThisTake = 0;
  bool _stopping = false;
  String? _error;
  String? _notice;

  bool get _isOpen => _session != null;
  bool get _isRecording =>
      _status?.state == CaptureState.recording ||
      _status?.state == CaptureState.stopping;

  @override
  void initState() {
    super.initState();
    // A hot restart leaves the native session running.
    Capture.close();
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    _outDir = Directory('$home\\Documents\\OpenVoiceActorPrototype')
      ..createSync(recursive: true);
    _recoverPartials();
    _refreshDevices();
  }

  @override
  void dispose() {
    _timer?.cancel();
    Capture.close();
    super.dispose();
  }

  void _guard(void Function() action) {
    setState(() => _error = null);
    try {
      action();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _recoverPartials() {
    final partials = _outDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.partial'));
    var recovered = 0;
    for (final partial in partials) {
      _guard(() {
        Capture.recoverPartial(partial.path);
        recovered++;
      });
    }
    if (recovered > 0) _notice = 'Recovered $recovered interrupted take(s).';
  }

  void _refreshDevices() {
    _guard(() {
      final devices = Capture.listDevices();
      setState(() {
        _devices = devices;
        _deviceIndex = devices.where((d) => d.isDefault).firstOrNull?.index ??
            devices.firstOrNull?.index;
      });
    });
  }

  void _open() {
    _guard(() {
      Capture.open(deviceIndex: _deviceIndex, exclusive: _exclusive);
      final session = Capture.sessionFormat();
      setState(() {
        _session = session;
        _channel = 0;
        _meter = List.filled(session.channels.clamp(1, 8), 0);
      });
      _timer = Timer.periodic(_meterPollInterval, (_) => _poll());
    });
  }

  void _close() {
    _timer?.cancel();
    Capture.close();
    setState(() {
      _session = null;
      _status = null;
      _meter = [];
    });
  }

  void _poll() {
    final status = Capture.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      if (status.state == CaptureState.recording) {
        _clipsThisTake = status.clippedSamples;
      }
      for (var c = 0; c < _meter.length; c++) {
        // Hold peaks briefly so short transients are visible.
        _meter[c] = status.peaks[c] > _meter[c]
            ? status.peaks[c]
            : _meter[c] * 0.85;
      }
    });
  }

  String _newTakePath() {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${_outDir.path}\\take_$stamp.wav';
  }

  String? _currentPath;

  void _start() {
    _currentPath = null;
    _guard(() {
      final path = _newTakePath();
      Capture.startTake(path, selectedChannel: _channel);
      _currentPath = path;
      _clipsThisTake = 0;
    });
    if (_currentPath != null) unawaited(_watchForTakeEnd());
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    try {
      await Capture.stopTake();
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _stopping = false);
  }

  /// Also covers a take that ends itself, such as when the device is unplugged.
  Future<void> _watchForTakeEnd() async {
    final path = _currentPath!;
    final end = await Capture.waitForTakeEnd();
    if (!mounted) return;
    String report;
    try {
      report = analyzeWav(path).toString();
    } catch (e) {
      report = 'Could not read the file: $e';
    }
    setState(() {
      _takes.insert(
        0,
        Take(
          path,
          report,
          '${end.lastTakeResult.name}, dropped ${end.droppedFrames}, '
              'clipped ${end.clippedSamples}',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('OVA Capture Test Bench')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_notice != null) Text(_notice!),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (status?.deviceLost ?? false)
            Text(
              'The input device stopped. What was recorded has been saved. '
              'Close and reopen the device to continue.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _deviceIndex,
                  hint: const Text('No input devices'),
                  onChanged: _isOpen
                      ? null
                      : (v) => setState(() => _deviceIndex = v),
                  items: [
                    for (final d in _devices)
                      DropdownMenuItem(value: d.index, child: Text(d.name)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh devices',
                onPressed: _isOpen ? null : _refreshDevices,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_deviceIndex != null && _deviceIndex! < _devices.length)
            for (final f in _devices[_deviceIndex!].formats)
              Text('Offers: $f', style: theme.textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exclusive mode'),
            value: _exclusive,
            onChanged: _isOpen ? null : (v) => setState(() => _exclusive = v),
          ),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _isRecording
                    ? null
                    : (_isOpen ? _close : (_deviceIndex == null ? null : _open)),
                child: Text(_isOpen ? 'Close device' : 'Open device'),
              ),
              const SizedBox(width: 12),
              if (session != null) Expanded(child: Text('$session')),
            ],
          ),
          const SizedBox(height: 16),
          for (var c = 0; c < _meter.length; c++) _meterRow(c, theme),
          if (session != null && session.channels > 1)
            Text(
              'Selecting a channel records it as clean mono.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: !_isOpen || _stopping || (status?.deviceLost ?? false)
                    ? null
                    : (_isRecording ? _stop : _start),
                icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                label: Text(_isRecording ? 'Stop' : 'Record'),
              ),
              const SizedBox(width: 12),
              if (_isRecording && session != null)
                Text(
                  '${(status!.framesWritten / session.sampleRate).toStringAsFixed(1)} s'
                  '${_clipsThisTake > 0 ? ' - CLIPPING ($_clipsThisTake samples)' : ''}',
                ),
            ],
          ),
          const Divider(height: 32),
          Text('Takes in ${_outDir.path}', style: theme.textTheme.titleSmall),
          for (final take in _takes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(take.path.split('\\').last),
              subtitle: Text('${take.report}\n${take.status}'),
              trailing: IconButton(
                tooltip: 'Open in default player',
                icon: const Icon(Icons.play_arrow),
                onPressed: () => Process.run('explorer', [take.path]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _meterRow(int channel, ThemeData theme) {
    final level = _meter[channel];
    return Row(
      children: [
        Radio<int>(
          value: channel,
          // ignore: deprecated_member_use
          groupValue: _channel,
          // ignore: deprecated_member_use
          onChanged: _isRecording
              ? null
              : (v) => setState(() => _channel = v ?? 0),
        ),
        Text('Input ${channel + 1}'),
        const SizedBox(width: 12),
        Expanded(
          child: LinearProgressIndicator(
            value: level.clamp(0.0, 1.0),
            color: level >= 0.99 ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}
