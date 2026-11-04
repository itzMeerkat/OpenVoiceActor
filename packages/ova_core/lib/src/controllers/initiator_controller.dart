import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../format/packages.dart';
import '../import/csv.dart';
import '../import/script_import.dart';
import '../import/translation_import.dart';
import '../model/line_status.dart';
import '../model/local_data.dart';
import '../model/project.dart';
import '../model/submission.dart';
import '../ports/audio_ports.dart';
import '../store/workspace.dart';
import 'notifier.dart';

class SubmissionImportReport {
  SubmissionImportReport({
    required this.actorName,
    required this.importedCount,
    required this.alreadyImported,
    required this.rejected,
    required this.unassigned,
  });

  final String actorName;
  final int importedCount;
  final int alreadyImported;
  final List<SkippedTake> rejected;
  final List<Take> unassigned;
}

/// Everything an initiator does with one project. Each change saves at once.
class InitiatorController extends Notifier {
  InitiatorController(this.workspace, String projectId, {this.freeSpace})
    : _dir = workspace.initiatorDir(projectId) {
    project = workspace.loadProject(_dir);
    review = workspace.loadReview(_dir);
  }

  final Workspace workspace;
  final FreeSpaceLookup? freeSpace;
  final String _dir;

  late final Project project;
  late final ReviewData review;

  void _saveProject() {
    workspace.saveProject(_dir, project);
    notifyListeners();
  }

  void _saveReview() {
    workspace.saveReview(_dir, review);
    notifyListeners();
  }

  // Project details

  void updateDetails({
    String? title,
    String? description,
    int? minSampleRateHz,
    int? minBitDepth,
  }) {
    if (title != null && title.trim().isNotEmpty) project.title = title.trim();
    if (description != null) {
      project.description = description.isEmpty ? null : description;
    }
    project.audioRequest = minSampleRateHz == null && minBitDepth == null
        ? null
        : AudioRequest(
            minSampleRateHz: minSampleRateHz,
            minBitDepth: minBitDepth,
            extra: project.audioRequest?.extra,
          );
    _saveProject();
  }

  /// Empty text removes the terms. Changing them raises their version, so
  /// actors have to accept the new wording.
  void setUsageTerms(String text) {
    final trimmed = text.trim();
    final current = project.usageTerms;
    if (trimmed.isEmpty) {
      project.usageTerms = null;
    } else if (current == null) {
      project.usageTerms = UsageTerms(version: 1, text: trimmed);
    } else if (current.text != trimmed) {
      current
        ..text = trimmed
        ..version += 1;
    }
    _saveProject();
  }

  void addLanguage(String tag) {
    if (!isValidLanguageTag(tag)) {
      throw ArgumentError('"$tag" is not a valid language tag.');
    }
    if (project.languages.contains(tag)) return;
    project.languages.add(tag);
    _saveProject();
  }

  /// Removing a language keeps its text and takes; it can be added back.
  void removeLanguage(String tag) {
    if (tag == project.sourceLanguage) {
      throw ArgumentError('The source language cannot be removed.');
    }
    project.languages.remove(tag);
    _saveProject();
  }

  // Characters and scenes

  Character addCharacter(String name, {String? description}) {
    final character = Character(
      id: nextSequentialId('C', project.characters.map((c) => c.id)),
      name: name.trim(),
      description: _blankToNull(description),
    );
    project.characters.add(character);
    _saveProject();
    return character;
  }

  void updateCharacter(String id, {String? name, String? description}) {
    final character = project.characterById(id);
    if (character == null) return;
    if (name != null && name.trim().isNotEmpty) character.name = name.trim();
    if (description != null) character.description = _blankToNull(description);
    _saveProject();
  }

  Scene addScene(String title, {String? context}) {
    final lastOrder = project.scenes.fold(
      0,
      (m, s) => s.order > m ? s.order : m,
    );
    final scene = Scene(
      id: nextSequentialId('S', project.scenes.map((s) => s.id)),
      title: title.trim(),
      order: lastOrder + 10,
      context: _blankToNull(context),
    );
    project.scenes.add(scene);
    _saveProject();
    return scene;
  }

  void updateScene(String id, {String? title, String? context}) {
    final scene = project.sceneById(id);
    if (scene == null) return;
    if (title != null && title.trim().isNotEmpty) scene.title = title.trim();
    if (context != null) scene.context = _blankToNull(context);
    _saveProject();
  }

  // Lines

