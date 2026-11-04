import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../common.dart';

const _contentWidth = 760.0;

class SetupTab extends StatelessWidget {
  const SetupTab({super.key, required this.controller});

  final InitiatorController controller;

  Future<void> _editField(
    BuildContext context, {
    required String title,
    required String initial,
    required void Function(String) onSave,
    int maxLines = 1,
  }) async {
    final value = await askText(
      context,
      title: title,
      initial: initial,
      maxLines: maxLines,
    );
    if (value != null && context.mounted) {
      await guarded(context, () => onSave(value));
    }
  }

  Future<void> _addLanguage(BuildContext context) async {
    final tag = await askText(
      context,
      title: 'Add language',
      label: 'Language tag, such as ja or zh-Hans',
      action: 'Add',
    );
    if (tag != null && tag.trim().isNotEmpty && context.mounted) {
      await guarded(context, () => controller.addLanguage(tag.trim()));
    }
  }

  void _setAudioRequest({int? rate, int? bits}) {
    controller.updateDetails(minSampleRateHz: rate, minBitDepth: bits);
  }

  @override
  Widget build(BuildContext context) {
    final project = controller.project;
    final request = project.audioRequest;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Project',
                  children: [
                    _EditRow(
                      label: 'Title',
                      value: project.title,
                      onTap: () => _editField(
                        context,
                        title: 'Title',
                        initial: project.title,
                        onSave: (v) => controller.updateDetails(
                          title: v,
                          minSampleRateHz: request?.minSampleRateHz,
                          minBitDepth: request?.minBitDepth,
                        ),
                      ),
                    ),
                    _EditRow(
                      label: 'Description',
                      value: project.description,
                      placeholder: 'What actors should know',
                      onTap: () => _editField(
                        context,
                        title: 'Description',
                        initial: project.description ?? '',
                        maxLines: 4,
                        onSave: (v) => controller.updateDetails(
                          description: v,
                          minSampleRateHz: request?.minSampleRateHz,
                          minBitDepth: request?.minBitDepth,
                        ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: 'Languages',
                  children: [
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        for (final language in project.languages)
                          Chip(
                            label: Text(language),
                            side: BorderSide.none,
                            backgroundColor: Palette.surfaceSoft,
                            onDeleted: language == project.sourceLanguage
                                ? null
                                : () => controller.removeLanguage(language),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                          side: const BorderSide(color: Palette.lineStrong),
                          onPressed: () => _addLanguage(context),
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: 'Audio request',
                  subtitle:
                      'Actors below these minimums see a warning, and can '
                      'still record.',
                  children: [
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        SoftDropdown<int?>(
                          value: request?.minSampleRateHz,
                          onChanged: (v) => _setAudioRequest(
                            rate: v,
                            bits: request?.minBitDepth,
                          ),
                          items: const {
                            null: 'Any sample rate',
                            44100: '44.1 kHz or more',
                            48000: '48 kHz or more',
                            96000: '96 kHz or more',
                          },
                        ),
                        SoftDropdown<int?>(
                          value: request?.minBitDepth,
                          onChanged: (v) => _setAudioRequest(
                            rate: request?.minSampleRateHz,
                            bits: v,
                          ),
                          items: const {
                            null: 'Any bit depth',
                            16: '16-bit or more',
                            24: '24-bit or more',
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: 'Usage terms',
                  subtitle: project.usageTerms == null
                      ? 'Optional. Actors must accept these before exporting.'
                      : 'Version ${project.usageTerms!.version}. Actors must '
                            'accept these before exporting.',
                  children: [
                    _EditRow(
                      label: 'Terms',
                      value: project.usageTerms?.text,
                      placeholder: 'None',
                      onTap: () => _editField(
                        context,
                        title: 'Usage terms',
                        initial: project.usageTerms?.text ?? '',
                        maxLines: 5,
                        onSave: controller.setUsageTerms,
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: 'Characters',
                  action: TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add character'),
                    onPressed: () => _editField(
                      context,
                      title: 'New character',
                      initial: '',
                      onSave: (v) {
                        if (v.trim().isNotEmpty) controller.addCharacter(v);
                      },
                    ),
                  ),
                  children: [
                    for (final character in project.characters)
                      _NamedRow(
                        leading: CharacterBadge(
                          id: character.id,
                          name: character.name,
                        ),
                        description: character.description,
                        placeholder: 'Add a description',
                        onTap: () => _editField(
                          context,
                          title: 'About ${character.name}',
                          initial: character.description ?? '',
                          maxLines: 3,
                          onSave: (v) => controller.updateCharacter(
                            character.id,
                            description: v,
                          ),
                        ),
                        onRename: () => _editField(
                          context,
                          title: 'Rename character',
                          initial: character.name,
                          onSave: (v) =>
                              controller.updateCharacter(character.id, name: v),
                        ),
                      ),
                  ],
                ),
                _Section(
                  title: 'Scenes',
                  action: TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add scene'),
                    onPressed: () => _editField(
                      context,
                      title: 'New scene',
                      initial: '',
                      onSave: (v) {
                        if (v.trim().isNotEmpty) controller.addScene(v);
                      },
                    ),
                  ),
                  children: [
                    for (final scene in project.scenes)
                      _NamedRow(
                        leading: Text(
                          scene.title,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        description: scene.context,
                        placeholder: 'Add context for the actors',
                        onTap: () => _editField(
                          context,
                          title: 'Context for ${scene.title}',
                          initial: scene.context ?? '',
                          maxLines: 4,
                          onSave: (v) =>
                              controller.updateScene(scene.id, context: v),
                        ),
                        onRename: () => _editField(
                          context,
                          title: 'Rename scene',
                          initial: scene.title,
                          onSave: (v) =>
                              controller.updateScene(scene.id, title: v),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: SoftCard(
        padding: EdgeInsets.all(isCompact(context) ? Space.l : Space.l + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.titleMedium)),
                ?action,
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: theme.bodySmall),
              ),
            if (children.isNotEmpty) const SizedBox(height: Space.m),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder,
  });

  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final compact = isCompact(context);
    final text = Text(
      value ?? placeholder ?? '',
      style: value == null
          ? theme.bodyMedium?.copyWith(color: Palette.inkFaint)
          : theme.bodyMedium,
    );
    final caption = Text(label, style: theme.bodySmall);
    return InkWell(
      borderRadius: BorderRadius.circular(Corners.s),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [caption, text],
                ),
              )
            else ...[
              SizedBox(width: 110, child: caption),
              Expanded(child: text),
            ],
            const Icon(Icons.edit_outlined, size: 16, color: Palette.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _NamedRow extends StatelessWidget {
  const _NamedRow({
    required this.leading,
    required this.description,
    required this.placeholder,
    required this.onTap,
    required this.onRename,
  });

  final Widget leading;
  final String? description;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final compact = isCompact(context);
    final text = Text(
      description ?? placeholder,
      style: description == null
          ? theme.bodySmall?.copyWith(color: Palette.inkFaint)
          : theme.bodySmall,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(Corners.s),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? Space.xs : 2),
        child: Row(
          children: [
            if (compact)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [leading, const SizedBox(height: 2), text],
                ),
              )
            else ...[
              SizedBox(
                width: 170,
                child: Align(alignment: Alignment.centerLeft, child: leading),
              ),
              Expanded(child: text),
            ],
            IconButton(
              tooltip: 'Rename',
              iconSize: 16,
              color: Palette.inkFaint,
              icon: const Icon(Icons.drive_file_rename_outline_rounded),
              onPressed: onRename,
            ),
          ],
        ),
      ),
    );
  }
}
