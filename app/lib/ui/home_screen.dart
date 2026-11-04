import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../services.dart';
import 'actor/record_screen.dart';
import 'common.dart';
import 'initiator/project_screen.dart';
import 'shared/role.dart';

const _sidebarWidth = 264.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _home = HomeController(widget.services.workspace);

  Future<void> _createProject() async {
    final result = await showDialog<_NewProject>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (result == null || !mounted) return;
    await guarded(context, () async {
      final project = _home.createProject(
        title: result.title,
        sourceLanguage: result.language,
      );
      await _openInitiator(project.id);
    });
  }

  Future<void> _openInitiator(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InitiatorProjectScreen(services: widget.services, projectId: id),
      ),
    );
    _home.refresh();
  }

  Future<void> _openActor(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordScreen(services: widget.services, projectId: id),
      ),
    );
    _home.refresh();
  }

  Future<void> _importProject() async {
    final path = await widget.services.files.pickFile(
      'OpenVoiceActor project',
      ['ovaproject'],
    );
    if (path == null || !mounted) return;
    await guarded(context, () async {
      final result = await _home.importProject(path);
      if (!mounted) return;
      final title = result.project.title;
      showMessage(context, switch (result.outcome) {
        ProjectImportOutcome.added => 'Added "$title".',
        ProjectImportOutcome.updated =>
          'Updated "$title". Your takes were kept.',
        ProjectImportOutcome.unchanged => 'You already have this version.',
        ProjectImportOutcome.refusedOlder =>
          'This file is older than your copy of "$title", so it was not imported.',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Watch(
      notifiers: [_home],
      builder: (context) {
        final role = _home.role;
        final owner = role == AppRole.owner;
        final projects = owner ? _home.initiatorProjects : _home.actorProjects;
        final actionIcon = owner ? Icons.add_rounded : Icons.file_open_outlined;
        final actionLabel = owner ? 'New project' : 'Import project';
        final onAction = owner ? _createProject : _importProject;
        return Scaffold(
          resizeToAvoidBottomInset: false,
          floatingActionButton: compact
              ? FloatingActionButton.extended(
                  onPressed: onAction,
                  icon: Icon(actionIcon),
                  label: Text(actionLabel),
                )
              : null,
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: role.index,
                  onDestinationSelected: (i) =>
                      _home.setRole(AppRole.values[i]),
                  destinations: [
                    for (final r in AppRole.values)
                      NavigationDestination(icon: Icon(r.icon), label: r.label),
                  ],
                )
              : null,
          body: SafeArea(
            bottom: !compact,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact)
                  _RoleSidebar(role: role, onChanged: _home.setRole),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Padding(
                        padding: compact
                            ? const EdgeInsets.fromLTRB(
                                Space.l,
                                Space.l,
                                Space.l,
                                0,
                              )
                            : const EdgeInsets.fromLTRB(
                                Space.xxl,
                                Space.xxl,
                                Space.xxl,
                                0,
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RoleHeading(
                              role: role,
                              action: compact
                                  ? null
                                  : FilledButton.icon(
                                      onPressed: onAction,
                                      icon: Icon(actionIcon),
                                      label: Text(actionLabel),
                                    ),
                            ),
                            SizedBox(height: compact ? Space.l : Space.xl),
                            Expanded(
                              child: projects.isEmpty
                                  ? _emptyState(owner)
                                  : _projectGrid(projects, owner, compact),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState(bool owner) => owner
      ? const EmptyState(
          icon: Icons.theater_comedy_outlined,
          title: 'Start your first project',
          message:
              'Create a project, add your lines, and send it to your actors.',
        )
      : const EmptyState(
          icon: Icons.mic_none_rounded,
          title: 'Nothing to record yet',
          message:
              'Got a .ovaproject file? Import it to see the lines and start '
              'recording.',
        );

  Widget _projectGrid(
    List<ProjectSummary> projects,
    bool owner,
    bool compact,
  ) => GridView.builder(
    // On a phone the last card clears the button.
    padding: EdgeInsets.only(bottom: compact ? 96 : Space.xl),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: compact ? 600 : 340,
      mainAxisExtent: compact ? 128 : 148,
      crossAxisSpacing: Space.l,
      mainAxisSpacing: compact ? Space.m : Space.l,
    ),
    itemCount: projects.length,
    itemBuilder: (context, index) {
      final project = projects[index];
      return _ProjectCard(
        project: project,
        onTap: () =>
            owner ? _openInitiator(project.id) : _openActor(project.id),
      );
    },
  );
}

/// The app's top level on a large screen. A phone has the same choice in its
/// bottom bar.
class _RoleSidebar extends StatelessWidget {
  const _RoleSidebar({required this.role, required this.onChanged});

  final AppRole role;
  final void Function(AppRole) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _sidebarWidth,
      padding: const EdgeInsets.all(Space.l),
      decoration: const BoxDecoration(
        color: Palette.surface,
        border: Border(right: BorderSide(color: Palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: Space.xl),
          for (final r in AppRole.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: _RoleTile(
                role: r,
                selected: r == role,
                onTap: () => onChanged(r),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final AppRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Material(
      color: selected ? Palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(Corners.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Row(
            children: [
              Icon(
                role.icon,
                size: 22,
                color: selected ? Palette.accent : Palette.inkSoft,
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: theme.titleMedium?.copyWith(
                        color: selected ? Palette.accentInk : Palette.ink,
                      ),
                    ),
                    Text(role.caption, style: theme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleHeading extends StatelessWidget {
  const _RoleHeading({required this.role, this.action});

  final AppRole role;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (role) {
                AppRole.owner => 'Your projects',
                AppRole.actor => 'Projects to record',
              }, style: theme.headlineSmall),
              Text(switch (role) {
                AppRole.owner => 'Write the script, send it to actors, and review their takes.',
                AppRole.actor => 'Record your lines and send the takes back.',
              }, style: theme.bodySmall),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Palette.accent,
            borderRadius: BorderRadius.circular(Corners.m),
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            'OpenVoiceActor',
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SoftCard(
      onTap: onTap,
      padding: EdgeInsets.all(isCompact(context) ? Space.l : Space.l + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.title,
            style: theme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            '${countOf(project.lineCount, 'line')} · '
            'revision ${project.revision}',
            style: theme.bodySmall,
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.xs,
            children: [
              for (final language in project.languages)
                TintBadge(
                  language,
                  background: Palette.surfaceSoft,
                  foreground: Palette.inkSoft,
                  dot: false,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewProject {
  _NewProject(this.title, this.language);
  final String title;
  final String language;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _title = TextEditingController();
  final _language = TextEditingController(text: 'en');

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      isValidLanguageTag(_language.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New project'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _language,
              decoration: const InputDecoration(
                labelText: 'Script language',
                helperText: 'A language tag such as en, ja or zh-Hans',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  _NewProject(_title.text.trim(), _language.text.trim()),
                )
              : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
