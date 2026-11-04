import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import '../design/tokens.dart';

/// How each role presents itself, so it reads the same wherever it appears.
extension RoleText on AppRole {
  String get label => switch (this) {
    AppRole.owner => 'Project owner',
    AppRole.actor => 'Voice actor',
  };

  String get caption => switch (this) {
    AppRole.owner => 'Write scripts and review takes',
    AppRole.actor => 'Record your lines',
  };

  IconData get icon => switch (this) {
    AppRole.owner => Icons.theater_comedy_rounded,
    AppRole.actor => Icons.mic_rounded,
  };
}

/// A project's title with the role it's open in, for an app bar.
class RoleTitle extends StatelessWidget {
  const RoleTitle({super.key, required this.title, required this.role});

  final String title;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(role.icon, size: 13, color: Palette.accent),
            const SizedBox(width: Space.xs),
            Text(
              role.label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Palette.inkSoft),
            ),
          ],
        ),
      ],
    );
  }
}
