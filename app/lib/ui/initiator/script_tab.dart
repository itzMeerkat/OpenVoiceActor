import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../../services.dart';
import '../common.dart';
import 'import_dialogs.dart';
import 'line_editor.dart';

const _contentWidth = 960.0;

class ScriptTab extends StatefulWidget {
  const ScriptTab({
    super.key,
    required this.controller,
    required this.services,
    required this.language,
  });

  final InitiatorController controller;
  final AppServices services;
  final String language;

  @override
  State<ScriptTab> createState() => _ScriptTabState();
}

class _ScriptTabState extends State<ScriptTab> {
  bool _showRetired = false;

  InitiatorController get _c => widget.controller;
  String get _title => fileNameFor(_c.project.title);

  Future<void> _importScript() async {
    final path = await widget.services.files.pickFile('CSV', ['csv']);
    if (path == null || !mounted) return;
    await guarded(context, () async {
      final preview = _c.previewScript(await readCsvFile(path));
      if (mounted) await showScriptImport(context, _c, preview);
    });
  }

  Future<void> _importTranslation() async {
    final language = await askText(
      context,
      title: 'Which language is this translation?',
      label: 'Language tag, such as ja or zh-Hans',
      initial: widget.language == _c.project.sourceLanguage
          ? ''
          : widget.language,
      action: 'Choose file',
    );
    if (language == null || language.trim().isEmpty || !mounted) return;
    final path = await widget.services.files.pickFile('CSV', ['csv']);
    if (path == null || !mounted) return;
    await guarded(context, () async {
      final preview = _c.previewTranslation(
        language.trim(),
        await readCsvFile(path),
      );
      if (mounted) await showTranslationImport(context, _c, preview);
    });
  }

  Future<void> _saveCsv(String suggestedName, String Function() content) async {
    final path = await widget.services.files.pickSaveLocation(
      suggestedName,
      'CSV',
      'csv',
    );
    if (path == null || !mounted) return;
    await guarded(context, () async {
      await File(path).writeAsString(content());
      if (mounted) showMessage(context, 'Saved.');
    });
  }

  void _addLine() => showLineEditor(context, _c, language: widget.language);

  @override
  Widget build(BuildContext context) {
    final project = _c.project;
    final lines = project.orderedLines(includeRetired: _showRetired);
    final compact = isCompact(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              _compactToolbar(context, lines.length)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.s,
                  Space.l,
                  Space.m,
                ),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add line'),
                    ),
                    const SizedBox(width: Space.s),
                    _CsvMenu(
                      label: 'Import',
                      items: {
                        'Script CSV': _importScript,
                        'Translation CSV': _importTranslation,
                      },
                    ),
                    const SizedBox(width: Space.s),
                    _CsvMenu(
                      label: 'Export CSV',
                      items: {
                        'Script': () =>
                            _saveCsv('$_title script', () => _c.scriptCsv()),
                        'Translation sheet (${widget.language})': () =>
                            _saveCsv(
                              '$_title ${widget.language}',
                              () => _c.translationTemplate(widget.language),
                            ),
                      },
                    ),
                    const Spacer(),
                    Text(
                      'Show retired',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Switch(
                      value: _showRetired,
                      onChanged: (v) => setState(() => _showRetired = v),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: lines.isEmpty
                  ? EmptyState(
                      icon: Icons.edit_note_rounded,
                      title: 'Your script is empty',
                      message:
                          'Add lines one at a time, or import a whole script '
                          'from a CSV file.',
                      action: OutlinedButton(
                        onPressed: _importScript,
                        child: const Text('Import a script'),
                      ),
                    )
                  : ListView.builder(
                      // On a phone the last line clears the Add line button.
                      padding: EdgeInsets.fromLTRB(
                        Space.l,
                        0,
                        Space.l,
                        compact ? 88 : Space.xl,
                      ),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final previous = index > 0 ? lines[index - 1] : null;
                        final next = index + 1 < lines.length
                            ? lines[index + 1]
                            : null;
                        final first =
                            index == 0 || previous?.sceneId != line.sceneId;
                        final last =
                            next == null || next.sceneId != line.sceneId;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (first) _sceneHeading(context, line.sceneId),
                            _ScriptRow(
                              line: line,
                              controller: _c,
                              language: widget.language,
                              first: first,
                              last: last,
                              compact: compact,
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The less frequent actions share one menu, leaving the screen to the script.
  Widget _compactToolbar(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: Space.l + Space.xs, right: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              countOf(count, 'line'),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Palette.inkSoft),
            ),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Import, export and view options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _importScript,
                child: const Text('Import script CSV'),
              ),
              PopupMenuItem(
                value: _importTranslation,
                child: const Text('Import translation CSV'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: () => _saveCsv('$_title script', () => _c.scriptCsv()),
                child: const Text('Export script CSV'),
              ),
              PopupMenuItem(
                value: () => _saveCsv(
                  '$_title ${widget.language}',
                  () => _c.translationTemplate(widget.language),
                ),
                child: Text('Export translation sheet (${widget.language})'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: () => setState(() => _showRetired = !_showRetired),
                checked: _showRetired,
                child: const Text('Show retired'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sceneHeading(BuildContext context, String? sceneId) {
    final theme = Theme.of(context).textTheme;
    final scene = _c.project.sceneById(sceneId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scene?.title ?? 'No scene', style: theme.titleMedium),
          if (scene?.context != null)
            Text(scene!.context!, style: theme.bodySmall),
        ],
      ),
    );
  }
}

class _CsvMenu extends StatelessWidget {
  const _CsvMenu({required this.label, required this.items});

  final String label;
  final Map<String, VoidCallback> items;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, menu, _) => OutlinedButton.icon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.expand_more_rounded, size: 18),
        iconAlignment: IconAlignment.end,
        label: Text(label),
      ),
      menuChildren: [
        for (final entry in items.entries)
          MenuItemButton(onPressed: entry.value, child: Text(entry.key)),
      ],
    );
  }
}

