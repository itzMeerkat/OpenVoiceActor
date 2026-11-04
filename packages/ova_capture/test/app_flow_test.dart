// The logic and the real native engine working together, with a generated signal
// in place of a microphone: record, export, import, review, retake.
import 'dart:async';
import 'dart:io';

import 'package:ova_capture/windows_audio.dart';
import 'package:ova_core/ova_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ova_flow_测试'));
  tearDown(() async {
    WindowsAudioOutput().stop();
    dir.deleteSync(recursive: true);
  });

  Future<Take> recordOne(RecordingController recorder, Line line) async {
    final before = recorder.actor.takesFor(line.id).length;
    recorder.startTake(line);
    await until(() => recorder.elapsedSeconds > 0.2);
    recorder.stopTake();
    await until(() => !recorder.isRecording);
    expect(recorder.actor.takesFor(line.id).length, before + 1);
    return recorder.actor.takesFor(line.id).first;
  }

  test('a project goes from initiator to actor and back', () async {
    // The two sides use separate workspaces, as on two computers.
    final initiatorHome = HomeController(Workspace(p.join(dir.path, 'a')));
    final actorHome = HomeController(Workspace(p.join(dir.path, 'b')));
    final created = initiatorHome.createProject(
      title: 'Game',
      sourceLanguage: 'en',
    );
    final initiator = InitiatorController(
      initiatorHome.workspace,
      created.id,
      freeSpace: freeDiskBytes,
    );
    final mira = initiator.addCharacter('Mira');
    final scene = initiator.addScene('Clinic', context: 'Night. Rain.');
    final line = initiator.addLine(
      characterId: mira.id,
      sceneId: scene.id,
      text: 'Who else knows?',
    );
    initiator.setUsageTerms('Use in Game.');
    final projectPath = p.join(dir.path, 'game.ovaproject');
    await initiator.exportPackage(projectPath);

    final imported = await actorHome.importProject(projectPath);
    expect(imported.outcome, ProjectImportOutcome.added);
    final actor = ActorController(actorHome.workspace, created.id);
    actor.setActorNames(displayName: 'Alex');
    final actorLine = actor.project.lineById(line.id)!;
    final recorder = RecordingController(
      SyntheticAudioInput(speed: 4),
      actor,
    )..start();
    expect(recorder.format!.bitDepth, 24);

    final first = await recordOne(recorder, actorLine);
    final second = await recordOne(recorder, actorLine);
    expect(actor.takesFor(line.id), hasLength(2));
    expect(first.audio.bitDepth, 24);
    expect(first.audio.sampleRateHz, 48000);
    expect(first.audio.channels, 1, reason: 'The chosen input becomes mono');
    expect(first.spokenText, 'Who else knows?');
    actor.toggleFavorite(second.id);

    final playback = PlaybackController(WindowsAudioOutput());
    playback.toggle(second.id, actor.audioPath(second.id));
    if (playback.error == null) {
      expect(playback.playingTakeId, second.id);
      playback.stop();
    }

    final submissionPath = p.join(dir.path, 'alex.ovasubmission');
    expect(
      () => actor.exportSubmission(submissionPath),
      throwsStateError,
      reason: 'The terms have not been accepted',
    );
    actor.acceptTerms();
    final exported = await actor.exportSubmission(submissionPath);
    expect(exported.exportedCount, 1, reason: 'Favorites only by default');
    expect(exported.skipped, isEmpty);
    expect(actor.statusOf(actorLine), LineStatus.submitted);

    final report = await initiator.importSubmission(submissionPath);
    expect(report.importedCount, 1);
    expect(report.rejected, isEmpty);
    final again = await initiator.importSubmission(submissionPath);
    expect(again.importedCount, 0);
    expect(again.alreadyImported, 1);
    final reviewLine = initiator.project.lineById(line.id)!;
    expect(initiator.statusOf(reviewLine, 'en'), LineStatus.submitted);
    final reviewTake = initiator.takesFor(line.id, 'en').single;
    expect(reviewTake.actor.displayName, 'Alex');
    expect(readWavInfo(initiator.audioPath(reviewTake)).bitDepth, 24);

    // The initiator asks for a retake and the actor answers it.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    initiator.requestRetake(reviewTake, 'More tired.');
    expect(initiator.statusOf(reviewLine, 'en'), LineStatus.retakeRequested);
    await initiator.exportPackage(projectPath);
    final updated = await actorHome.importProject(projectPath);
    expect(updated.outcome, ProjectImportOutcome.updated);

    await recorder.shutdown();
    final actor2 = ActorController(actorHome.workspace, created.id);
    final line2 = actor2.project.lineById(line.id)!;
    expect(actor2.takesFor(line.id), hasLength(2), reason: 'Takes are kept');
    expect(actor2.statusOf(line2), LineStatus.retakeRequested);
    final recorder2 = RecordingController(
      SyntheticAudioInput(speed: 4),
      actor2,
    )..start();
    final retake = await recordOne(recorder2, line2);
    expect(actor2.openRetakes(line2), isEmpty);
    actor2.toggleFavorite(retake.id);
    await actor2.exportSubmission(submissionPath);
    await recorder2.shutdown();

    await initiator.importSubmission(submissionPath);
    expect(initiator.statusOf(reviewLine, 'en'), LineStatus.submitted);
    initiator.selectTake(initiator.takesFor(line.id, 'en').first);
    expect(initiator.statusOf(reviewLine, 'en'), LineStatus.approved);

    // A text change that needs new recording undoes the approval.
    initiator.setLineText(line.id, 'en', 'Who knows?', needsNewRecording: true);
    expect(initiator.statusOf(reviewLine, 'en'), LineStatus.outdated);

    final engine = p.join(dir.path, 'engine');
    expect(await initiator.exportSelectedTakes(engine), 1);
    expect(File(p.join(engine, 'en', '${line.id}.wav')).existsSync(), isTrue);
    expect(File(p.join(engine, 'mapping.csv')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a take interrupted by a crash comes back on its line', () async {
    final home = HomeController(Workspace(dir.path));
    final created = home.createProject(title: 'Game', sourceLanguage: 'en');
    final initiator = InitiatorController(home.workspace, created.id);
    final mira = initiator.addCharacter('Mira');
    final line = initiator.addLine(characterId: mira.id, text: 'Hello.');
    final projectPath = p.join(dir.path, 'game.ovaproject');
    await initiator.exportPackage(projectPath);
    await home.importProject(projectPath);

    final actor = ActorController(home.workspace, created.id);
    final input = SyntheticAudioInput(speed: 4);
    input.open(exclusive: false);
    final (_, path) = actor.beginTake(actor.project.lineById(line.id)!);
    input.startTake(path, channel: 0);
    await until(() => input.status().framesWritten > 48000);
    // Closing mid-take finishes the file, so rename it back to what a crash
    // leaves: a partial file whose header doesn't know its length yet.
    await until(() {
      input.requestStopQuietly();
      return input.status().activity == CaptureActivity.armed;
    });
    input.close();
    File(path).renameSync('$path.partial');

    // A later launch finds the take on disk with only a pending record.
    final relaunched = ActorController(home.workspace, created.id);
    expect(relaunched.session.pending, hasLength(1));
    expect(await relaunched.recoverInterruptedTakes(input), 1);
    expect(relaunched.session.pending, isEmpty);
    final take = relaunched.takesFor(line.id).single;
    expect(take.audio.durationMs, greaterThan(500));
    expect(File(relaunched.audioPath(take.id)).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

extension on AudioInput {
  void requestStopQuietly() {
    try {
      requestStop();
    } catch (_) {
      // Refused until the writer picks up the start.
    }
  }
}
