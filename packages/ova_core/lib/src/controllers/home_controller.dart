import 'dart:io';
import 'dart:isolate';

import '../format/packages.dart';
import '../model/local_data.dart';
import '../model/project.dart';
import '../store/workspace.dart';
import 'notifier.dart';

enum ProjectImportOutcome { added, updated, unchanged, refusedOlder }

class ProjectImportResult {
  ProjectImportResult(this.outcome, this.project);

  final ProjectImportOutcome outcome;
  final Project project;
}

/// The home screen: which role is in use, and that role's projects.
class HomeController extends Notifier {
  HomeController(this.workspace) {
    refresh();
  }

  final Workspace workspace;

  List<ProjectSummary> initiatorProjects = [];
  List<ProjectSummary> actorProjects = [];

  late final AppSettings _settings = workspace.loadSettings();

  AppRole get role => _settings.role;

  /// Remembered, so the app reopens in the role last used.
  void setRole(AppRole value) {
    if (value == role) return;
    _settings.role = value;
    workspace.saveSettings(_settings);
    notifyListeners();
  }

  void refresh() {
    initiatorProjects = workspace.initiatorProjects();
    actorProjects = workspace.actorProjects();
    notifyListeners();
  }

  /// Starts a project with one language. Its revision stays 0 until first export.
  Project createProject({
    required String title,
    required String sourceLanguage,
    List<String> otherLanguages = const [],
    String? description,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError('A project needs a title.');
    for (final tag in [sourceLanguage, ...otherLanguages]) {
      if (!isValidLanguageTag(tag)) {
        throw ArgumentError('"$tag" is not a valid language tag.');
      }
    }
    final project = Project(
      id: Workspace.newId(),
      title: trimmed,
      sourceLanguage: sourceLanguage,
      languages: {sourceLanguage, ...otherLanguages}.toList(),
      description: description,
    );
    workspace.saveProject(workspace.initiatorDir(project.id), project);
    refresh();
    return project;
  }

  /// Imports a `.ovaproject` into actor mode, following spec section 6. Local
  /// takes are never touched: outdated status is worked out from their versions.
  Future<ProjectImportResult> importProject(String packagePath) async {
    final incoming = await Isolate.run(() => readProjectPackage(packagePath));
    final dir = workspace.actorDir(incoming.id);
    final exists = File('$dir/project.json').existsSync();
    final ProjectImportResult result;
    if (!exists) {
      workspace.saveProject(dir, incoming);
      result = ProjectImportResult(ProjectImportOutcome.added, incoming);
    } else {
      final current = workspace.loadProject(dir);
      if (incoming.revision > current.revision) {
        workspace.saveProject(dir, incoming);
        result = ProjectImportResult(ProjectImportOutcome.updated, incoming);
      } else if (incoming.revision == current.revision) {
        result = ProjectImportResult(ProjectImportOutcome.unchanged, current);
      } else {
        result = ProjectImportResult(
          ProjectImportOutcome.refusedOlder,
          current,
        );
      }
    }
    refresh();
    return result;
  }
}
