/// Script CSV import, following spec section 8. Previewing changes nothing, so
/// the initiator can review every change and choose before applying.
library;

import '../model/project.dart';
import 'csv.dart';

const _orderGap = 10;

enum ScriptRowKind {
  /// A line that doesn't exist yet.
  added,

  /// An existing line whose text changed. Needs a recording decision.
  textChanged,

  /// An existing line whose other details changed.
  detailsChanged,

  /// A retired line that appears in the script again.
  restored,
  unchanged,
}

class ScriptRow {
  ScriptRow({
    required this.kind,
    required this.rowNumber,
    required this.characterName,
    required this.text,
    this.lineId,
    this.oldText,
    this.sceneName,
    this.order,
    this.direction,
    this.emotion,
    this.pronunciation,
  });

  final ScriptRowKind kind;
  final int rowNumber;

  /// The id to update or create. Null for a new line that gets a generated one.
  final String? lineId;
  final String characterName;
  final String text;
  final String? oldText;
  final String? sceneName;
  final int? order;

  /// Null means the file has no such column, so the line keeps what it has.
  final String? direction;
  final String? emotion;
  final String? pronunciation;
}

class ScriptPreview {
  ScriptPreview({
    required this.rows,
    required this.errors,
    required this.missing,
    required this.hasSceneColumn,
  });

  final List<ScriptRow> rows;

  /// Problems that block applying, with row numbers.
  final List<String> errors;

  /// Active lines the file doesn't mention. Offered for retiring.
  final List<Line> missing;
  final bool hasSceneColumn;

  bool get canApply => errors.isEmpty;

  Iterable<ScriptRow> ofKind(ScriptRowKind kind) =>
      rows.where((r) => r.kind == kind);
}

