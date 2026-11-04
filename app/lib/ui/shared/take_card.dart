import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/components.dart';

const _stackedWidth = 520.0;

/// One recorded take, used by both the actor and the review screens. Each screen
/// supplies its own text and actions. In a narrow space the waveform and actions
/// take their own rows.
class TakeCard extends StatelessWidget {
  const TakeCard({
    super.key,
    required this.title,
    required this.details,
    required this.peaks,
    required this.playing,
    required this.progress,
    required this.onPlay,
    this.leading,
    this.trailing,
    this.badges = const [],
    this.warnings = const [],
    this.actions = const [],
    this.highlighted = false,
  });

  final String title;
  final String details;
  final List<double>? peaks;
  final bool playing;
  final double? progress;
  final VoidCallback onPlay;
  final Widget? leading;

  /// A small control that stays on the title row at any width.
  final Widget? trailing;
  final List<Widget> badges;
  final List<String> warnings;
  final List<Widget> actions;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.m,
          vertical: Space.s + 2,
        ),
        color: highlighted ? const Color(0xFFFFF8F5) : Palette.surface,
        borderColor: highlighted ? Palette.accent : Palette.line,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < _stackedWidth;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  details,
                  style: theme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
            final waveform = WaveformView(peaks: peaks, progress: progress);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _PlayButton(playing: playing, onPressed: onPlay),
                    ?leading,
                    const SizedBox(width: Space.s),
                    if (stacked)
                      Expanded(child: heading)
                    else ...[
                      SizedBox(width: 170, child: heading),
                      const SizedBox(width: Space.m),
                      Expanded(child: waveform),
                      const SizedBox(width: Space.m),
                      ...actions,
                    ],
                    ?trailing,
                  ],
                ),
                if (stacked) ...[const SizedBox(height: Space.s), waveform],
                if (badges.isNotEmpty || warnings.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: Space.s,
                      left: stacked ? 0 : 44,
                    ),
                    child: Wrap(
                      spacing: Space.s,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...badges,
                        for (final warning in warnings)
                          Text(
                            warning,
                            style: theme.bodySmall?.copyWith(
                              color: Palette.dangerInk,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (stacked && actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: playing ? 'Stop' : 'Play',
      style: IconButton.styleFrom(
        backgroundColor: playing ? Palette.accent : Palette.accentSoft,
        foregroundColor: playing ? Colors.white : Palette.accent,
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(
        playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        size: 22,
      ),
      onPressed: onPressed,
    );
  }
}
