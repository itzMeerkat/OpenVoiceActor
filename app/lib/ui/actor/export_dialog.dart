import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../../services.dart';
import '../common.dart';

Future<void> showExportDialog(
  BuildContext context,
  ActorController actor,
  FilePicker files,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(actor, files),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog(this.actor, this.files);

  final ActorController actor;
  final FilePicker files;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late final _name = TextEditingController(
    text: widget.actor.settings.displayName,
  );
  late final _credit = TextEditingController(
    text: widget.actor.settings.creditName,
  );
  bool _favoritesOnly = true;
  bool _includeExported = false;
  bool _includeDevice = false;
  bool _accepted = false;

  ExportOptions get _options => ExportOptions(
    favoritesOnly: _favoritesOnly,
    includeAlreadyExported: _includeExported,
    includeDeviceName: _includeDevice,
  );

  Future<void> _export() async {
    final actor = widget.actor;
    final title = fileNameFor(actor.project.title);
    final name = fileNameFor(_name.text);
    final path = await widget.files.pickSaveLocation(
      '$title $name',
      'OpenVoiceActor submission',
      'ovasubmission',
    );
    if (path == null || !mounted) return;
    await guarded(context, () async {
      actor.setActorNames(displayName: _name.text, creditName: _credit.text);
      if (_accepted) actor.acceptTerms();
      final report = await withProgress(
        context,
        'Packaging takes...',
        () => actor.exportSubmission(path, options: _options),
      );
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        report.skipped.isEmpty
            ? 'Exported ${countOf(report.exportedCount, 'take')}. Send this file back to the project owner.'
            : 'Exported ${countOf(report.exportedCount, 'take')}. '
                  'Left out ${report.skipped.length} because the audio is missing '
                  'or changed.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.actor;
    final terms = actor.project.usageTerms;
    final needsTerms = actor.termsNeedAcceptance;
    final takes = actor.takesToExport(_options);
    final canExport =
        takes.isNotEmpty &&
        _name.text.trim().isNotEmpty &&
        (!needsTerms || _accepted);
    return FormDialog(
      title: 'Export takes',
      width: 520,
      action: FilledButton(
        onPressed: canExport ? _export : null,
        child: const Text('Export'),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _credit,
            decoration: const InputDecoration(
              labelText: 'Name in the credits (optional)',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Favorites only'),
            subtitle: const Text('Turn off to send every take'),
            value: _favoritesOnly,
            onChanged: (v) => setState(() => _favoritesOnly = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include takes already exported'),
            value: _includeExported,
            onChanged: (v) => setState(() => _includeExported = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include my input device name'),
            subtitle: const Text('Helps diagnose audio problems'),
            value: _includeDevice,
            onChanged: (v) => setState(() => _includeDevice = v),
          ),
          if (terms != null && needsTerms) ...[
            const SizedBox(height: 12),
            Text('Usage terms', style: Theme.of(context).textTheme.titleSmall),
            Text(terms.text),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I accept these terms'),
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            takes.isEmpty
                ? 'Nothing to export with these settings. Mark takes as '
                      'favorites with the star, or turn off "Favorites only".'
                : '${countOf(takes.length, 'take')}, about '
                      '${formatBytes(actor.exportSizeBytes(_options))}.',
          ),
        ],
      ),
    );
  }
}