  Line addLine({
    required String characterId,
    required String text,
    String? sceneId,
    String? direction,
    String? emotion,
    String? pronunciation,
  }) {
    final line = Line(
      id: nextSequentialId('L', project.lines.map((l) => l.id)),
      characterId: characterId,
      sceneId: sceneId,
      order: nextLineOrder(project, sceneId),
      direction: _blankToNull(direction),
      emotion: _blankToNull(emotion),
      pronunciation: _blankToNull(pronunciation),
      text: {project.sourceLanguage: LineText(text.trim(), 1)},
    );
    project.lines.add(line);
    _saveProject();
    return line;
  }

  /// Changing these never makes existing takes outdated.
  void updateLineDetails(
    String lineId, {
    required String characterId,
    required String? sceneId,
    required String? direction,
    required String? emotion,
    required String? pronunciation,
  }) {
    final line = project.lineById(lineId);
    if (line == null) return;
    if (line.sceneId != sceneId) {
      line.order = nextLineOrder(project, sceneId);
    }
    line
      ..characterId = characterId
      ..sceneId = sceneId
      ..direction = _blankToNull(direction)
      ..emotion = _blankToNull(emotion)
      ..pronunciation = _blankToNull(pronunciation);
    _saveProject();
  }

  /// True if saving [value] would change the line, so the screen knows whether
  /// to ask if it needs new recording.
  bool textWouldChange(String lineId, String language, String value) {
    final current = project.lineById(lineId)?.text[language];
    return current != null && current.value != value.trim();
  }

  /// [needsNewRecording] decides whether the version goes up (spec section 5).
  void setLineText(
    String lineId,
    String language,
    String value, {
    required bool needsNewRecording,
  }) {
    final line = project.lineById(lineId);
    final trimmed = value.trim();
    if (line == null || trimmed.isEmpty) return;
    final current = line.text[language];
    if (current == null) {
      line.text[language] = LineText(trimmed, 1);
    } else if (current.value != trimmed) {
      current.value = trimmed;
      if (needsNewRecording) current.version++;
    }
    _saveProject();
  }

  /// Retired lines are hidden from actors and keep their takes and their id.
  void setRetired(String lineId, bool retired) {
    project.lineById(lineId)?.retired = retired;
    _saveProject();
  }

  // CSV

  ScriptPreview previewScript(String csvText) =>
      previewScriptImport(project, csvText);

  void applyScript(
    ScriptPreview preview, {
    Set<String> keepRecordings = const {},
    Set<String> retire = const {},
  }) {
    applyScriptImport(
      project,
      preview,
      keepRecordings: keepRecordings,
      retire: retire,
    );
    _saveProject();
  }

  TranslationPreview previewTranslation(String language, String csvText) {
    if (!isValidLanguageTag(language)) {
      throw CsvException('"$language" is not a valid language tag.');
    }
    return previewTranslationImport(project, language, csvText);
  }

  void applyTranslation(
    TranslationPreview preview, {
    Set<String> keepRecordings = const {},
  }) {
    applyTranslationImport(project, preview, keepRecordings: keepRecordings);
    _saveProject();
  }

  String scriptCsv() => exportScriptCsv(project);

  String translationTemplate(String language) =>
      exportTranslationTemplate(project, language);

  // Packages

  /// Raises the revision only once the package is safely written.
  Future<void> exportPackage(String path) async {
    project.revision++;
    final snapshot = project;
    try {
      await writeProjectPackage(snapshot, path);
    } catch (_) {
      project.revision--;
      rethrow;
    }
    _saveProject();
  }

  Future<SubmissionImportReport> importSubmission(String packagePath) async {
    final audioDir = p.join(_dir, 'audio');
    Directory(audioDir).createSync(recursive: true);
    final projectId = project.id;
    final knownTakeIds = {for (final t in review.takes) t.take.id};
    final knownLineIds = {for (final l in project.lines) l.id};
    final freeBytes = freeSpace?.call(audioDir);

    final result = await Isolate.run(
      () => importSubmissionPackage(
        path: packagePath,
        projectId: projectId,
        audioDir: audioDir,
        knownTakeIds: knownTakeIds,
        knownLineIds: knownLineIds,
        freeBytes: freeBytes,
      ),
    );

    for (final take in result.imported) {
      review.takes.add(
        ReviewTake(
          take: take,
          actor: result.submission.actor,
          submissionId: result.submission.id,
        ),
      );
    }
    _saveReview();
    return SubmissionImportReport(
      actorName: result.submission.actor.displayName,
      importedCount: result.imported.length,
      alreadyImported: result.alreadyImported,
      rejected: result.rejected,
      unassigned: result.unassigned,
    );
  }

