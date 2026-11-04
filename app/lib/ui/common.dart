/// Small pieces shared by every screen. Nothing here knows about projects.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ova_core/ova_core.dart';

import 'design/responsive.dart';

export 'design/components.dart';
export 'design/responsive.dart';
export 'design/tokens.dart';

const _messageWidth = 320.0;
const _messageMargin = 10.0;

/// Rebuilds when any of [notifiers] changes.
class Watch extends StatefulWidget {
  const Watch({super.key, required this.notifiers, required this.builder});

  final List<Notifier> notifiers;
  final WidgetBuilder builder;

  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final n in widget.notifiers) {
      n.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final n in widget.notifiers) {
      n.removeListener(_changed);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Shown in the bottom-left corner, so it never covers the record controls. On a
/// phone it spans the width, above any bottom bar.
void showMessage(BuildContext context, String message) {
  final width = MediaQuery.sizeOf(context).width;
  final right = isCompact(context)
      ? _messageMargin
      : width - _messageWidth - _messageMargin;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          left: _messageMargin,
          bottom: _messageMargin,
          right: right < _messageMargin ? _messageMargin : right,
        ),
      ),
    );
}

String errorText(Object error) => switch (error) {
  StateError e => e.message,
  ArgumentError e => '${e.message}',
  FileSystemException e => '${e.message}: ${e.path ?? ''}',
  _ => '$error',
};

/// Runs an action and shows any failure instead of losing it.
Future<void> guarded(
  BuildContext context,
  FutureOr<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}

/// Blocks the screen with a spinner during long work such as packaging audio.
Future<T> withProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    navigator.pop();
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for one piece of text. Returns null if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String action = 'Save',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onSubmitted: maxLines == 1
              ? (value) => Navigator.pop(context, value)
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
}

String countOf(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

String formatRate(int hz) {
  final khz = hz / 1000;
  return '${khz == khz.roundToDouble() ? khz.toInt() : khz.toStringAsFixed(1)} kHz';
}

/// Just the time of day, for today's work.
String formatClock(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

String formatBytes(int bytes) {
  if (bytes < 1 << 20) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1 << 30) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
}

String formatDuration(int ms) {
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} s';
  final minutes = seconds ~/ 60;
  final rest = (seconds - minutes * 60).toStringAsFixed(0).padLeft(2, '0');
  return '$minutes:$rest';
}

/// A title made safe to suggest as a file name.
String fileNameFor(String title) {
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return safe.isEmpty ? 'project' : safe;
}

/// Reads a CSV as UTF-8, as the spec requires, with a clear message otherwise.
Future<String> readCsvFile(String path) async {
  try {
    return await File(path).readAsString();
  } on FileSystemException catch (e) {
    if (e.osError == null) {
      throw StateError('This file is not UTF-8. Save it as "CSV UTF-8" first.');
    }
    rethrow;
  }
}
