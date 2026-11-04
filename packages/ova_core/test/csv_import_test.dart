import 'package:ova_core/ova_core.dart';
import 'package:ova_core/src/import/csv.dart';
import 'package:test/test.dart';

Project emptyProject() => Project(
  id: '3f1c9a52-6a0e-4c58-9d0b-2f6d3f0b7a11',
  title: 'Game',
  sourceLanguage: 'en',
  languages: ['en'],
);

void main() {
  group('CSV parsing', () {
    test('handles a BOM, quotes, commas, newlines and CRLF', () {
      final rows = parseCsv('﻿a,b\r\n"x, y","say ""hi""\nthere"\r\n');
      expect(rows, [
        ['a', 'b'],
        ['x, y', 'say "hi"\nthere'],
      ]);
    });

    test('skips blank lines and accepts a missing final newline', () {
      expect(parseCsv('a\n\nb'), [
        ['a'],
        ['b'],
      ]);
    });

    test('rejects an unterminated quote', () {
      expect(() => parseCsv('"a'), throwsA(isA<CsvException>()));
    });

    test('writes what it reads', () {
      final rows = [
        ['id', 'text'],
        ['1', 'a, "b"\nc'],
      ];
      expect(parseCsv(writeCsv(rows)), rows);
    });
  });

  group('script import', () {
    test('needs character and text columns', () {
      final preview = previewScriptImport(emptyProject(), 'id,text\n1,hi\n');
      expect(preview.canApply, isFalse);
      expect(preview.errors.single, contains('character'));
    });

    test('generates line, character and scene ids', () {
      final project = emptyProject();
      final preview = previewScriptImport(
        project,
        'character,text,scene\nMira,Hello,Clinic\nMira,Bye,Clinic\nTom,Hi,\n',
      );
      expect(preview.ofKind(ScriptRowKind.added), hasLength(3));
      applyScriptImport(project, preview);
      expect(project.lines.map((l) => l.id), ['L000001', 'L000002', 'L000003']);
      expect(project.characters.map((c) => c.name), ['Mira', 'Tom']);
      expect(project.characters.first.id, 'C000001');
      expect(project.scenes.single.title, 'Clinic');
      expect(project.lines[1].order, greaterThan(project.lines[0].order));
      expect(project.lines[0].text['en']!.version, 1);
      expect(project.lines[2].sceneId, isNull);
    });

    test('reports bad rows with their numbers and blocks applying', () {
      final preview = previewScriptImport(
        emptyProject(),
        'id,character,text,order\na,M,x,1\na,M,y,2\nb,,z,3\nc,M,,4\nd,M,w,x\n',
      );
      expect(preview.canApply, isFalse);
      expect(preview.errors, hasLength(4));
      expect(preview.errors.first, startsWith('Row 3:'));
      expect(
        () => applyScriptImport(emptyProject(), preview),
        throwsStateError,
      );
    });

    test('keeps ids that are provided, of any shape', () {
      final project = emptyProject();
      applyScriptImport(
        project,
        previewScriptImport(project, 'id,character,text\n../../x y,M,Hi\n'),
      );
      expect(project.lines.single.id, '../../x y');
    });

    group('re-import', () {
      late Project project;
      setUp(() {
        project = emptyProject();
        applyScriptImport(
          project,
          previewScriptImport(
            project,
            'id,character,text\na,Mira,Hello\nb,Mira,Bye\n',
          ),
        );
      });

      test('a row with an id updates its line, and text needs a decision', () {
        final preview = previewScriptImport(
          project,
          'id,character,text\na,Mira,Hello there\nb,Mira,Bye\n',
        );
        final changed = preview.ofKind(ScriptRowKind.textChanged).single;
        expect(changed.oldText, 'Hello');
        expect(preview.ofKind(ScriptRowKind.unchanged), hasLength(1));
        expect(preview.missing, isEmpty);
        applyScriptImport(project, preview);
        expect(project.lineById('a')!.text['en']!.value, 'Hello there');
        expect(project.lineById('a')!.text['en']!.version, 2);
        expect(project.lineById('b')!.text['en']!.version, 1);
      });

      test('the initiator can keep recordings valid for a text change', () {
        final preview = previewScriptImport(
          project,
          'id,character,text\na,Mira,Hello!\nb,Mira,Bye\n',
        );
        applyScriptImport(project, preview, keepRecordings: {'a'});
        expect(project.lineById('a')!.text['en']!.value, 'Hello!');
        expect(project.lineById('a')!.text['en']!.version, 1);
      });

      test('a row without an id matches by character and exact text', () {
        final preview = previewScriptImport(
          project,
          'character,text\nMira,Hello\nMira,Bye\n',
        );
        expect(preview.ofKind(ScriptRowKind.unchanged), hasLength(2));
        applyScriptImport(project, preview);
        expect(project.lines, hasLength(2));
      });

      test('an edited row without an id is one new line and one missing', () {
        final preview = previewScriptImport(
          project,
          'character,text\nMira,Hello there\nMira,Bye\n',
        );
        expect(preview.ofKind(ScriptRowKind.added), hasLength(1));
        expect(preview.missing.single.id, 'a');
        applyScriptImport(project, preview, retire: {'a'});
        expect(project.lineById('a')!.retired, isTrue);
        expect(project.lines, hasLength(3), reason: 'Nothing is deleted');
        expect(project.lines.last.id, 'L000001');
      });

      test('identical rows pair with lines in order', () {
        final p = emptyProject();
        applyScriptImport(
          p,
          previewScriptImport(
            p,
            'id,character,text,order\nx,M,Yes,20\ny,M,Yes,10\n',
          ),
        );
        final preview = previewScriptImport(
          p,
          'character,text,direction\nM,Yes,first\nM,Yes,second\n',
        );
        applyScriptImport(p, preview);
        expect(p.lineById('y')!.direction, 'first');
        expect(p.lineById('x')!.direction, 'second');
      });

      test('a retired line in the file comes back', () {
        project.lineById('a')!.retired = true;
        final preview = previewScriptImport(
          project,
          'id,character,text\na,Mira,Hello\nb,Mira,Bye\n',
        );
        expect(preview.ofKind(ScriptRowKind.restored).single.lineId, 'a');
        applyScriptImport(project, preview);
        expect(project.lineById('a')!.retired, isFalse);
      });

      test('generated ids never reuse a retired line\'s id', () {
        final p = emptyProject();
        applyScriptImport(p, previewScriptImport(p, 'character,text\nM,One\n'));
        p.lines.single.retired = true;
        applyScriptImport(p, previewScriptImport(p, 'character,text\nM,Two\n'));
        expect(p.lines.last.id, 'L000002');
      });

      test('a missing column keeps the value and an empty cell clears it', () {
        project.lineById('a')!.direction = 'Softly';
        applyScriptImport(
          project,
          previewScriptImport(project, 'id,character,text\na,Mira,Hello\n'),
        );
        expect(project.lineById('a')!.direction, 'Softly');
        applyScriptImport(
          project,
          previewScriptImport(
            project,
            'id,character,text,direction\na,Mira,Hello,\n',
          ),
        );
        expect(project.lineById('a')!.direction, isNull);
      });

      test('the exported CSV re-imports with no changes', () {
        project.lineById('a')!.direction = 'Softly, "really"';
        final preview = previewScriptImport(project, exportScriptCsv(project));
        expect(preview.canApply, isTrue);
        expect(preview.ofKind(ScriptRowKind.unchanged), hasLength(2));
        expect(preview.missing, isEmpty);
      });
    });
  });

  group('translation import', () {
    late Project project;
    setUp(() {
      project = emptyProject();
      applyScriptImport(
        project,
        previewScriptImport(project, 'id,character,text\na,M,Hi\nb,M,Bye\n'),
      );
    });

    test('adds text at version 1 and adds the language', () {
      final preview = previewTranslationImport(
        project,
        'zh-Hans',
        'id,text\na,你好\n',
      );
      applyTranslationImport(project, preview);
      expect(project.languages, contains('zh-Hans'));
      expect(project.lineById('a')!.text['zh-Hans']!.value, '你好');
      expect(project.lineById('a')!.text['zh-Hans']!.version, 1);
    });

    test('unknown ids are reported and not imported', () {
      final preview = previewTranslationImport(
        project,
        'fr',
        'id,text\nnope,Salut\na,Salut\n',
      );
      expect(preview.unknownIds, ['nope']);
      expect(preview.canApply, isTrue);
      applyTranslationImport(project, preview);
      expect(project.lineById('a')!.text['fr']!.value, 'Salut');
    });

    test('rows need ids, and duplicates are errors', () {
      expect(
        previewTranslationImport(project, 'fr', 'id,text\n,x\n').canApply,
        isFalse,
      );
      expect(
        previewTranslationImport(project, 'fr', 'id,text\na,x\na,y\n').canApply,
        isFalse,
      );
    });

    test('changes raise the version unless kept', () {
      applyTranslationImport(
        project,
        previewTranslationImport(project, 'fr', 'id,text\na,Salut\nb,Adieu\n'),
      );
      final preview = previewTranslationImport(
        project,
        'fr',
        'id,text\na,Bonjour\nb,Au revoir\n',
      );
      expect(preview.changes.every((c) => c.isChange), isTrue);
      applyTranslationImport(project, preview, keepRecordings: {'b'});
      expect(project.lineById('a')!.text['fr']!.version, 2);
      expect(project.lineById('b')!.text['fr']!.version, 1);
    });

    test('the template round trips, ignoring the reference column', () {
      project.lineById('a')!.text['fr'] = LineText('Salut', 1);
      final preview = previewTranslationImport(
        project,
        'fr',
        exportTranslationTemplate(project, 'fr'),
      );
      expect(preview.errors, isEmpty);
      expect(preview.unchangedCount, 1);
      expect(preview.changes, isEmpty, reason: 'Blank rows are left alone');
    });
  });
}
