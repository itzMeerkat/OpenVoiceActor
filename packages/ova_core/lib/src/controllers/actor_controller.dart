import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../format/packages.dart';
import '../format/wav_info.dart';
import '../model/line_status.dart';
import '../model/local_data.dart';
import '../model/project.dart';
import '../model/submission.dart';
import '../ports/audio_ports.dart';
import '../store/workspace.dart';
import 'notifier.dart';

class ExportOptions {
  const ExportOptions({
    this.favoritesOnly = true,
    this.includeAlreadyExported = false,
    this.includeDeviceName = false,
  });

  final bool favoritesOnly;
  final bool includeAlreadyExported;
  final bool includeDeviceName;
}

class ExportReport {
  ExportReport(this.exportedCount, this.skipped);

  final int exportedCount;
  final List<SkippedTake> skipped;
}

/// Everything an actor does with one project, apart from driving the device,
/// which is [RecordingController]'s job. Each change saves at once.
class ActorController extends Notifier {
  ActorController(this.workspace, String projectId)
    : _dir = workspace.actorDir(projectId) {
    project = workspace.loadProject(_dir);
    session = workspace.loadSession(_dir);
    settings = workspace.loadSettings();
    language = project.languages.contains(project.sourceLanguage)
        ? project.sourceLanguage
        : project.languages.first;
  }

  final Workspace workspace;
  final String _dir;

  late final Project project;
  late final ActorSession session;
  late final AppSettings settings;
  late String language;

  String? characterFilter;
  String? sceneFilter;
  LineStatus? statusFilter;

  void _save() {
    workspace.saveSession(_dir, session);
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }

  void setFilters({String? character, String? scene, LineStatus? status}) {
    characterFilter = character;
    sceneFilter = scene;
    statusFilter = status;
    notifyListeners();
  }

  /// The script for the current language and filters. An actor can't record a
  /// line that has no text in the language.
  List<Line> get visibleLines => [
    for (final line in project.orderedLines())
      if (line.text.containsKey(language) &&
          (characterFilter == null || line.characterId == characterFilter) &&
          (sceneFilter == null || line.sceneId == sceneFilter) &&
          (statusFilter == null || statusOf(line) == statusFilter))
        line,
  ];

  LineStatus statusOf(Line line) =>
      actorLineStatus(project, session, settings.actorId, line, language);

