import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../common.dart';

Future<void> showScriptImport(
  BuildContext context,
  InitiatorController controller,
  ScriptPreview preview,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ScriptImportDialog(controller, preview),
  );
}

Future<void> showTranslationImport(
  BuildContext context,
  InitiatorController controller,
  TranslationPreview preview,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TranslationImportDialog(controller, preview),
  );
}

/// One changed line with its "needs new recording" choice.
class _ChangeTile extends StatelessWidget {
  const _ChangeTile({
    required this.oldText,
    required this.newText,
    required this.needsRecording,
    required this.onChanged,
  });

  final String oldText;
  final String newText;
  final bool needsRecording;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final was = Text(
      'Was: $oldText',
      style: const TextStyle(decoration: TextDecoration.lineThrough),
    );
    return CheckboxListTile(
      dense: true,
      contentPadding: compact ? EdgeInsets.zero : null,
      title: Text(newText),
      // Beside the text there's no room on a phone, so the label goes under it.
      subtitle: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [was, const Text('Needs new recording')],
            )
          : was,
      secondary: compact ? null : const Text('New recording'),
      value: needsRecording,
      onChanged: (v) => onChanged(v ?? true),
    );
  }
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 4),
  child: Text(text, style: Theme.of(context).textTheme.titleSmall),
);

Widget _errorList(BuildContext context, List<String> errors) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _heading(context, 'Fix these in the file first'),
    for (final error in errors)
      Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  ],
);

class _ScriptImportDialog extends StatefulWidget {
  const _ScriptImportDialog(this.controller, this.preview);

  final InitiatorController controller;
  final ScriptPreview preview;

  @override
  State<_ScriptImportDialog> createState() => _ScriptImportDialogState();
}

class _ScriptImportDialogState extends State<_ScriptImportDialog> {
  /// Ids the initiator says don't need new recording. Empty means all do.
  final _keep = <String>{};
  final _retire = <String>{};

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    int count(ScriptRowKind kind) => preview.ofKind(kind).length;
    final changed = preview.ofKind(ScriptRowKind.textChanged).toList();
    return FormDialog(
      title: 'Import script',
      width: 640,
      action: FilledButton(
        onPressed: preview.canApply
            ? () {
                widget.controller.applyScript(
                  preview,
                  keepRecordings: _keep,
                  retire: _retire,
                );
                Navigator.pop(context);
              }
            : null,
        child: const Text('Apply'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${count(ScriptRowKind.added)} new, '
            '${changed.length} changed text, '
            '${count(ScriptRowKind.detailsChanged)} changed details, '
            '${count(ScriptRowKind.restored)} restored, '
            '${count(ScriptRowKind.unchanged)} unchanged.',
          ),
          if (preview.errors.isNotEmpty) _errorList(context, preview.errors),
          if (changed.isNotEmpty) ...[
            _heading(context, 'Changed text'),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => setState(_keep.clear),
                  child: const Text('All need new recording'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _keep.addAll(changed.map((r) => r.lineId!)),
                  ),
                  child: const Text('Keep all takes'),
                ),
              ],
            ),
            for (final row in changed)
              _ChangeTile(
                oldText: row.oldText ?? '',
                newText: row.text,
                needsRecording: !_keep.contains(row.lineId),
                onChanged: (needs) => setState(() {
                  needs ? _keep.remove(row.lineId) : _keep.add(row.lineId!);
                }),
              ),
          ],
          if (preview.missing.isNotEmpty) ...[
            _heading(
              context,
              'Not in this file. Lines are never deleted, but you can retire them.',
            ),
            for (final line in preview.missing)
              CheckboxListTile(
                dense: true,
                title: Text(
                  line.text[widget.controller.project.sourceLanguage]?.value ??
                      line.id,
                ),
                subtitle: Text(line.id),
                secondary: const Text('Retire'),
                value: _retire.contains(line.id),
                onChanged: (v) => setState(() {
                  v == true ? _retire.add(line.id) : _retire.remove(line.id);
                }),
              ),
          ],
        ],
      ),
    );
  }
}

class _TranslationImportDialog extends StatefulWidget {
  const _TranslationImportDialog(this.controller, this.preview);

  final InitiatorController controller;
  final TranslationPreview preview;

  @override
  State<_TranslationImportDialog> createState() =>
      _TranslationImportDialogState();
}

class _TranslationImportDialogState extends State<_TranslationImportDialog> {
  final _keep = <String>{};

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final changed = preview.changes.where((c) => c.isChange).toList();
    final added = preview.changes.length - changed.length;
    return FormDialog(
      title: 'Import ${preview.language} translation',
      width: 640,
      action: FilledButton(
        onPressed: preview.canApply
            ? () {
                widget.controller.applyTranslation(
                  preview,
                  keepRecordings: _keep,
                );
                Navigator.pop(context);
              }
            : null,
        child: const Text('Apply'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$added new, ${changed.length} changed, '
            '${preview.unchangedCount} unchanged.',
          ),
          if (preview.errors.isNotEmpty) _errorList(context, preview.errors),
          if (preview.unknownIds.isNotEmpty) ...[
            _heading(context, 'Unknown ids, which will not be imported'),
            Text(preview.unknownIds.join(', ')),
          ],
          if (changed.isNotEmpty) ...[
            _heading(context, 'Changed text'),
            for (final row in changed)
              _ChangeTile(
                oldText: row.oldText ?? '',
                newText: row.text,
                needsRecording: !_keep.contains(row.lineId),
                onChanged: (needs) => setState(() {
                  needs ? _keep.remove(row.lineId) : _keep.add(row.lineId);
                }),
              ),
          ],
        ],
      ),
    );
  }
}
