import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ova_core/ova_core.dart';

import '../../services.dart';
import '../common.dart';
import '../shared/role.dart';
import '../shared/take_card.dart';
import 'export_dialog.dart';

const _clipLevel = 0.99;
const _scriptWidth = 320.0;
const _inputColumnWidth = 230.0;
const _inputColumnWidthCompact = 170.0;
const _compactConsoleWidth = 760.0;
const _meterLabelWidth = 66.0;
const _swipeSpeed = 300.0;
const _compactLineTextSize = 24.0;
// Roughly one row in the script list, for opening the sheet near the current line.
const _lineRowEstimate = 76.0;

class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.services,
    required this.projectId,
  });

  final AppServices services;
  final String projectId;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final _actor = ActorController(
    widget.services.workspace,
    widget.projectId,
  );
  late final _input = widget.services.createInput();
  late final _playback = PlaybackController(widget.services.output);
  late final _waveforms = WaveformStore();
  late final _recorder = RecordingController(
    _input,
    _actor,
    onBeforeTake: _playback.stop,
  );
  String? _lineId;
  bool _wasRecording = false;

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_onRecorderChanged);
    _recorder.start();
    _recover();
  }

  /// The script and language locks follow recording. Meters update far more
  /// often, so only a real change rebuilds the whole screen.
  void _onRecorderChanged() {
    if (_recorder.isRecording == _wasRecording || !mounted) return;
    setState(() => _wasRecording = _recorder.isRecording);
  }

  Future<void> _recover() async {
    final recovered = await _actor.recoverInterruptedTakes(_input);
    if (recovered > 0 && mounted) {
      showMessage(
        context,
        'Recovered ${countOf(recovered, 'interrupted take')}.',
      );
    }
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorderChanged);
    _playback.stop();
    _recorder.shutdown();
    super.dispose();
  }

  Line? get _line {
    final lines = _actor.visibleLines;
    return lines.where((l) => l.id == _lineId).firstOrNull ?? lines.firstOrNull;
  }

  void _toggleRecord() {
    final line = _line;
    if (_recorder.isRecording) {
      _recorder.stopTake();
    } else if (line != null) {
      _recorder.startTake(line);
    }
  }

  void _moveLine(int delta) {
    if (_recorder.isRecording) return;
    final lines = _actor.visibleLines;
    final current = lines.indexWhere((l) => l.id == _line?.id);
    final next = current + delta;
    if (current >= 0 && next >= 0 && next < lines.length) {
      setState(() => _lineId = lines[next].id);
    }
  }

  Future<void> _deleteTake(Take take) async {
    final yes = await confirm(
      context,
      title: 'Delete this take?',
      message: 'Its audio is removed from this device and cannot be restored.',
      action: 'Delete',
    );
    if (yes) {
      _playback.stop();
      _actor.deleteTake(take.id);
    }
  }

  void _openScriptSheet() {
    final index = _actor.visibleLines.indexWhere((l) => l.id == _line?.id);
    final scroll = ScrollController(
      initialScrollOffset: index < 2 ? 0 : (index - 1) * _lineRowEstimate,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Watch(
          notifiers: [_actor],
          builder: (context) => _script(
            context,
            scroll: scroll,
            onPicked: () => Navigator.pop(sheetContext),
          ),
        ),
      ),
    ).whenComplete(scroll.dispose);
  }

  void _openInputSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Watch(
        notifiers: [_recorder],
        builder: (context) => _InputSheet(recorder: _recorder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return CallbackShortcuts(
      bindings: {
        // A held key mustn't stop the take it just started.
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
            _toggleRecord,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveLine(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveLine(1),
      },
      child: Focus(
        autofocus: true,
        child: Watch(
          notifiers: [_actor],
          builder: (context) => Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              title: RoleTitle(
                title: _actor.project.title,
                role: AppRole.actor,
              ),
              actions: [
                SoftDropdown<String>(
                  value: _actor.language,
                  onChanged: _recorder.isRecording
                      ? null
                      : (v) => _actor.setLanguage(v ?? _actor.language),
                  items: {for (final l in _actor.project.languages) l: l},
                ),
                if (compact) ...[
                  const SizedBox(width: Space.xs),
                  IconButton(
                    tooltip: 'Export takes',
                    onPressed: () => showExportDialog(
                      context,
                      _actor,
                      widget.services.files,
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  const SizedBox(width: Space.xs),
                ] else ...[
                  const SizedBox(width: Space.m),
                  FilledButton.icon(
                    onPressed: () => showExportDialog(
                      context,
                      _actor,
                      widget.services.files,
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Export takes'),
                  ),
                  const SizedBox(width: Space.l),
                ],
              ],
            ),
            // The console sits in the bottom bar, so messages float above it.
            bottomNavigationBar: compact && _line != null
                ? Watch(
                    notifiers: [_recorder],
                    builder: (context) => _CompactConsole(
                      recorder: _recorder,
                      onToggle: _toggleRecord,
                      onPrevious: () => _moveLine(-1),
                      onNext: () => _moveLine(1),
                      onOpenInput: _openInputSheet,
                    ),
                  )
                : null,
            body: compact
                ? _compactBody(context)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: _scriptWidth, child: _script(context)),
                      Expanded(child: _detail(context)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// One line at a time, with the script a tap away in a sheet.
  Widget _compactBody(BuildContext context) {
    final line = _line;
    final lines = _actor.visibleLines;
    final progress = _actor.progress();
    final done = _doneCount(progress);
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: SoftCard(
            onTap: _recorder.isRecording ? null : _openScriptSheet,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.m,
              vertical: Space.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        line == null
                            ? 'No lines match'
                            : 'Line ${lines.indexWhere((l) => l.id == line.id) + 1} '
                                  'of ${lines.length}',
                        style: theme.labelMedium,
                      ),
                    ),
                    Text(
                      '$done of ${progress.total} done',
                      style: theme.bodySmall,
                    ),
                    const SizedBox(width: Space.xs),
                    const Icon(
                      Icons.format_list_bulleted_rounded,
                      size: 18,
                      color: Palette.accent,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs + 2),
                SegmentBar(
                  segments: [
                    (done, Palette.accent),
                    (progress.total - done, Palette.surfaceSoft),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: line == null
              ? const EmptyState(
                  icon: Icons.format_list_bulleted_rounded,
                  title: 'No line selected',
                  message: 'Open the script above to change the filters.',
                )
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final speed = details.primaryVelocity ?? 0;
                    if (speed < -_swipeSpeed) _moveLine(1);
                    if (speed > _swipeSpeed) _moveLine(-1);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      0,
                      Space.l,
                      Space.m,
                    ),
                    children: _lineContent(context, line, compact: true),
                  ),
                ),
        ),
      ],
    );
  }

  /// Outdated lines and requested retakes still need recording.
  int _doneCount(ProjectProgress progress) =>
      progress.of(LineStatus.recorded) +
      progress.of(LineStatus.submitted) +
      progress.of(LineStatus.approved);

  Widget _script(
    BuildContext context, {
    VoidCallback? onPicked,
    ScrollController? scroll,
  }) {
    final project = _actor.project;
    final lines = _actor.visibleLines;
    final current = _line;
    final progress = _actor.progress();
    final done = _doneCount(progress);
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.xs,
            Space.m,
            Space.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$done of ${countOf(progress.total, 'line')} done',
                style: theme.labelMedium,
              ),
              const SizedBox(height: 6),
              SegmentBar(
                segments: [
                  (done, Palette.accent),
                  (progress.total - done, Palette.surfaceSoft),
                ],
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: SoftDropdown<String?>(
                      value: _actor.characterFilter,
                      expanded: true,
                      onChanged: (v) => _actor.setFilters(
                        character: v,
                        scene: _actor.sceneFilter,
                        status: _actor.statusFilter,
                      ),
                      items: {
                        null: 'All characters',
                        for (final c in project.characters) c.id: c.name,
                      },
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: SoftDropdown<LineStatus?>(
                      value: _actor.statusFilter,
                      expanded: true,
                      onChanged: (v) => _actor.setFilters(
                        character: _actor.characterFilter,
                        scene: _actor.sceneFilter,
                        status: v,
                      ),
                      items: {
                        null: 'Any status',
                        for (final s in const [
                          LineStatus.notRecorded,
                          LineStatus.recorded,
                          LineStatus.submitted,
                          LineStatus.outdated,
                          LineStatus.retakeRequested,
                        ])
                          s: s.label,
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(child: Text('No lines match.', style: theme.bodySmall))
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    Space.s,
                    0,
                    Space.xs,
                    Space.l,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    final previous = index > 0 ? lines[index - 1] : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (index == 0 || previous?.sceneId != line.sceneId)
                          _SceneHeading(
                            project.sceneById(line.sceneId)?.title ??
                                'No scene',
                          ),
                        _LineRow(
                          text: line.text[_actor.language]!.value,
                          character: project.characterById(line.characterId),
                          characterId: line.characterId,
                          status: _actor.statusOf(line),
                          selected: line.id == current?.id,
                          onTap: _recorder.isRecording
                              ? null
                              : () {
                                  setState(() => _lineId = line.id);
                                  onPicked?.call();
                                },
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context) {
    final line = _line;
    if (line == null) {
      return const EmptyState(
        icon: Icons.format_list_bulleted_rounded,
        title: 'No line selected',
        message: 'Choose a line from the script to start recording.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.s,
              Space.xs,
              Space.l,
              Space.l,
            ),
            children: _lineContent(context, line),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.l, Space.l),
          child: Watch(
            notifiers: [_recorder],
            builder: (context) => _RecordConsole(
              recorder: _recorder,
              onToggle: _toggleRecord,
              onPrevious: () => _moveLine(-1),
              onNext: () => _moveLine(1),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _lineContent(
    BuildContext context,
    Line line, {
    bool compact = false,
  }) {
    final project = _actor.project;
    final theme = Theme.of(context).textTheme;
    final scene = project.sceneById(line.sceneId);
    final character = project.characterById(line.characterId);
    final takes = _actor.takesFor(line.id);
    final retakes = _actor.openRetakes(line);
    return [
      SoftCard(
        radius: Corners.xl,
        padding: EdgeInsets.all(compact ? Space.l : Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (scene?.context != null) ...[
              Text(
                scene!.context!,
                style: theme.bodyMedium?.copyWith(color: Palette.inkSoft),
              ),
              const SizedBox(height: Space.l),
            ],
            CharacterBadge(
              id: line.characterId,
              name: character?.name ?? '?',
              large: true,
            ),
            if (character?.description != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(character!.description!, style: theme.bodySmall),
              ),
            const SizedBox(height: Space.m),
            Text(
              line.text[_actor.language]!.value,
              style: compact
                  ? theme.headlineMedium?.copyWith(
                      fontSize: _compactLineTextSize,
                    )
                  : theme.headlineMedium,
            ),
            if (line.direction != null) ...[
              const SizedBox(height: Space.s),
              Text(
                line.direction!,
                style: theme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Palette.accentInk,
                ),
              ),
            ],
            if (line.emotion != null || line.pronunciation != null) ...[
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.xs,
                children: [
                  if (line.emotion != null)
                    TintBadge(
                      line.emotion!,
                      background: Palette.surfaceSoft,
                      foreground: Palette.inkSoft,
                      dot: false,
                    ),
                  if (line.pronunciation != null)
                    TintBadge(
                      'Say: ${line.pronunciation}',
                      background: Palette.surfaceSoft,
                      foreground: Palette.inkSoft,
                      dot: false,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      for (final retake in retakes)
        Notice(
          'Retake requested'
          '${retake.note == null ? '' : ': ${retake.note}'}',
          isError: false,
        ),
      if (takes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(
            left: Space.xs,
            top: Space.xs,
            bottom: Space.s,
          ),
          child: Text(
            '${countOf(takes.length, 'take')}. '
            'Star the ones you like best.',
            style: theme.labelMedium?.copyWith(color: Palette.inkSoft),
          ),
        ),
      Watch(
        notifiers: [_playback, _waveforms],
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_playback.error != null) Notice(_playback.error!),
            for (final (index, take) in takes.indexed)
              _takeCard(take, line, takes.length - index),
          ],
        ),
      ),
    ];
  }

  Widget _takeCard(Take take, Line line, int number) {
    final playing = _playback.playingTakeId == take.id;
    final path = _actor.audioPath(take.id);
    return TakeCard(
      title: 'Take $number · ${formatDuration(take.audio.durationMs)}',
      details: '${take.audio.label} · ${formatClock(take.recordedAt)}',
      peaks: _waveforms.peaksFor(take.id, path),
      playing: playing,
      progress: playing && _playback.durationMs > 0
          ? _playback.positionMs / _playback.durationMs
          : null,
      onPlay: () => _playback.toggle(take.id, path),
      highlighted: take.favorite,
      leading: IconButton(
        tooltip: take.favorite ? 'Remove favorite' : 'Mark as favorite',
        icon: Icon(
          take.favorite ? Icons.star_rounded : Icons.star_border_rounded,
          color: take.favorite ? Palette.accent : Palette.inkFaint,
        ),
        onPressed: () => _actor.toggleFavorite(take.id),
      ),
      badges: [
        if (_actor.session.exportedTakeIds.contains(take.id))
          const TintBadge(
            'Exported',
            background: Palette.infoSoft,
            foreground: Palette.info,
          ),
        if (isOutdated(take, line))
          const TintBadge(
            'Outdated: the line has changed',
            background: Palette.warningSoft,
            foreground: Palette.warning,
          ),
      ],
      warnings: [
        if (take.hasCaptureProblem)
          'Dropped ${take.capture?.droppedFrames ?? 0} frames, '
              'clipped ${take.capture?.clippedSamples ?? 0} samples',
      ],
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline_rounded),
        color: Palette.inkFaint,
        onPressed: () => _deleteTake(take),
      ),
    );
  }
}

class _SceneHeading extends StatelessWidget {
  const _SceneHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.xs),
      child: Text(
        title.toUpperCase(),
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Palette.inkFaint, letterSpacing: 0.6),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.text,
    required this.character,
    required this.characterId,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final Character? character;
  final String characterId;
  final LineStatus status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? Palette.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.m),
          side: selected
              ? const BorderSide(color: Palette.accent, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Corners.m),
          canRequestFocus: false,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.s + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CharacterBadge(
                        id: characterId,
                        name: character?.name ?? '?',
                      ),
                    ),
                    StatusChip(status),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The controls for recording, kept in one place so hands and eyes learn it.
class _RecordConsole extends StatelessWidget {
  const _RecordConsole({
    required this.recorder,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
  });

  final RecordingController recorder;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final busy = recorder.isRecording;
    final recording = busy && !recorder.isCountingIn;
    final canRecord = busy || (recorder.isOpen && !recorder.deviceLost);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recorder.error != null) Notice(recorder.error!),
        if (recorder.takeNotice != null) Notice(recorder.takeNotice!),
        if (recorder.deviceLost)
          Notice(
            'The input device stopped.',
            action: TextButton(
              onPressed: recorder.start,
              child: const Text('Reconnect'),
            ),
          ),
        if (recorder.audioRequestWarning != null)
          Notice(recorder.audioRequestWarning!, isError: false),
        SoftCard(
          radius: Corners.xl,
          color: recording ? Palette.accentSoft : Palette.surface,
          borderColor: recording ? Palette.accent : Palette.line,
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.m,
            Space.m,
            Space.m,
          ),
          // In a small window the meters keep their room and the rest gives way.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactConsoleWidth;
              return Row(
                children: [
                  SizedBox(
                    width: compact
                        ? _inputColumnWidthCompact
                        : _inputColumnWidth,
                    child: _InputColumn(recorder: recorder, compact: compact),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(child: _Meters(recorder: recorder)),
                  const SizedBox(width: Space.l),
                  SizedBox(
                    width: compact ? 56 : 76,
                    child: Text(
                      recording
                          ? '${recorder.elapsedSeconds.toStringAsFixed(1)} s'
                          : '',
                      textAlign: TextAlign.end,
                      style: theme.titleLarge?.copyWith(
                        color: Palette.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Previous line (Up)',
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        onPressed: busy ? null : onPrevious,
                      ),
                      IconButton(
                        tooltip: 'Next line (Down)',
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        onPressed: busy ? null : onNext,
                      ),
                    ],
                  ),
                  const SizedBox(width: Space.xs),
                  RecordButton(
                    recording: recording,
                    label: _recordLabel(recorder),
                    showKey: !compact,
                    actOnPress: busy,
                    onPressed: canRecord ? onToggle : null,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The same controls for a phone: meter and device on top, thumb controls below.
/// A sideways phone gets one row, because height is what it lacks.
class _CompactConsole extends StatelessWidget {
  const _CompactConsole({
    required this.recorder,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenInput,
  });

  final RecordingController recorder;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onOpenInput;

  @override
  Widget build(BuildContext context) {
    final busy = recorder.isRecording;
    final recording = busy && !recorder.isCountingIn;
    final canRecord = busy || (recorder.isOpen && !recorder.deviceLost);
    final short = isShort(context);
    final previous = IconButton(
      tooltip: 'Previous line',
      iconSize: 28,
      icon: const Icon(Icons.chevron_left_rounded),
      onPressed: busy ? null : onPrevious,
    );
    final next = IconButton(
      tooltip: 'Next line',
      iconSize: 28,
      icon: const Icon(Icons.chevron_right_rounded),
      onPressed: busy ? null : onNext,
    );
    final button = RecordButton(
      recording: recording,
      label: _recordLabel(recorder),
      showKey: false,
      showLabel: !short,
      size: short ? 46 : 62,
      actOnPress: busy,
      onPressed: canRecord ? onToggle : null,
    );
    final levels = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _InputSummary(recorder: recorder, onTap: onOpenInput),
        const SizedBox(height: Space.xs),
        _Meters(recorder: recorder, selectedOnly: true),
      ],
    );
    return Material(
      color: recording ? Palette.accentSoft : Palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Corners.xl),
        ),
        side: BorderSide(color: recording ? Palette.accent : Palette.line),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.m,
            Space.s,
            Space.m,
            Space.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recorder.error != null) Notice(recorder.error!),
              if (recorder.takeNotice != null) Notice(recorder.takeNotice!),
              if (recorder.deviceLost)
                Notice(
                  'The input device stopped.',
                  action: TextButton(
                    onPressed: recorder.start,
                    child: const Text('Reconnect'),
                  ),
                ),
              if (recorder.audioRequestWarning != null)
                Notice(recorder.audioRequestWarning!, isError: false),
              if (short)
                Row(
                  children: [
                    previous,
                    const SizedBox(width: Space.xs),
                    Expanded(child: levels),
                    const SizedBox(width: Space.xs),
                    button,
                    next,
                  ],
                )
              else ...[
                levels,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [previous, button, next],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The device in use, or the elapsed time while recording. Opens the input
/// settings, which stay out of the way once they're set.
class _InputSummary extends StatelessWidget {
  const _InputSummary({required this.recorder, required this.onTap});

  final RecordingController recorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final busy = recorder.isRecording;
    final format = recorder.format;
    final summary = [
      recorder.device?.name ?? 'No input devices',
      if (format != null) ...[
        _depthLabel(format),
        formatRate(format.sampleRateHz),
      ],
    ].join(' · ');
    return Tooltip(
      message: 'Input settings',
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.s),
        canRequestFocus: false,
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            children: [
              Icon(
                busy ? Icons.fiber_manual_record_rounded : Icons.mic_rounded,
                size: 16,
                color: Palette.accent,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  recorder.isCountingIn
                      ? 'Starts in a moment'
                      : busy
                      ? '${recorder.elapsedSeconds.toStringAsFixed(1)} s'
                      : summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: busy
                      ? theme.labelLarge?.copyWith(
                          color: Palette.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )
                      : theme.bodySmall,
                ),
              ),
              if (!busy)
                const Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: Palette.inkSoft,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputSheet extends StatelessWidget {
  const _InputSheet({required this.recorder});

  final RecordingController recorder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Input', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.m),
          _InputColumn(recorder: recorder, compact: true, largeSwitch: true),
          const SizedBox(height: Space.m),
          _Meters(recorder: recorder),
        ],
      ),
    );
  }
}

String _recordLabel(RecordingController recorder) => recorder.isCountingIn
    ? 'Get ready'
    : recorder.isRecording
    ? 'Stop'
    : 'Record';

String _depthLabel(InputFormat format) =>
    format.isFloat ? '${format.bitDepth}-bit float' : '${format.bitDepth}-bit';

class _InputColumn extends StatelessWidget {
  const _InputColumn({
    required this.recorder,
    required this.compact,
    this.largeSwitch = false,
  });

  final RecordingController recorder;
  final bool compact;
  final bool largeSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final recording = recorder.isRecording;
    final format = recorder.format;
    final depth = format == null ? '' : _depthLabel(format);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SoftDropdown<int?>(
                value: recorder.device?.index,
                expanded: true,
                fill: recording ? Palette.surface : Palette.surfaceSoft,
                hint: 'No input devices',
                onChanged: recording
                    ? null
                    : (index) => recorder.open(
                        recorder.devices.firstWhere((d) => d.index == index),
                      ),
                items: {for (final d in recorder.devices) d.index: d.name},
              ),
            ),
            IconButton(
              tooltip: 'Look for devices again',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: recording ? null : recorder.start,
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        if (format != null)
          Padding(
            padding: const EdgeInsets.only(left: Space.xs),
            child: Text(
              '$depth · ${formatRate(format.sampleRateHz)} · '
              '${format.rawMode ? 'effects off' : 'effects may be on'}',
              style: theme.bodySmall,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: Space.xs),
                child: Text(
                  'Exclusive mode',
                  style: theme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Transform.scale(
              scale: largeSwitch ? 1 : 0.7,
              alignment: Alignment.centerRight,
              child: Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: recorder.exclusive,
                onChanged: recording ? null : recorder.setExclusive,
              ),
            ),
            SizedBox(width: compact ? 0 : Space.xl + Space.xs),
          ],
        ),
      ],
    );
  }
}

class _Meters extends StatelessWidget {
  const _Meters({required this.recorder, this.selectedOnly = false});

  final RecordingController recorder;

  /// Shows just the channel being recorded, with no channel labels.
  final bool selectedOnly;

  @override
  Widget build(BuildContext context) {
    final recording = recorder.isRecording;
    final clipping = recording && recorder.clippedSamples > 0;
    final labelWidth = selectedOnly ? 0.0 : _meterLabelWidth;
    final channel = recorder.channel;
    final selectedLevel = channel >= 0 && channel < recorder.meters.length
        ? recorder.meters[channel]
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selectedOnly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: LevelMeter(
              level: selectedLevel,
              clipped: selectedLevel >= _clipLevel,
            ),
          )
        else
          for (var c = 0; c < recorder.meters.length; c++)
            _MeterRow(
              channel: c,
              level: recorder.meters[c],
              selected: recorder.channel == c,
              onSelect: recording ? null : () => recorder.selectChannel(c),
            ),
        Padding(
          padding: EdgeInsets.only(left: labelWidth),
          child: const MeterScale(),
        ),
        if (clipping)
          Padding(
            padding: EdgeInsets.only(left: labelWidth, top: Space.xs),
            child: Text(
              'Too loud: this take is clipping. Move back or lower the gain.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Palette.danger),
            ),
          ),
      ],
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.channel,
    required this.level,
    required this.selected,
    required this.onSelect,
  });

  final int channel;
  final double level;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(Corners.s),
      canRequestFocus: false,
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: _meterLabelWidth,
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 14,
                    color: selected ? Palette.accent : Palette.inkFaint,
                  ),
                  const SizedBox(width: Space.xs),
                  Flexible(
                    child: Text(
                      'In ${channel + 1}',
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: selected ? theme.labelMedium : theme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LevelMeter(
                level: level,
                active: selected,
                clipped: level >= _clipLevel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
