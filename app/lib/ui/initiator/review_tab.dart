import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../../services.dart';
import '../common.dart';
import '../shared/take_card.dart';

const _listWidth = 340.0;
// Tight enough that both toolbar labels stay on one line on the smallest phones.
const _compactButtonPadding = EdgeInsets.symmetric(
  horizontal: Space.s,
  vertical: Space.m,
);

class ReviewTab extends StatefulWidget {
  const ReviewTab({
    super.key,
    required this.controller,
    required this.playback,
    required this.services,
    required this.language,
  });

  final InitiatorController controller;
  final PlaybackController playback;
  final AppServices services;
  final String language;

  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  final _waveforms = WaveformStore();
  String? _lineId;

  InitiatorController get _c => widget.controller;

  Future<void> _importSubmission() async {
    final path = await widget.services.files.pickFile(
      'OpenVoiceActor submission',
      ['ovasubmission'],
    );
    if (path == null || !mounted) return;
    await guarded(context, () async {
      final report = await withProgress(
        context,
        'Importing takes...',
        () => _c.importSubmission(path),
      );
      if (mounted) await _showReport(report);
    });
  }

  Future<void> _showReport(SubmissionImportReport report) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Takes from ${report.actorName}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.importedCount} imported, '
                '${report.alreadyImported} already here.',
              ),
              if (report.unassigned.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Text(
                    '${report.unassigned.length} are for lines not in this '
                    'project. They are kept and listed at the end of Review.',
                  ),
                ),
              if (report.rejected.isNotEmpty) ...[
                const SizedBox(height: Space.m),
                Text('${report.rejected.length} could not be imported:'),
                for (final rejected in report.rejected)
                  Text(
                    '${rejected.takeId}: ${rejected.reason}',
                    style: const TextStyle(color: Palette.danger),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _exportSelected() async {
    final folder = await widget.services.files.pickFolder();
    if (folder == null || !mounted) return;
    await guarded(context, () async {
      final count = await withProgress(
        context,
        'Copying takes...',
        () => _c.exportSelectedTakes(folder),
      );
      if (mounted) {
        showMessage(
          context,
          'Copied ${countOf(count, 'take')}, with mapping.csv.',
        );
      }
    });
  }

  /// On a phone a line's takes get their own page, with a way through the script
  /// that doesn't need a trip back to the list.
  Future<void> _openLine(List<Line> lines, Line line) async {
    var index = lines.indexWhere((l) => l.id == line.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, setPageState) {
            void move(int delta) {
              widget.playback.stop();
              setPageState(() => index += delta);
            }

            return Scaffold(
              appBar: AppBar(
                title: Text('Line ${index + 1} of ${lines.length}'),
              ),
              body: Watch(
                notifiers: [_c, widget.playback, _waveforms],
                builder: (context) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.xs,
                    Space.l,
                    Space.l,
                  ),
                  children: [
                    if (widget.playback.error != null)
                      Notice(widget.playback.error!),
                    ..._lineDetail(context, lines[index]),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.xs,
                    Space.l,
                    Space.s,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: index > 0 ? () => move(-1) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Previous'),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: index + 1 < lines.length
                              ? () => move(1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          iconAlignment: IconAlignment.end,
                          label: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    widget.playback.stop();
  }

  Future<void> _requestRetake(ReviewTake take) async {
    final note = await askText(
      context,
      title: 'Request a retake from ${take.actor.displayName}',
      label: 'What should change?',
      action: 'Request',
      maxLines: 3,
    );
    if (note == null) return;
    _c.requestRetake(take, note);
    if (mounted) {
      showMessage(
        context,
        'Requested. It reaches the actor with your next export.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _c.project;
    final lines = [
      for (final line in project.orderedLines())
        if (line.text.containsKey(widget.language)) line,
    ];
    final selected = project.lineById(_lineId ?? '') ?? lines.firstOrNull;
    final compact = isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compact ? _compactToolbar(context) : _toolbar(context),
        Expanded(
          child: lines.isEmpty && _c.unassignedTakes.isEmpty
              ? EmptyState(
                  icon: Icons.headphones_rounded,
                  title: 'Nothing to review yet',
                  message:
                      'There are no lines in ${widget.language}. Add lines in '
                      'Script, then send the project to your actors.',
                )
              : compact
              ? Watch(
                  notifiers: [widget.playback, _waveforms],
                  builder: (context) => ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s,
                      0,
                      Space.s,
                      Space.l,
                    ),
                    children: [
                      for (final line in lines)
                        _ReviewRow(
                          line: line,
                          controller: _c,
                          language: widget.language,
                          selected: false,
                          onTap: () => _openLine(lines, line),
                        ),
                      if (_c.unassignedTakes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.s,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _unassigned(context),
                          ),
                        ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _listWidth,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          Space.s,
                          0,
                          Space.xs,
                          Space.l,
                        ),
                        children: [
                          for (final line in lines)
                            _ReviewRow(
                              line: line,
                              controller: _c,
                              language: widget.language,
                              selected: line.id == selected?.id,
                              onTap: () => setState(() => _lineId = line.id),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Watch(
                        notifiers: [widget.playback, _waveforms],
                        builder: (context) => ListView(
                          padding: const EdgeInsets.fromLTRB(
                            Space.s,
                            0,
                            Space.l,
                            Space.l,
                          ),
                          children: [
                            if (widget.playback.error != null)
                              Notice(widget.playback.error!),
                            if (selected != null)
                              ..._lineDetail(context, selected),
                            if (_c.unassignedTakes.isNotEmpty)
                              ..._unassigned(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _compactToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _progress(context),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: _compactButtonPadding),
                  onPressed: _importSubmission,
                  icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
                  label: const Text('Import takes'),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: _compactButtonPadding,
                  ),
                  onPressed: _c.review.selections.isEmpty
                      ? null
                      : _exportSelected,
                  child: const Text('Export selected'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _importSubmission,
            icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
            label: const Text('Import submission'),
          ),
          const SizedBox(width: Space.s),
          OutlinedButton(
            onPressed: _c.review.selections.isEmpty ? null : _exportSelected,
            child: const Text('Export selected takes for the game'),
          ),
          const SizedBox(width: Space.xl),
          Expanded(child: _progress(context)),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final progress = _c.progress(widget.language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${progress.of(LineStatus.approved)} of ${progress.total} '
          'approved in ${widget.language}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        SegmentBar(
          segments: [
            (progress.of(LineStatus.approved), Palette.meterGood),
            (progress.of(LineStatus.submitted), Palette.info),
            (progress.of(LineStatus.outdated), Palette.meterHot),
            (progress.of(LineStatus.retakeRequested), Palette.accent),
            (progress.of(LineStatus.notRecorded), Palette.surfaceSoft),
          ],
        ),
      ],
    );
  }

  List<Widget> _lineDetail(BuildContext context, Line line) {
    final theme = Theme.of(context).textTheme;
    final takes = _c.takesFor(line.id, widget.language);
    final selection = _c.review.selectionFor(line.id, widget.language);
    final retakes = _c.openRetakes(line.id, widget.language);
    final character = _c.project.characterById(line.characterId);
    return [
      SoftCard(
        radius: Corners.xl,
        padding: EdgeInsets.all(isCompact(context) ? Space.l : Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CharacterBadge(
              id: line.characterId,
              name: character?.name ?? '?',
              large: true,
            ),
            const SizedBox(height: Space.m),
            Text(
              line.text[widget.language]?.value ?? '',
              style: theme.headlineSmall,
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${line.id} · text version '
              '${line.text[widget.language]?.version}',
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      for (final retake in retakes)
        Notice(
          'Retake requested${retake.note == null ? '' : ': ${retake.note}'}',
          isError: false,
          action: TextButton(
            onPressed: () => _c.cancelRetake(retake.id),
            child: const Text('Cancel'),
          ),
        ),
      if (takes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Text('No takes yet.', style: theme.bodySmall),
        ),
      for (final take in takes)
        _takeCard(take, line, selection?.takeId == take.take.id),
    ];
  }

  Widget _takeCard(ReviewTake reviewTake, Line? line, bool isSelected) {
    final take = reviewTake.take;
    final playback = widget.playback;
    final playing = playback.playingTakeId == take.id;
    final path = _c.audioPath(reviewTake);
    return TakeCard(
      title: reviewTake.actor.displayName,
      details: '${formatDuration(take.audio.durationMs)} · ${take.audio.label}',
      peaks: _waveforms.peaksFor(take.id, path),
      playing: playing,
      progress: playing && playback.durationMs > 0
          ? playback.positionMs / playback.durationMs
          : null,
      onPlay: () => playback.toggle(take.id, path),
      highlighted: isSelected,
      badges: [
        if (isSelected)
          const TintBadge(
            'Final take',
            background: Palette.accent,
            foreground: Colors.white,
          ),
        if (take.favorite)
          const TintBadge(
            "Actor's favorite",
            background: Palette.accentSoft,
            foreground: Palette.accentInk,
          ),
        if (isOutdated(take, line))
          TintBadge(
            'Outdated. Recorded as: ${take.spokenText}',
            background: Palette.warningSoft,
            foreground: Palette.warning,
          )
        else if (spokenTextDiffers(take, line))
          TintBadge(
            'Wording when recorded: ${take.spokenText}',
            background: Palette.surfaceSoft,
            foreground: Palette.inkSoft,
          ),
      ],
      warnings: [
        if (take.hasCaptureProblem)
          'Dropped ${take.capture?.droppedFrames ?? 0} frames, '
              'clipped ${take.capture?.clippedSamples ?? 0} samples',
      ],
      actions: [
        if (line != null) ...[
          TextButton(
            onPressed: () => _requestRetake(reviewTake),
            child: const Text('Request retake'),
          ),
          const SizedBox(width: Space.xs),
          isSelected
              ? OutlinedButton(
                  onPressed: () => _c.clearSelection(line.id, widget.language),
                  child: const Text('Unselect'),
                )
              : FilledButton(
                  onPressed: () => _c.selectTake(reviewTake),
                  child: const Text('Select'),
                ),
        ],
      ],
    );
  }

  List<Widget> _unassigned(BuildContext context) => [
    const SizedBox(height: Space.xl),
    Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Text(
        'Takes for lines not in this project',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    for (final take in _c.unassignedTakes) _takeCard(take, null, false),
  ];
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.line,
    required this.controller,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final Line line;
  final InitiatorController controller;
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final character = controller.project.characterById(line.characterId);
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
                        id: line.characterId,
                        name: character?.name ?? '?',
                      ),
                    ),
                    StatusChip(controller.statusOf(line, language)),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  line.text[language]!.value,
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