  // Review

  String audioPath(ReviewTake take) =>
      p.join(_dir, 'audio', '${take.take.id}.wav');

  List<ReviewTake> takesFor(String lineId, String language) {
    final takes = review.takes
        .where((t) => t.take.lineId == lineId && t.take.language == language)
        .toList();
    takes.sort((a, b) => b.take.recordedAt.compareTo(a.take.recordedAt));
    return takes;
  }

  /// Takes whose line isn't in this project. Kept so nothing is lost.
  List<ReviewTake> get unassignedTakes => [
    for (final t in review.takes)
      if (project.lineById(t.take.lineId) == null) t,
  ];

  LineStatus statusOf(Line line, String language) =>
      initiatorLineStatus(project, review, line, language);

  ProjectProgress progress(String language) {
    final counts = <LineStatus, int>{};
    for (final line in project.orderedLines()) {
      if (!line.text.containsKey(language)) continue;
      final status = statusOf(line, language);
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return ProjectProgress(counts);
  }

  void selectTake(ReviewTake take) {
    final line = project.lineById(take.take.lineId);
    final version = line?.text[take.take.language]?.version;
    if (version == null) return;
    review.selections.removeWhere(
      (s) => s.lineId == take.take.lineId && s.language == take.take.language,
    );
    review.selections.add(
      TakeSelection(
        lineId: take.take.lineId,
        language: take.take.language,
        takeId: take.take.id,
        approvedTextVersion: version,
      ),
    );
    _saveReview();
  }

  void clearSelection(String lineId, String language) {
    review.selections.removeWhere(
      (s) => s.lineId == lineId && s.language == language,
    );
    _saveReview();
  }

  /// Sent to the actor with the next project export.
  void requestRetake(ReviewTake take, String note) {
    project.retakeRequests.add(
      RetakeRequest(
        id: Workspace.newId(),
        lineId: take.take.lineId,
        language: take.take.language,
        actorId: take.actor.id,
        sourceTakeId: take.take.id,
        note: _blankToNull(note),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _saveProject();
  }

  void cancelRetake(String requestId) {
    project.retakeRequests.removeWhere((r) => r.id == requestId);
    _saveProject();
  }

  List<RetakeRequest> openRetakes(String lineId, String language) {
    final pairs = [
      for (final t in takesFor(lineId, language)) (t.take, t.actor.id),
    ];
    return [
      for (final r in project.retakeRequests)
        if (r.lineId == lineId &&
            r.language == language &&
            isRetakeOpen(r, pairs))
          r,
    ];
  }

  /// Copies the selected takes to `<folder>/<language>/<lineId>.wav` for a game
  /// engine, unchanged, with a `mapping.csv`. Re-exporting replaces those files.
  /// Returns how many takes were copied.
  Future<int> exportSelectedTakes(String folder) async {
    final rows = <List<String>>[
      const ['line_id', 'language', 'file', 'character', 'text', 'outdated'],
    ];
    final usedNames = <String>{};
    var copied = 0;
    for (final selection in review.selections) {
      final take = review.takes
          .where((t) => t.take.id == selection.takeId)
          .firstOrNull;
      if (take == null) continue;
      final line = project.lineById(selection.lineId);
      final name = _uniqueFileName(selection, usedNames);
      final languageDir = _safeFileName(selection.language);
      final target = p.join(folder, languageDir, name);
      Directory(p.dirname(target)).createSync(recursive: true);
      await File(audioPath(take)).copy(target);
      rows.add([
        selection.lineId,
        selection.language,
        '$languageDir/$name',
        project.characterById(line?.characterId)?.name ?? '',
        take.take.spokenText,
        isOutdated(take.take, line) ? 'yes' : 'no',
      ]);
      copied++;
    }
    File(p.join(folder, 'mapping.csv')).writeAsStringSync(writeCsv(rows));
    return copied;
  }

  /// Line ids may contain any characters, so they can't be file names as is.
  String _uniqueFileName(TakeSelection selection, Set<String> used) {
    final base = _safeFileName(selection.lineId);
    var name = '$base.wav';
    for (var n = 2; !used.add('${selection.language}/$name'); n++) {
      name = '${base}_$n.wav';
    }
    return name;
  }

  String _safeFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final trimmed = safe.replaceAll(RegExp(r'^\.+|\.+$'), '');
    return trimmed.isEmpty ? 'line' : trimmed;
  }
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
