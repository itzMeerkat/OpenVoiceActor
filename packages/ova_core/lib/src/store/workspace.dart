import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../format/packages.dart';
import '../model/local_data.dart';
import '../model/project.dart';

/// Replaces [path] in one step, so a crash can't leave half a file.
void writeJsonAtomic(String path, Json json) {
  File(path).parent.createSync(recursive: true);
  final temp = File('$path.tmp');
  temp.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(json),
    flush: true,
  );
  temp.renameSync(path);
}

Json? readJsonIfExists(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Json;
}

class ProjectSummary {
  ProjectSummary(
    this.id,
    this.title,
    this.revision,
    this.lineCount,
    this.languages,
  );

  final String id;
  final String title;
  final int revision;
  final int lineCount;
  final List<String> languages;
}

/// Where the app keeps everything on disk:
///
/// ```
/// <root>/settings.json
/// <root>/initiator/<projectId>/project.json, review.json, audio/<takeId>.wav
/// <root>/actor/<projectId>/project.json, session.json, audio/<takeId>.wav
/// ```
///
/// Project ids come from packages, so only UUIDs ever reach a path.
class Workspace {
  Workspace(this.root);

  final String root;

  static String newId() => const Uuid().v4();

  String get _settingsPath => p.join(root, 'settings.json');

  String initiatorDir(String projectId) => _projectDir('initiator', projectId);
  String actorDir(String projectId) => _projectDir('actor', projectId);

  String _projectDir(String mode, String projectId) {
    if (!isUuid(projectId)) throw ArgumentError('Invalid project id');
    return p.join(root, mode, projectId);
  }

  AppSettings loadSettings() {
    final json = readJsonIfExists(_settingsPath);
    if (json != null) return AppSettings.fromJson(json);
    final settings = AppSettings(actorId: newId());
    saveSettings(settings);
    return settings;
  }

  void saveSettings(AppSettings settings) =>
      writeJsonAtomic(_settingsPath, settings.toJson());

  List<ProjectSummary> initiatorProjects() => _summaries('initiator');
  List<ProjectSummary> actorProjects() => _summaries('actor');

  List<ProjectSummary> _summaries(String mode) {
    final dir = Directory(p.join(root, mode));
    if (!dir.existsSync()) return [];
    final summaries = <ProjectSummary>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      try {
        final project = loadProject(entry.path);
        summaries.add(
          ProjectSummary(
            project.id,
            project.title,
            project.revision,
            project.lines.where((l) => !l.retired).length,
            project.languages,
          ),
        );
      } catch (_) {
        // One damaged folder shouldn't hide the other projects.
      }
    }
    summaries.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return summaries;
  }

  Project loadProject(String dir) =>
      Project.fromJson(readJsonIfExists(p.join(dir, 'project.json'))!);

  void saveProject(String dir, Project project) =>
      writeJsonAtomic(p.join(dir, 'project.json'), project.toJson());

  ReviewData loadReview(String dir) {
    final json = readJsonIfExists(p.join(dir, 'review.json'));
    return json == null ? ReviewData() : ReviewData.fromJson(json);
  }

  void saveReview(String dir, ReviewData review) =>
      writeJsonAtomic(p.join(dir, 'review.json'), review.toJson());

  ActorSession loadSession(String dir) {
    final json = readJsonIfExists(p.join(dir, 'session.json'));
    return json == null ? ActorSession() : ActorSession.fromJson(json);
  }

  void saveSession(String dir, ActorSession session) =>
      writeJsonAtomic(p.join(dir, 'session.json'), session.toJson());
}
