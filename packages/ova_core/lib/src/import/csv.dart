/// A small RFC 4180 reader and writer, so spreadsheet exports just work.
library;

class CsvException implements Exception {
  CsvException(this.message);
  final String message;

  @override
  String toString() => message;
}

List<List<String>> parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldWasQuoted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    fieldWasQuoted = false;
  }

  void endRow() {
    endField();
    final isBlank = row.length == 1 && row.first.isEmpty;
    if (!isBlank) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c != '"') {
        field.write(c);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        inQuotes = false;
      }
    } else if (c == '"' && field.isEmpty && !fieldWasQuoted) {
      inQuotes = true;
      fieldWasQuoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
  }
  if (inQuotes) throw CsvException('The file ends inside a quoted field.');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

String _escape(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// With a BOM, because Excel otherwise misreads UTF-8.
String writeCsv(List<List<String>> rows) {
  final out = StringBuffer('﻿');
  for (final row in rows) {
    out.write(row.map(_escape).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

/// One data row, read by column name.
class CsvRow {
  CsvRow(this.number, this._columns, this._cells);

  /// The row's position in the file, counting the header as row 1.
  final int number;
  final Map<String, int> _columns;
  final List<String> _cells;

  bool hasColumn(String name) => _columns.containsKey(name);

  /// The trimmed cell, or empty when the column or the cell is missing.
  String cell(String name) {
    final index = _columns[name];
    if (index == null || index >= _cells.length) return '';
    return _cells[index].trim();
  }
}

/// Splits a parsed file into rows. Header names ignore case and spaces.
List<CsvRow> csvRows(String input, {required List<String> required}) {
  final rows = parseCsv(input);
  if (rows.isEmpty) throw CsvException('The file is empty.');
  final columns = <String, int>{};
  for (final (index, name) in rows.first.indexed) {
    columns[name.trim().toLowerCase()] = index;
  }
  for (final name in required) {
    if (!columns.containsKey(name)) {
      throw CsvException('The file has no "$name" column.');
    }
  }
  return [
    for (final (index, cells) in rows.skip(1).indexed)
      CsvRow(index + 2, columns, cells),
  ];
}
