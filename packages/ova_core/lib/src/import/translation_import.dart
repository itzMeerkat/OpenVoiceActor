/// Per-language translation CSV import and templates (spec section 8).
library;

import '../model/project.dart';
import 'csv.dart';

class TranslationRow {
  TranslationRow(this.lineId, this.text, this.oldText);

  final String lineId;
  final String text;

  /// Null when the line has no text in this language yet.
  final String? oldText;

  bool get isChange => oldText != null;
}

class TranslationPreview {
  TranslationPreview({
    required this.language,
    required this.changes,
    required this.unchangedCount,
    required this.unknownIds,
    required this.errors,
  });

  final String language;

  /// New and changed translations. Unchanged rows aren't listed.
  final List<TranslationRow> changes;
  final int unchangedCount;

  /// Rows whose id isn't in the project. Reported and not imported.
  final List<String> unknownIds;
  final List<String> errors;

  bool get canApply => errors.isEmpty;
}

TranslationPreview previewTranslationImport(
  Project project,
  String language,
  String csvText,
) {
  final changes = <TranslationRow>[];
  final unknownIds = <String>[];
  final errors = <String>[];
  var unchanged = 0;

  try {
    final seen = <String>{};
    final csv = csvRows(csvText, required: const ['id', 'text']);
    for (final row in csv) {
      final id = row.cell('id');
      final text = row.cell('text');
      if (id.isEmpty) {
        errors.add('Row ${row.number}: translation rows need an id.');
      } else if (!seen.add(id)) {
        errors.add('Row ${row.number}: duplicate id "$id".');
      } else if (project.lineById(id) == null) {
        unknownIds.add(id);
      } else if (text.isNotEmpty) {
        final current = project.lineById(id)!.text[language];
        if (current?.value == text) {
          unchanged++;
        } else {
          changes.add(TranslationRow(id, text, current?.value));
        }
      }
    }
  } on CsvException catch (e) {
    errors.add(e.message);
  }

  return TranslationPreview(
    language: language,
    changes: changes,
    unchangedCount: unchanged,
    unknownIds: unknownIds,
    errors: errors,
  );
}

/// [keepRecordings] works as in the script import: changed lines listed there
/// keep their version, and all others need new recording.
void applyTranslationImport(
  Project project,
  TranslationPreview preview, {
  Set<String> keepRecordings = const {},
}) {
  if (!preview.canApply) {
    throw StateError('This import has errors and cannot be applied.');
  }
  if (!project.languages.contains(preview.language)) {
    project.languages.add(preview.language);
  }
  for (final row in preview.changes) {
    final line = project.lineById(row.lineId);
    if (line == null) continue;
    final current = line.text[preview.language];
    if (current == null) {
      line.text[preview.language] = LineText(row.text, 1);
    } else {
      current.value = row.text;
      if (!keepRecordings.contains(line.id)) current.version++;
    }
  }
}

/// A sheet for translators: every id, the source text for reference, and any
/// existing translation. The import ignores the reference column.
String exportTranslationTemplate(Project project, String language) {
  final sourceColumn = 'source (${project.sourceLanguage})';
  return writeCsv([
    ['id', sourceColumn, 'text'],
    for (final line in project.orderedLines())
      [
        line.id,
        line.text[project.sourceLanguage]?.value ?? '',
        line.text[language]?.value ?? '',
      ],
  ]);
}
