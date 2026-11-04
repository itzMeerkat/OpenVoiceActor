/// The widgets that give the app its own look. None of them know about projects
/// beyond the status enum, so screens can rearrange them freely.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart' show LineStatus;

import 'responsive.dart';
import 'tokens.dart';

/// A white panel with a hairline border.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.l),
    this.color = Palette.surface,
    this.borderColor = Palette.line,
    this.radius = Corners.l,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// A form in a dialog, which fills the screen on a phone so the fields have room
/// beside the keyboard.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.width,
    required this.action,
    required this.child,
  });

  final String title;
  final double width;
  final Widget action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isCompact(context)) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: width,
          child: SingleChildScrollView(child: child),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          action,
        ],
      );
    }
    return Dialog.fullscreen(
      backgroundColor: Palette.surface,
      child: Scaffold(
        backgroundColor: Palette.surface,
        appBar: AppBar(
          backgroundColor: Palette.surface,
          leading: const CloseButton(),
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            action,
            const SizedBox(width: Space.m),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.l),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A segmented switch for moving between views.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.expanded = false,
  });

  final T value;
  final Map<T, String> options;
  final void Function(T) onChanged;

  /// Shares the full width between the options.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    Widget tab(MapEntry<T, String> entry) => InkWell(
      borderRadius: BorderRadius.circular(Corners.pill),
      onTap: () => onChanged(entry.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? Space.s : Space.l,
          vertical: expanded ? Space.m : Space.s,
        ),
        decoration: BoxDecoration(
          color: entry.key == value ? Palette.surface : null,
          borderRadius: BorderRadius.circular(Corners.pill),
          boxShadow: entry.key == value
              ? const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          entry.value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            color: entry.key == value ? Palette.accent : Palette.inkSoft,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.surfaceSoft,
        borderRadius: BorderRadius.circular(Corners.pill),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final entry in options.entries)
            expanded ? Expanded(child: tab(entry)) : tab(entry),
        ],
      ),
    );
  }
}

/// A compact dropdown on a soft pill, for filters and language choice.
class SoftDropdown<T> extends StatelessWidget {
  const SoftDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.expanded = false,
    this.hint,
    this.fill = Palette.surfaceSoft,
  });

  final T value;
  final Map<T, String> items;
  final void Function(T?)? onChanged;
  final bool expanded;
  final String? hint;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: Palette.ink);
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: Space.m, right: Space.s),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Corners.pill),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: expanded,
          isDense: true,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(Corners.m),
          dropdownColor: Palette.surface,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          style: style,
          hint: hint == null ? null : Text(hint!, style: style),
          onChanged: onChanged,
          items: [
            for (final entry in items.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }
}

/// A line's status as a small tinted badge with a dot.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final LineStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      LineStatus.notRecorded => (Palette.surfaceSoft, Palette.inkSoft),
      LineStatus.recorded => (Palette.infoSoft, Palette.info),
      LineStatus.submitted => (Palette.infoSoft, Palette.info),
      LineStatus.approved => (Palette.successSoft, Palette.success),
      LineStatus.outdated => (Palette.warningSoft, Palette.warning),
      LineStatus.retakeRequested => (Palette.accentSoft, Palette.accentInk),
    };
    return TintBadge(
      status.label,
      background: background,
      foreground: foreground,
    );
  }
}

/// A small tinted label with a dot.
class TintBadge extends StatelessWidget {
  const TintBadge(
    this.label, {
    super.key,
    required this.background,
    required this.foreground,
    this.dot = true,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Corners.pill),
      ),
      // Capped so a long note can't push past the edge of its card. The dot sits
      // in the text, so the label wraps inside whatever width a phone leaves.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text.rich(
          TextSpan(
            children: [
              if (dot)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: foreground,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              TextSpan(text: label),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// A notice with an icon, for warnings that need to stay on screen.
class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.isError = true, this.action});