/// Lines in a scene join up into one card, so scenes read as blocks.
class _ScriptRow extends StatelessWidget {
  const _ScriptRow({
    required this.line,
    required this.controller,
    required this.language,
    required this.first,
    required this.last,
    required this.compact,
  });

  final Line line;
  final InitiatorController controller;
  final String language;
  final bool first;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final text = line.text[language]?.value;
    final project = controller.project;
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? Corners.l : 0),
      bottom: Radius.circular(last ? Corners.l : 0),
    );
    final badge = CharacterBadge(
      id: line.characterId,
      name: project.characterById(line.characterId)?.name ?? '?',
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text ?? 'No text in $language yet',
          style: text == null
              ? theme.bodyMedium?.copyWith(
                  color: Palette.inkFaint,
                  fontStyle: FontStyle.italic,
                )
              : theme.bodyLarge?.copyWith(
                  color: line.retired ? Palette.inkFaint : Palette.ink,
                ),
        ),
        Text(
          [line.id, if (line.retired) 'retired', ?line.direction].join(' · '),
          style: theme.bodySmall,
        ),
      ],
    );
    final retire = IconButton(
      tooltip: line.retired ? 'Restore' : 'Retire',
      color: Palette.inkFaint,
      visualDensity: compact ? VisualDensity.compact : null,
      icon: Icon(
        line.retired ? Icons.restore_rounded : Icons.archive_outlined,
        size: 20,
      ),
      onPressed: () => controller.setRetired(line.id, !line.retired),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border(
          left: const BorderSide(color: Palette.line),
          right: const BorderSide(color: Palette.line),
          top: first ? const BorderSide(color: Palette.line) : BorderSide.none,
          bottom: const BorderSide(color: Palette.line),
        ),
      ),
      child: Material(
        color: line.retired ? Palette.surfaceSoft : Palette.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: line.retired
              ? null
              : () => showLineEditor(
                  context,
                  controller,
                  line: line,
                  language: language,
                ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? Space.m : Space.l,
              vertical: compact ? Space.s : Space.s + 2,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: badge),
                          retire,
                        ],
                      ),
                      words,
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(width: 130, child: badge),
                      const SizedBox(width: Space.m),
                      Expanded(child: words),
                      retire,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