  /// Progress in the current language, ignoring filters.
  ProjectProgress progress() {
    final counts = <LineStatus, int>{};
    for (final line in project.orderedLines()) {
      if (!line.text.containsKey(language)) continue;
      final status = statusOf(line);
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return ProjectProgress(counts);
  }

  List<RetakeRequest> openRetakes(Line line) {
    final pairs = [for (final t in takesFor(line.id)) (t, settings.actorId)];
    return [
      for (final r in project.retakeRequests)
        if (r.actorId == settings.actorId &&
            r.lineId == line.id &&
            r.language == language &&
            isRetakeOpen(r, pairs))
          r,
    ];
  }

  /// Takes for a line in the current language, newest first.
  List<Take> takesFor(String lineId) {
    final takes = session.takes
        .where((t) => t.lineId == lineId && t.language == language)
        .toList();
    takes.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return takes;
  }

  String audioPath(String takeId) => p.join(_dir, 'audio', '$takeId.wav');

  void toggleFavorite(String takeId) {
    final take = session.takes.where((t) => t.id == takeId).firstOrNull;
    if (take == null) return;
    take.favorite = !take.favorite;
    _save();
  }

  /// Deleting is the actor's own choice about a local take. It doesn't reach
  /// anything already exported.
  void deleteTake(String takeId) {
    session.takes.removeWhere((t) => t.id == takeId);
    session.exportedTakeIds.remove(takeId);
    final file = File(audioPath(takeId));
    if (file.existsSync()) file.deleteSync();
    _save();
  }

  // Recording

  /// Saves what's about to be recorded, before capture starts, so a crash can
  /// still tie the audio back to its line. Returns the path to record to.
  (PendingTake, String) beginTake(Line line, {String? inputDeviceName}) {
    final text = line.text[language];
    if (text == null) {
      throw StateError('This line has no text in $language.');
    }
    final pending = PendingTake(
      id: Workspace.newId(),
      lineId: line.id,
      language: language,
      characterId: line.characterId,
      recordedAt: DateTime.now().toUtc(),
      spokenText: text.value,
      textVersion: text.version,
      inputDeviceName: inputDeviceName,
    );
    Directory(p.join(_dir, 'audio')).createSync(recursive: true);
    session.pending.add(pending);
    workspace.saveSession(_dir, session);
    return (pending, audioPath(pending.id));
  }

  /// Turns a finished recording into a tracked take. Returns null if there's no
  /// usable audio, such as when the device failed before anything was written.
  Future<Take?> finishTake(
    PendingTake pending, {
    int droppedFrames = 0,
    int clippedSamples = 0,
  }) async {
    session.pending.removeWhere((t) => t.id == pending.id);
    final path = audioPath(pending.id);
    Take? take;
    try {
      final info = readWavInfo(path);
      if (info.frames > 0) {
        take = Take(
          id: pending.id,
          lineId: pending.lineId,
          language: pending.language,
          characterId: pending.characterId,
          recordedAt: pending.recordedAt,
          spokenText: pending.spokenText,
          textVersion: pending.textVersion,
          file: 'audio/${pending.id}.wav',
          sha256: await sha256OfFile(path),
          audio: info.toTakeAudio(),
          capture: TakeCapture(
            platform: Platform.operatingSystem,
            appVersion: appVersion,
            inputDeviceName: pending.inputDeviceName,
            droppedFrames: droppedFrames,
            clippedSamples: clippedSamples,
          ),
        );
        session.takes.add(take);
      } else {
        File(path).deleteSync();
      }
    } on FileSystemException {
      // No file means nothing was captured. The pending entry is cleared below.
    } on FormatException {
      // Unreadable audio stays on disk but isn't offered as a take.
    }
    _save();
    return take;
  }

  /// After a crash: repairs the takes that were still being written and tracks
  /// them. Returns how many takes came back.
  Future<int> recoverInterruptedTakes(AudioInput input) async {
    var recovered = 0;
    for (final pending in List.of(session.pending)) {
      final path = audioPath(pending.id);
      final partial = File('$path.partial');
      if (partial.existsSync()) {
        try {
          input.recoverPartial(partial.path);
        } catch (_) {
          // Leave the file for manual rescue. The take can't be tracked.
        }
      }
      if (await finishTake(pending) != null) recovered++;
    }
    return recovered;
  }

  // Export

  bool get termsNeedAcceptance {
    final terms = project.usageTerms;
    return terms != null && session.termsAcceptance?.version != terms.version;
  }

  void acceptTerms() {
    final terms = project.usageTerms;
    if (terms == null) return;
    session.termsAcceptance = UsageTermsAcceptance(
      version: terms.version,
      acceptedAt: DateTime.now().toUtc(),
    );
    _save();
  }

  void setActorNames({required String displayName, String creditName = ''}) {
    settings
      ..displayName = displayName.trim()
      ..creditName = creditName.trim();
    workspace.saveSettings(settings);
    notifyListeners();
  }

  List<Take> takesToExport(ExportOptions options) => [
    for (final take in session.takes)
      if ((!options.favoritesOnly || take.favorite) &&
          (options.includeAlreadyExported ||
              !session.exportedTakeIds.contains(take.id)))
        take,
  ];

  /// Total audio size of the takes that would be exported, for the screen.
  int exportSizeBytes(ExportOptions options) {
    var total = 0;
    for (final take in takesToExport(options)) {
      final file = File(audioPath(take.id));
      if (file.existsSync()) total += file.lengthSync();
    }
    return total;
  }

  Future<ExportReport> exportSubmission(
    String path, {
    ExportOptions options = const ExportOptions(),
  }) async {
    if (termsNeedAcceptance) {
      throw StateError('The usage terms must be accepted before exporting.');
    }
    if (settings.displayName.isEmpty) {
      throw StateError('Enter your name before exporting.');
    }
    final takes = takesToExport(options);
    if (takes.isEmpty) throw StateError('There are no takes to export.');

    final submission = Submission(
      id: Workspace.newId(),
      projectId: project.id,
      projectRevision: project.revision,
      actor: ActorInfo(
        id: settings.actorId,
        displayName: settings.displayName,
        creditName: settings.creditName.isEmpty ? null : settings.creditName,
      ),
      usageTermsAcceptance: project.usageTerms == null
          ? null
          : session.termsAcceptance,
      takes: [
        for (final take in takes)
          take.copyForExport(includeDeviceName: options.includeDeviceName),
      ],
    );
    final audioRoot = _dir;
    final (included, skipped) = await Isolate.run(
      () => writeSubmissionPackage(
        submission: submission,
        audioRoot: audioRoot,
        path: path,
      ),
    );
    session.exportedTakeIds.addAll(included);
    _save();
    return ExportReport(included.length, skipped);
  }
}
