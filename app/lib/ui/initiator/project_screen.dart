import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../../services.dart';
import '../common.dart';
import '../shared/role.dart';
import 'line_editor.dart';
import 'review_tab.dart';
import 'script_tab.dart';
import 'setup_tab.dart';

enum _Tab { script, review, setup }

class InitiatorProjectScreen extends StatefulWidget {
  const InitiatorProjectScreen({
    super.key,
    required this.services,
    required this.projectId,
  });

  final AppServices services;
  final String projectId;

  @override
  State<InitiatorProjectScreen> createState() => _InitiatorProjectScreenState();
}

class _InitiatorProjectScreenState extends State<InitiatorProjectScreen> {
  late final _controller = InitiatorController(
    widget.services.workspace,
    widget.projectId,
    freeSpace: widget.services.freeSpace,
  );
  late final _playback = PlaybackController(widget.services.output);
  late String _language = _controller.project.sourceLanguage;
  _Tab _tab = _Tab.script;

  @override
  void dispose() {
    _playback.stop();
    super.dispose();
  }

  Future<void> _export() async {
    final path = await widget.services.files.pickSaveLocation(
      fileNameFor(_controller.project.title),
      'OpenVoiceActor project',
      'ovaproject',
    );
    if (path == null || !mounted) return;
    await guarded(context, () async {
      await _controller.exportPackage(path);
      if (mounted) {
        showMessage(
          context,
          'Exported revision ${_controller.project.revision}. '
          'Send this file to your actors.',
        );
      }
    });
  }

  void _selectTab(_Tab tab) {
    _playback.stop();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Watch(
      notifiers: [_controller],
      builder: (context) {
        final project = _controller.project;
        // A language removed in Setup can't stay selected.
        if (!project.languages.contains(_language)) {
          _language = project.sourceLanguage;
        }
        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: RoleTitle(title: project.title, role: AppRole.owner),
                ),
                if (!compact) ...[
                  const SizedBox(width: Space.l),
                  PillTabs<_Tab>(
                    value: _tab,
                    options: const {
                      _Tab.script: 'Script',
                      _Tab.review: 'Review',
                      _Tab.setup: 'Setup',
                    },
                    onChanged: _selectTab,
                  ),
                ],
              ],
            ),
            actions: [
              SoftDropdown<String>(
                value: _language,
                onChanged: (v) => setState(() => _language = v ?? _language),
                items: {for (final l in project.languages) l: l},
              ),
              if (compact) ...[
                const SizedBox(width: Space.xs),
                IconButton(
                  tooltip: 'Export project',
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share_rounded),
                ),
                const SizedBox(width: Space.xs),
              ] else ...[
                const SizedBox(width: Space.m),
                FilledButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Export project'),
                ),
                const SizedBox(width: Space.l),
              ],
            ],
          ),
          floatingActionButton: compact && _tab == _Tab.script
              ? FloatingActionButton.extended(
                  onPressed: () =>
                      showLineEditor(context, _controller, language: _language),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add line'),
                )
              : null,
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) => _selectTab(_Tab.values[i]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.notes_rounded),
                      label: 'Script',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.headphones_rounded),
                      label: 'Review',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_rounded),
                      label: 'Setup',
                    ),
                  ],
                )
              : null,
          body: switch (_tab) {
            _Tab.script => ScriptTab(
              controller: _controller,
              services: widget.services,
              language: _language,
            ),
            _Tab.review => ReviewTab(
              controller: _controller,
              playback: _playback,
              services: widget.services,
              language: _language,
            ),
            _Tab.setup => SetupTab(controller: _controller),
          },
        );
      },
    );
  }
}
