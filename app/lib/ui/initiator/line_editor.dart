import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../common.dart';

/// Adds a line, or edits [line] when given.
Future<void> showLineEditor(
  BuildContext context,
  InitiatorController controller, {
  Line? line,
  required String language,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _LineEditor(controller: controller, line: line, language: language),
  );
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.controller,
    required this.line,
    required this.language,
  });

  final InitiatorController controller;
  final Line? line;
  final String language;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _text = TextEditingController(
    text: widget.line?.text[widget.language]?.value,
  );
  late final _direction = TextEditingController(text: widget.line?.direction);
  late final _emotion = TextEditingController(text: widget.line?.emotion);
  late final _pronunciation = TextEditingController(
    text: widget.line?.pronunciation,
  );
  late String? _characterId =
      widget.line?.characterId ??
      widget.controller.project.characters.firstOrNull?.id;
  late String? _sceneId =
      widget.line?.sceneId ?? widget.controller.project.scenes.lastOrNull?.id;

  InitiatorController get _c => widget.controller;
  bool get _isNew => widget.line == null;

  /// A new line starts in the script's language, so it always has source text.
  String get _language => _isNew ? _c.project.sourceLanguage : widget.language;

  Future<void> _newCharacter() async {
    final name = await askText(
      context,
      title: 'New character',
      label: 'Name',
      action: 'Add',
    );
    if (name == null || name.trim().isEmpty) return;
    final character = _c.addCharacter(name);
    setState(() => _characterId = character.id);
  }

  Future<void> _newScene() async {
    final title = await askText(
      context,
      title: 'New scene',
      label: 'Title',
      action: 'Add',
    );
    if (title == null || title.trim().isEmpty) return;
    final scene = _c.addScene(title);
    setState(() => _sceneId = scene.id);
  }

  Future<void> _save() async {
    final characterId = _characterId;
    final text = _text.text.trim();
    if (characterId == null || text.isEmpty) return;
    final existing = widget.line;
    if (existing == null) {
      _c.addLine(
        characterId: characterId,
        text: text,
        sceneId: _sceneId,
        direction: _direction.text,
        emotion: _emotion.text,
        pronunciation: _pronunciation.text,
      );
    } else {
      var needsNewRecording = true;
      if (_c.textWouldChange(existing.id, _language, text)) {
        final answer = await _askNeedsNewRecording();
        if (answer == null) return;
        needsNewRecording = answer;
      }
      _c.setLineText(
        existing.id,
        _language,
        text,
        needsNewRecording: needsNewRecording,
      );
      _c.updateLineDetails(
        existing.id,
        characterId: characterId,
        sceneId: _sceneId,
        direction: _direction.text,
        emotion: _emotion.text,
        pronunciation: _pronunciation.text,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<bool?> _askNeedsNewRecording() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Does this change need new recording?'),
      content: const Text(
        'If it does, existing takes are marked as outdated. They are kept and '
        'can still be played. Keep them only for a change actors don\'t say '
        'out loud, such as a typo in the displayed text.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep existing takes'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Needs new recording'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final project = _c.project;
    final line = widget.line;
    final source = project.sourceLanguage;
    final sourceText = line?.text[source]?.value;
    final canSave = _characterId != null && _text.text.trim().isNotEmpty;
    final compact = isCompact(context);
    final character = [
      Expanded(
        child: _Picker(
          label: 'Character',
          value: _characterId,
          options: {for (final c in project.characters) c.id: c.name},
          onChanged: (v) => setState(() => _characterId = v),
        ),
      ),
      TextButton(onPressed: _newCharacter, child: const Text('New')),
    ];
    final scene = [
      Expanded(
        child: _Picker(
          label: 'Scene',
          value: _sceneId,
          noneLabel: 'No scene',
          options: {for (final s in project.scenes) s.id: s.title},
          onChanged: (v) => setState(() => _sceneId = v),
        ),
      ),
      TextButton(onPressed: _newScene, child: const Text('New')),
    ];
    final emotion = TextField(
      controller: _emotion,
      decoration: const InputDecoration(labelText: 'Emotion'),
    );
    final pronunciation = TextField(
      controller: _pronunciation,
      decoration: const InputDecoration(
        labelText: 'Pronunciation',
        hintText: 'Mira = MEE-rah',
      ),
    );
    return FormDialog(
      title: _isNew ? 'Add line' : 'Edit ${line!.id}',
      width: 560,
      action: FilledButton(
        onPressed: canSave ? _save : null,
        child: Text(_isNew ? 'Add' : 'Save'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            Row(children: character),
            const SizedBox(height: 12),
            Row(children: scene),
          ] else
            Row(children: [...character, const SizedBox(width: 12), ...scene]),
          const SizedBox(height: 12),
          if (!_isNew && _language != source && sourceText != null) ...[
            Text(
              '$source: $sourceText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
          ],
          TextField(
            controller: _text,
            autofocus: !compact,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: 'Line ($_language)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _direction,
            decoration: const InputDecoration(
              labelText: 'Direction',
              hintText: 'Quietly, to herself.',
            ),
          ),
          const SizedBox(height: 12),
          if (compact) ...[
            emotion,
            const SizedBox(height: 12),
            pronunciation,
          ] else
            Row(
              children: [
                Expanded(child: emotion),
                const SizedBox(width: 12),
                Expanded(child: pronunciation),
              ],
            ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.noneLabel,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final void Function(String?) onChanged;
  final String? noneLabel;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButton<String?>(
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        hint: const Text('Add one first'),
        onChanged: onChanged,
        items: [
          if (noneLabel != null)
            DropdownMenuItem(value: null, child: Text(noneLabel!)),
          for (final entry in options.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}