  final String message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = isError
        ? (Palette.dangerSoft, Palette.dangerInk)
        : (Palette.warningSoft, Palette.warning);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.s + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Corners.m),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A character's name beside a tinted initial. Each character keeps one color,
/// so a long script can be scanned by speaker.
class CharacterBadge extends StatelessWidget {
  const CharacterBadge({
    super.key,
    required this.id,
    required this.name,
    this.large = false,
  });

  final String id;
  final String name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final tints = Palette.characterTints;
    final tint = tints[id.codeUnits.fold(0, (a, b) => a + b) % tints.length];
    final size = large ? 30.0 : 22.0;
    final theme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint.$1, shape: BoxShape.circle),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: (large ? theme.titleSmall : theme.labelSmall)?.copyWith(
              color: tint.$2,
            ),
          ),
        ),
        SizedBox(width: large ? Space.s : 6),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: (large ? theme.titleMedium : theme.labelMedium)?.copyWith(
              color: Palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// Friendly filler for a view with nothing in it yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Palette.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Palette.accent, size: 30),
              ),
              const SizedBox(height: Space.l),
              Text(title, style: theme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: Space.xs),
              Text(
                message,
                style: theme.bodyMedium?.copyWith(color: Palette.inkSoft),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: Space.l), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded bar split into colored parts, for showing progress.
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.segments, this.height = 6});

  final List<(int, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Corners.pill),
      child: Container(
        height: height,
        color: Palette.surfaceSoft,
        child: Row(
          children: [
            for (final (count, color) in segments)
              if (count > 0)
                Expanded(
                  flex: count,
                  child: Container(color: color),
                ),
          ],
        ),
      ),
    );
  }
}

const _meterFloorDb = -60.0;

/// Where a linear level sits on the meter, from 0 to 1. Meters use decibels
/// because that's how loudness is heard, and how recording levels are judged.
double meterPosition(double level) {
  if (level <= 0) return 0;
  final db = 20 * math.log(level) / math.ln10;
  return ((db - _meterFloorDb) / -_meterFloorDb).clamp(0.0, 1.0);
}

double _dbPosition(double db) => (db - _meterFloorDb) / -_meterFloorDb;

/// One input's level, with green, amber and red zones always faintly visible,
/// so an actor can see where they should aim.
class LevelMeter extends StatelessWidget {
  const LevelMeter({
    super.key,
    required this.level,
    this.active = true,
    this.clipped = false,
  });

  final double level;
  final bool active;

