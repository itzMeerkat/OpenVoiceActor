import 'dart:io';

import 'package:ova_core/ova_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_support.dart';

Future<void> settle(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory dir;
  late HomeController home;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('ova_controller_test');
    home = HomeController(Workspace(dir.path));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('initiator', () {
    late InitiatorController c;
    late Line line;
    setUp(() {
      final project = home.createProject(title: 'Game', sourceLanguage: 'en');
      c = InitiatorController(home.workspace, project.id);
      final mira = c.addCharacter('Mira');
      line = c.addLine(characterId: mira.id, text: 'Hello');
    });

    test('changes persist across reopening', () {
      final reopened = InitiatorController(home.workspace, c.project.id);
      expect(reopened.project.lines.single.id, line.id);
      expect(reopened.project.lines.single.text['en']!.value, 'Hello');
    });

    test('text version follows the initiator\'s decision', () {
      c.setLineText(line.id, 'en', 'Hello!', needsNewRecording: false);
      expect(line.text['en']!.version, 1);
      c.setLineText(line.id, 'en', 'Goodbye', needsNewRecording: true);
      expect(line.text['en']!.version, 2);
      c.setLineText(line.id, 'en', 'Goodbye', needsNewRecording: true);
      expect(line.text['en']!.version, 2, reason: 'No change, no new version');
    });

    test('line details never change the text version', () {
      c.updateLineDetails(
        line.id,
        characterId: line.characterId,
        sceneId: null,
        direction: 'Softly',
        emotion: 'sad',
        pronunciation: null,
      );
      expect(line.direction, 'Softly');
      expect(line.text['en']!.version, 1);
    });

    test('changing the terms raises their version only on a real change', () {
      c.setUsageTerms('Terms');
      expect(c.project.usageTerms!.version, 1);
      c.setUsageTerms('Terms');
      expect(c.project.usageTerms!.version, 1);
      c.setUsageTerms('New terms');
      expect(c.project.usageTerms!.version, 2);
      c.setUsageTerms('');
      expect(c.project.usageTerms, isNull);
    });

    test(
      'each export raises the revision, and a failed one does not',
      () async {
        await c.exportPackage(p.join(dir.path, 'a.ovaproject'));
        await c.exportPackage(p.join(dir.path, 'a.ovaproject'));
        expect(c.project.revision, 2);
        // A folder in the way makes the final rename fail.
        final blocked = p.join(dir.path, 'blocked.ovaproject');
        Directory(blocked).createSync();
        await expectLater(c.exportPackage(blocked), throwsA(anything));
        expect(c.project.revision, 2);
        expect(File('$blocked.tmp').existsSync(), isFalse);
      },
    );

    test('a language can be added and removed, except the source', () {
      c.addLanguage('zh-Hans');
      expect(c.project.languages, contains('zh-Hans'));
      expect(() => c.addLanguage('not a tag'), throwsArgumentError);
      c.removeLanguage('zh-Hans');
      expect(() => c.removeLanguage('en'), throwsArgumentError);
    });

    test('progress counts each status per language', () {
      c.addLine(characterId: line.characterId, text: 'Two');
      final progress = c.progress('en');
      expect(progress.total, 2);
      expect(progress.of(LineStatus.notRecorded), 2);
    });
  });

  group('actor project import', () {
    late String packagePath;
    late InitiatorController initiator;
    setUp(() async {
      final project = home.createProject(title: 'Game', sourceLanguage: 'en');
      initiator = InitiatorController(home.workspace, project.id);
      final mira = initiator.addCharacter('Mira');
      initiator.addLine(characterId: mira.id, text: 'Hello');
      packagePath = p.join(dir.path, 'p.ovaproject');
      await initiator.exportPackage(packagePath);
    });

    test('follows the revision rules', () async {
      final first = await home.importProject(packagePath);
      expect(first.outcome, ProjectImportOutcome.added);
      final same = await home.importProject(packagePath);
      expect(same.outcome, ProjectImportOutcome.unchanged);

      final older = p.join(dir.path, 'older.ovaproject');
      File(packagePath).copySync(older);
      await initiator.exportPackage(packagePath);
      final newer = await home.importProject(packagePath);
      expect(newer.outcome, ProjectImportOutcome.updated);
      expect(newer.project.revision, 2);
      final refused = await home.importProject(older);
      expect(refused.outcome, ProjectImportOutcome.refusedOlder);
      expect(home.actorProjects.single.revision, 2);
    });
  });

  group('recording', () {
    late ActorController actor;
    late RecordingController recorder;
    late FakeInput input;
    late Line line;
    late InitiatorController initiator;

    setUp(() async {
      final project = home.createProject(
        title: 'Game',
        sourceLanguage: 'en',
        otherLanguages: ['fr'],
      );
      initiator = InitiatorController(home.workspace, project.id);
      final mira = initiator.addCharacter('Mira');
      final added = initiator.addLine(characterId: mira.id, text: 'Hello');
      final package = p.join(dir.path, 'p.ovaproject');
      await initiator.exportPackage(package);
      await home.importProject(package);
      actor = ActorController(home.workspace, project.id);
      line = actor.project.lineById(added.id)!;
      input = FakeInput();
      recorder = RecordingController(input, actor, countIn: Duration.zero)
        ..start();
    });
    tearDown(() => recorder.shutdown());

    Future<Take> record() async {
      recorder.startTake(line);
      recorder.stopTake();
      await settle(() => !recorder.isRecording);
      return actor.takesFor(line.id).first;
    }

    test('opens the default device and meters every channel', () async {
      expect(recorder.device!.name, 'Fake mic');
      expect(recorder.format!.channels, 2);
      expect(recorder.meters, hasLength(2));
      await settle(() => recorder.meters.first > 0);
    });

    test('every take is tracked and stays on its line', () async {
      final a = await record();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = await record();
      expect(actor.takesFor(line.id).map((t) => t.id), [b.id, a.id]);
      expect(a.textVersion, 1);
      expect(a.spokenText, 'Hello');
      expect(a.audio.bitDepth, 16);
      expect(actor.session.pending, isEmpty);
      expect(actor.statusOf(line), LineStatus.recorded);
    });

    test('takes survive a restart', () async {
      final take = await record();
      actor.toggleFavorite(take.id);
      final reopened = ActorController(home.workspace, actor.project.id);
      expect(reopened.takesFor(line.id).single.favorite, isTrue);
    });

    test('the chosen input channel is what gets recorded', () async {
      recorder.selectChannel(1);
      await record();
      expect(input.lastChannel, 1);
      final reopened = ActorController(home.workspace, actor.project.id);
      expect(reopened.settings.inputChannel, 1);
    });

    test('a take leaves out the sound of pressing record and stop', () async {
      await record();
      // The pre-roll must end well after the press that started the count-in.
      expect(
        input.lastPreRollMs,
        lessThan(defaultCountIn.inMilliseconds - 500),
      );
      expect(input.lastPreRollMs, greaterThan(0));
      expect(input.lastTrimEndMs, greaterThan(0));
    });

    test('capture waits for the count-in', () async {
      final counting = RecordingController(
        input,
        actor,
        countIn: const Duration(milliseconds: 60),
      )..start();
      addTearDown(counting.shutdown);
      counting.startTake(line);
      expect(counting.isCountingIn, isTrue);
      expect(counting.isRecording, isTrue);
      expect(counting.recordingLineId, line.id);
      expect(input.starts, 0);
      expect(actor.session.pending, isEmpty);
      await settle(() => !counting.isCountingIn);
      expect(input.starts, 1);
      expect(counting.isRecording, isTrue);
      counting.stopTake();
      await settle(() => !counting.isRecording);
      expect(actor.takesFor(line.id), hasLength(1));
    });

    test('stopping during the count-in records nothing', () async {
      final counting = RecordingController(
        input,
        actor,
        countIn: const Duration(milliseconds: 60),
      )..start();
      addTearDown(counting.shutdown);
      counting.startTake(line);
      counting.stopTake();
      expect(counting.isRecording, isFalse);
      expect(counting.recordingLineId, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(input.starts, 0);
      expect(actor.takesFor(line.id), isEmpty);
      expect(actor.session.pending, isEmpty);
    });

    test('the role is remembered', () {
      final home = HomeController(actor.workspace);
      expect(home.role, AppRole.owner);
      home.setRole(AppRole.actor);
      expect(HomeController(actor.workspace).role, AppRole.actor);
    });

    test('the device choice is remembered', () {
      recorder.open(recorder.devices[1]);
      final again = RecordingController(input, actor)..start();
      expect(again.device!.name, 'Other mic');
      again.shutdown();
    });

    test('a device failing with no audio leaves no take behind', () async {
      input
        ..writeFile = false
        ..outcome = TakeOutcome.deviceLost;
      recorder.startTake(line);
      recorder.stopTake();
      await settle(() => !recorder.isRecording);
      expect(actor.takesFor(line.id), isEmpty);
      expect(actor.session.pending, isEmpty);
      expect(recorder.takeNotice, contains('before anything was recorded'));
    });

    test('a take cut short by the device is saved and explained', () async {
      input.outcome = TakeOutcome.deviceLost;
      await record();
      expect(actor.takesFor(line.id), hasLength(1));
      expect(recorder.takeNotice, contains('has been saved'));
    });

    test('a pending take is recovered on its line after a crash', () async {
      final (_, path) = actor.beginTake(line);
      writeTestWav('$path.partial');
      final relaunched = ActorController(home.workspace, actor.project.id);
      expect(await relaunched.recoverInterruptedTakes(input), 1);
      expect(relaunched.takesFor(line.id), hasLength(1));
      expect(relaunched.session.pending, isEmpty);
    });

    test('a pending take with no audio is simply cleared', () async {
      actor.beginTake(line);
      final relaunched = ActorController(home.workspace, actor.project.id);
      expect(await relaunched.recoverInterruptedTakes(input), 0);
      expect(relaunched.session.pending, isEmpty);
    });

    test('a line with no text in the language cannot be recorded', () {
      actor.setLanguage('fr');
      expect(actor.visibleLines, isEmpty);
      expect(() => actor.beginTake(line), throwsStateError);
    });

    test('a changed line makes takes outdated and keeps them', () async {
      await record();
      initiator.setLineText(line.id, 'en', 'Goodbye', needsNewRecording: true);
      final package = p.join(dir.path, 'p.ovaproject');
      await initiator.exportPackage(package);
      await home.importProject(package);
      final updated = ActorController(home.workspace, actor.project.id);
      final current = updated.project.lineById(line.id)!;
      expect(updated.takesFor(line.id), hasLength(1));
      expect(updated.statusOf(current), LineStatus.outdated);
    });

    test('a wording fix keeps takes valid and shows the difference', () async {
      final take = await record();
      initiator.setLineText(line.id, 'en', 'Hello!', needsNewRecording: false);
      final package = p.join(dir.path, 'p.ovaproject');
      await initiator.exportPackage(package);
      await home.importProject(package);
      final updated = ActorController(home.workspace, actor.project.id);
      final current = updated.project.lineById(line.id)!;
      expect(updated.statusOf(current), LineStatus.recorded);
      expect(isOutdated(take, current), isFalse);
      expect(spokenTextDiffers(take, current), isTrue);
    });

    test('a low-spec input gets a warning but can still record', () async {
      actor.project.audioRequest = AudioRequest(
        minSampleRateHz: 96000,
        minBitDepth: 24,
      );
      expect(recorder.audioRequestWarning, contains('96000 Hz and 24-bit'));
      await record();
      expect(actor.takesFor(line.id), hasLength(1));
    });

    group('export', () {
      test('needs a name and takes', () async {
        final path = p.join(dir.path, 's.ovasubmission');
        await record();
        await expectLater(actor.exportSubmission(path), throwsStateError);
        actor.setActorNames(displayName: 'Alex');
        await expectLater(
          actor.exportSubmission(path),
          throwsStateError,
          reason: 'Nothing is marked as a favorite',
        );
      });

      test('favorites only by default, then all when asked', () async {
        actor.setActorNames(displayName: 'Alex');
        final a = await record();
        await record();
        actor.toggleFavorite(a.id);
        const favorites = ExportOptions();
        const all = ExportOptions(favoritesOnly: false);
        expect(actor.takesToExport(favorites), hasLength(1));
        expect(actor.takesToExport(all), hasLength(2));
        expect(actor.exportSizeBytes(all), greaterThan(0));
      });

      test(
        'leaves out exported takes unless asked, and device names',
        () async {
          actor.setActorNames(displayName: 'Alex');
          final take = await record();
          actor.toggleFavorite(take.id);
          final path = p.join(dir.path, 's.ovasubmission');
          await actor.exportSubmission(path);
          expect(actor.takesToExport(const ExportOptions()), isEmpty);
          expect(
            actor.takesToExport(
              const ExportOptions(includeAlreadyExported: true),
            ),
            hasLength(1),
          );

          await initiator.importSubmission(path);
          final received = initiator.takesFor(line.id, 'en').single.take;
          expect(received.capture!.inputDeviceName, isNull);
          expect(take.capture!.inputDeviceName, 'Fake mic');
        },
      );

      test('a damaged audio file is left out and reported', () async {
        actor.setActorNames(displayName: 'Alex');
        final bad = await record();
        final good = await record();
        actor.toggleFavorite(bad.id);
        actor.toggleFavorite(good.id);
        File(actor.audioPath(bad.id)).writeAsStringSync('damaged');
        final report = await actor.exportSubmission(
          p.join(dir.path, 's.ovasubmission'),
        );
        expect(report.exportedCount, 1);
        expect(report.skipped.single.takeId, bad.id);
        expect(actor.session.exportedTakeIds, {good.id});
      });

      test('deleting a take removes its audio', () async {
        final take = await record();
        final path = actor.audioPath(take.id);
        actor.deleteTake(take.id);
        expect(File(path).existsSync(), isFalse);
        expect(actor.takesFor(line.id), isEmpty);
      });
    });
  });
}