ScriptPreview previewScriptImport(Project project, String csvText) {
  final List<CsvRow> csv;
  try {
    csv = csvRows(csvText, required: const ['character', 'text']);
  } on CsvException catch (e) {
    return ScriptPreview(
      rows: const [],
      errors: [e.message],
      missing: const [],
      hasSceneColumn: false,
    );
  }

  final errors = <String>[];
  final valid = <CsvRow>[];
  final seenIds = <String>{};
  for (final row in csv) {
    final id = row.cell('id');
    final problems = [
      if (id.isNotEmpty && !seenIds.add(id)) 'duplicate id "$id"',
      if (row.cell('character').isEmpty) 'no character',
      if (row.cell('text').isEmpty) 'no text',
      if (row.cell('order').isNotEmpty &&
          int.tryParse(row.cell('order')) == null)
        'order is not a whole number',
    ];
    if (problems.isEmpty) {
      valid.add(row);
    } else {
      errors.add('Row ${row.number}: ${problems.join(', ')}.');
    }
  }

  final matched = <String>{};
  final byId = {for (final l in project.lines) l.id: l};
  final characterNames = {for (final c in project.characters) c.id: c.name};
  final language = project.sourceLanguage;

  // Rows with ids claim their lines first, so text matching can't take them.
  for (final row in valid) {
    final id = row.cell('id');
    if (byId.containsKey(id)) matched.add(id);
  }

  // Available lines per character and text, active lines first, each in order.
  final unmatchedByKey = <String, List<Line>>{};
  final candidates =
      project.lines.where((l) => !matched.contains(l.id)).toList()
        ..sort((a, b) {
          if (a.retired != b.retired) return a.retired ? 1 : -1;
          return a.order.compareTo(b.order);
        });
  for (final line in candidates) {
    final name = characterNames[line.characterId];
    final text = line.text[language]?.value;
    if (name == null || text == null) continue;
    unmatchedByKey.putIfAbsent('$name\u0000$text', () => []).add(line);
  }

  // Rows matching several lines are paired in `order`, or file order without it.
  final matchOrder = valid.indexed.toList()
    ..sort((a, b) {
      final orderA = int.tryParse(a.$2.cell('order'));
      final orderB = int.tryParse(b.$2.cell('order'));
      if (orderA != null && orderB != null && orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      return a.$1.compareTo(b.$1);
    });
  final textMatches = <int, Line>{};
  for (final (index, row) in matchOrder) {
    if (row.cell('id').isNotEmpty) continue;
    final key = '${row.cell('character')}\u0000${row.cell('text')}';
    final available = unmatchedByKey[key];
    if (available != null && available.isNotEmpty) {
      final line = available.removeAt(0);
      textMatches[index] = line;
      matched.add(line.id);
    }
  }

  final rows = <ScriptRow>[];
  for (final (index, row) in valid.indexed) {
    final id = row.cell('id');
    final existing = id.isNotEmpty ? byId[id] : textMatches[index];
    String? optional(String column) =>
        row.hasColumn(column) ? row.cell(column) : null;
    rows.add(
      ScriptRow(
        kind: existing == null
            ? ScriptRowKind.added
            : _classify(project, existing, row),
        rowNumber: row.number,
        lineId: existing?.id ?? (id.isEmpty ? null : id),
        characterName: row.cell('character'),
        text: row.cell('text'),
        oldText: existing?.text[language]?.value,
        sceneName: optional('scene'),
        order: int.tryParse(row.cell('order')),
        direction: optional('direction'),
        emotion: optional('emotion'),
        pronunciation: optional('pronunciation'),
      ),
    );
  }

  return ScriptPreview(
    rows: rows,
    errors: errors,
    hasSceneColumn: csv.isNotEmpty && csv.first.hasColumn('scene'),
    missing: [
      for (final line in project.lines)
        if (!line.retired && !matched.contains(line.id)) line,
    ],
  );
}

ScriptRowKind _classify(Project project, Line line, CsvRow row) {
  if (line.retired) return ScriptRowKind.restored;
  final current = line.text[project.sourceLanguage]?.value;
  if (current != row.cell('text')) return ScriptRowKind.textChanged;

  bool differs(String column, String? value) =>
      row.hasColumn(column) && row.cell(column) != (value ?? '');
  final order = int.tryParse(row.cell('order'));
  final characterName = project.characterById(line.characterId)?.name;
  final sceneChanged =
      row.hasColumn('scene') &&
      row.cell('scene') != (line.sceneId ?? '') &&
      row.cell('scene') != (project.sceneById(line.sceneId)?.title ?? '');
  final changed =
      characterName != row.cell('character') ||
      sceneChanged ||
      (order != null && order != line.order) ||
      differs('direction', line.direction) ||
      differs('emotion', line.emotion) ||
      differs('pronunciation', line.pronunciation);
  return changed ? ScriptRowKind.detailsChanged : ScriptRowKind.unchanged;
}

String _characterIdFor(Project project, String name) {
  final existing = project.characters.where((c) => c.name == name).firstOrNull;
  if (existing != null) return existing.id;
  final id = nextSequentialId('C', project.characters.map((c) => c.id));
  project.characters.add(Character(id: id, name: name));
  return id;
}

/// Finds a scene by id or title, creating it the first time a name appears.
String _sceneIdFor(Project project, String name) {
  final existing = project.scenes
      .where((s) => s.id == name || s.title == name)
      .firstOrNull;
  if (existing != null) return existing.id;
  final id = nextSequentialId('S', project.scenes.map((s) => s.id));
  final lastOrder = project.scenes.fold(0, (m, s) => s.order > m ? s.order : m);
  project.scenes.add(Scene(id: id, title: name, order: lastOrder + _orderGap));
  return id;
}

/// The next free `order` at the end of a scene.
int nextLineOrder(Project project, String? sceneId) {
  final inScene = project.lines.where((l) => l.sceneId == sceneId);
  return inScene.fold(0, (m, l) => l.order > m ? l.order : m) + _orderGap;
}

String? _blankToNull(String value) => value.isEmpty ? null : value;

/// Applies a preview. [keepRecordings] holds the ids of changed lines the
/// initiator says don't need new recording; every other change bumps the text
/// version, since an extra review beats shipping an old recording by mistake.
void applyScriptImport(
  Project project,
  ScriptPreview preview, {
  Set<String> keepRecordings = const {},
  Set<String> retire = const {},
}) {
  if (!preview.canApply) {
    throw StateError('This import has errors and cannot be applied.');
  }
  final language = project.sourceLanguage;
  for (final row in preview.rows) {
    if (row.kind == ScriptRowKind.unchanged) continue;

    final existing = row.lineId == null ? null : project.lineById(row.lineId!);
    final String? sceneId = row.sceneName == null
        ? existing?.sceneId
        : row.sceneName!.isEmpty
        ? null
        : _sceneIdFor(project, row.sceneName!);
    final characterId = _characterIdFor(project, row.characterName);

    final line =
        existing ??
        () {
          final id =
              row.lineId ??
              nextSequentialId('L', project.lines.map((l) => l.id));
          final created = Line(
            id: id,
            characterId: characterId,
            sceneId: sceneId,
            order: row.order ?? nextLineOrder(project, sceneId),
          );
          project.lines.add(created);
          return created;
        }();

    line.characterId = characterId;
    line.sceneId = sceneId;
    line.retired = false;
    if (row.order != null) line.order = row.order!;
    if (row.direction != null) line.direction = _blankToNull(row.direction!);
    if (row.emotion != null) line.emotion = _blankToNull(row.emotion!);
    if (row.pronunciation != null) {
      line.pronunciation = _blankToNull(row.pronunciation!);
    }
    final current = line.text[language];
    if (current == null) {
      line.text[language] = LineText(row.text, 1);
    } else if (current.value != row.text) {
      current.value = row.text;
      if (!keepRecordings.contains(line.id)) current.version++;
    }
  }
  for (final id in retire) {
    project.lineById(id)?.retired = true;
  }
}

/// The script as CSV with every id filled in, ready to edit and re-import.
String exportScriptCsv(Project project) {
  return writeCsv([
    const [
      'id',
      'character',
      'scene',
      'order',
      'text',
      'direction',
      'emotion',
      'pronunciation',
    ],
    for (final line in project.orderedLines())
      [
        line.id,
        project.characterById(line.characterId)?.name ?? '',
        project.sceneById(line.sceneId)?.title ?? '',
        '${line.order}',
        line.text[project.sourceLanguage]?.value ?? '',
        line.direction ?? '',
        line.emotion ?? '',
        line.pronunciation ?? '',
      ],
  ]);
}