  /// Lights the whole meter, so a peak at full scale can't be missed.
  final bool clipped;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MeterPainter(meterPosition(level), active, clipped),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.position, this.active, this.clipped);

  final double position;
  final bool active;
  final bool clipped;

  static const _zones = [
    (-60.0, -12.0, Palette.meterGood),
    (-12.0, -3.0, Palette.meterHot),
    (-3.0, 0.0, Palette.meterClip),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.clipRRect(rect);
    final paint = Paint();
    if (clipped) {
      canvas.drawRect(Offset.zero & size, paint..color = Palette.meterClip);
      return;
    }
    for (final (from, to, color) in _zones) {
      final left = _dbPosition(from) * size.width;
      final right = _dbPosition(to) * size.width;
      paint.color = color.withValues(alpha: 0.16);
      canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), paint);
      final filled = math.min(position * size.width, right);
      if (filled > left) {
        paint.color = active ? color : color.withValues(alpha: 0.45);
        canvas.drawRect(Rect.fromLTRB(left, 0, filled, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.position != position ||
      old.active != active ||
      old.clipped != clipped;
}

/// dB labels lined up with [LevelMeter].
class MeterScale extends StatelessWidget {
  const MeterScale({super.key});

  static const _marks = [-48, -24, -12, -6, 0];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Palette.inkFaint, fontSize: 10);
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final mark in _marks)
              Positioned(
                left:
                    _dbPosition(mark.toDouble()) * constraints.maxWidth -
                    (mark == 0 ? 28 : 14),
                width: 28,
                child: Text(
                  '$mark',
                  textAlign: mark == 0 ? TextAlign.end : TextAlign.center,
                  style: style,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The main control. It pulses while recording, so it's obvious at a glance.
class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.recording,
    required this.onPressed,
    required this.label,
    this.showKey = true,
    this.showLabel = true,
    this.size = 62,
    this.actOnPress = false,
  });

  final bool recording;
  final VoidCallback? onPressed;
  final String label;
  final bool showKey;
  final bool showLabel;
  final double size;

  /// Fires as the button goes down rather than on release. Stopping this way
  /// ends the take before the release can be heard.
  final bool actOnPress;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _firedOnPress = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.actOnPress || event.buttons & kPrimaryButton == 0) return;
    if (widget.onPressed == null) return;
    _firedOnPress = true;
    widget.onPressed!();
  }

  /// Also reached by assistive tech, which never sends a pointer down.
  void _handleTap() {
    if (_firedOnPress) {
      _firedOnPress = false;
      return;
    }
    widget.onPressed?.call();
  }

  void _syncPulse() {
    if (widget.recording) {
      _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(RecordButton old) {
    super.didUpdateWidget(old);
    if (old.recording != widget.recording) _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final enabled = widget.onPressed != null;
    final color = enabled ? Palette.accent : Palette.lineStrong;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Listener(
        onPointerDown: _handlePointerDown,
        child: InkWell(
          borderRadius: BorderRadius.circular(Corners.m),
          canRequestFocus: false,
          onTap: enabled || _firedOnPress ? _handleTap : null,
          onTapCancel: () => _firedOnPress = false,
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size + 12,
                  height: size + 12,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => Container(
                          width: size + 12 * _pulse.value,
                          height: size + 12 * _pulse.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Palette.accent.withValues(
                              alpha: 0.28 * (1 - _pulse.value),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: enabled
                              ? [
                                  BoxShadow(
                                    color: Palette.accent.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: widget.recording ? 20 : 24,
                        height: widget.recording ? 20 : 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            widget.recording ? 4 : 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Palette.ink),
                      ),
                      if (widget.showKey) ...[
                        const SizedBox(width: Space.xs + 2),
                        const KeyCap('Space'),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A key name drawn like a keyboard key.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Palette.line),
        boxShadow: const [
          BoxShadow(color: Palette.lineStrong, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Palette.inkSoft, fontSize: 10.5),
      ),
    );
  }
}

/// A take's shape as rounded bars. The part already played takes the accent.
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.progress,
    this.height = 38,
  });

  /// Null until loaded, which draws a flat placeholder.
  final List<double>? peaks;

  /// From 0 to 1 while playing.
  final double? progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _WaveformPainter(peaks, progress),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.peaks, this.progress);

  final List<double>? peaks;
  final double? progress;

  static const _barWidth = 2.5;
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_barWidth + _gap)).floor();
    if (count <= 0) return;
    final data = peaks;
    final paint = Paint();
    final middle = size.height / 2;
    for (var i = 0; i < count; i++) {
      var level = 0.0;
      if (data != null && data.isNotEmpty) {
        final from = i * data.length ~/ count;
        final to = math.max(from + 1, (i + 1) * data.length ~/ count);
        for (var p = from; p < to && p < data.length; p++) {
          level = math.max(level, data[p]);
        }
      }
      // The square root keeps quiet speech visible next to loud speech.
      final bar = math.max(2.5, math.sqrt(level) * size.height);
      final x = i * (_barWidth + _gap);
      final played = progress != null && i / count <= progress!;
      paint.color = played
          ? Palette.accent
          : (level > 0 ? const Color(0xFFBDB1A4) : Palette.line);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, middle - bar / 2, _barWidth, bar),
          const Radius.circular(_barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      !identical(old.peaks, peaks) || old.progress != progress;
}
