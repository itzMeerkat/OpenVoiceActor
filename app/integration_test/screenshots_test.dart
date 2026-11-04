// Fills a temporary workspace with sample data and saves a picture of each main
// screen, for checking the look. Audio is generated, and nothing is played.
//
//   flutter test integration_test/screenshots_test.dart -d windows
//     --dart-define=OVA_SCREENSHOT_DIR=<folder>
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openvoiceactor/main.dart';
import 'package:openvoiceactor/services.dart';
import 'package:openvoiceactor/ui/design/components.dart';
import 'package:ova_capture/ova_capture.dart';
import 'package:ova_capture/windows_audio.dart';
import 'package:ova_core/ova_core.dart';

const _shotDir = String.fromEnvironment('OVA_SCREENSHOT_DIR');

class NoFiles implements FilePicker {
  @override
  Future<String?> pickFile(String label, List<String> extensions) async => null;
  @override
  Future<String?> pickFolder() async => null;
  @override
  Future<String?> pickSaveLocation(
    String suggestedName,
    String label,
    String extension,
  ) async => null;
}

/// Reports playback partway through a take, so the picture shows it, silently.
class SilentOutput implements AudioOutput {
  bool _playing = false;

  @override
  void play(String wavPath) => _playing = true;
  @override
  void stop() => _playing = false;
  @override
  PlaybackSnapshot status() => PlaybackSnapshot(
    _playing ? PlaybackActivity.playing : PlaybackActivity.idle,
    1000,
    2500,
  );
}

/// A 24-bit mono WAV shaped roughly like speech: bursts of syllables and gaps.
void writeSpeechLikeWav(
  String path, {
  required int seed,
  double seconds = 2.5,
}) {
  const rate = 48000;
  final frames = (seconds * rate).toInt();
  final random = math.Random(seed);
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 255, (v >> 8) & 255]);
  void u32(int v) =>
      out.add([for (var i = 0; i < 4; i++) (v >> (8 * i)) & 255]);
  out.add('RIFF'.codeUnits);
  u32(36 + frames * 3);
  out.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate * 3);
  u16(3);
  u16(24);
  out.add('data'.codeUnits);
  u32(frames * 3);

  final samples = Uint8List(frames * 3);
  var position = (0.08 * rate).toInt();
  while (position < frames * 0.92) {
    final length = ((0.08 + random.nextDouble() * 0.28) * rate).toInt();
    final loudness = 0.08 + random.nextDouble() * 0.5;
    for (var i = 0; i < length && position + i < frames; i++) {
      final envelope = math.sin(math.pi * i / length);
      final value =
          loudness * envelope * math.sin(2 * math.pi * 170 * i / rate);
      final v = (value * 8388607).toInt();
      final at = (position + i) * 3;
      samples[at] = v & 255;
      samples[at + 1] = (v >> 8) & 255;
      samples[at + 2] = (v >> 16) & 255;
    }
    position += length + ((0.03 + random.nextDouble() * 0.16) * rate).toInt();
  }
  out.add(samples);
  File(path).writeAsBytesSync(out.toBytes());
}

const _script = '''
id,character,scene,order,text,direction,emotion,pronunciation
clinic_010,Mira,The clinic,10,Who else knows about this?,"Quietly, to herself.",uneasy,Mira = MEE-rah
clinic_020,Tomas,The clinic,20,"Only the two of us, doctor. And whoever wrote the letter.",Out of breath.,worried,
clinic_030,Mira,The clinic,30,Then we have until morning.,,resolved,
clinic_040,Tomas,The clinic,40,And if the storm doesn't lift?,,,
square_010,Elder Wren,The village square,10,This valley has kept its secrets for two hundred years.,"Slow, heavy.",stern,
square_020,Mira,The village square,20,Secrets don't keep. People just stop asking.,,defiant,
square_030,Elder Wren,The village square,30,"Then stop asking, child. Before someone answers you.",A warning.,,
square_040,Tomas,The village square,40,"Doctor, we should go. Now.",Whispered.,afraid,
''';

const _translation = '''
id,text
clinic_010,还有谁知道这件事?
clinic_020,只有我们两个,医生。还有写这封信的人。
clinic_030,那我们只有到早上的时间了。
''';

/// A temporary workspace holding one project with takes, seen from both sides.
Future<(Directory, AppServices)> _sampleWorkspace(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('ova_screenshots');
  final workspace = Workspace('${dir.path}\\data');
  final services = AppServices(
    workspace: workspace,
    createInput: () => SyntheticAudioInput(format: SampleFormat.s24),
    output: SilentOutput(),
    freeSpace: freeDiskBytes,
    files: NoFiles(),
  );
  final projectFile = '${dir.path}\\p.ovaproject';
  final submissionFile = '${dir.path}\\s.ovasubmission';

  await tester.runAsync(() async {
    final home = HomeController(workspace);
    final project = home.createProject(
      title: 'Mountain Village',
      sourceLanguage: 'en',
    );
    final initiator = InitiatorController(workspace, project.id);
    initiator.applyScript(initiator.previewScript(_script));
    initiator.applyTranslation(
      initiator.previewTranslation('zh-Hans', _translation),
    );
    initiator.updateScene(
      initiator.project.scenes.first.id,
      context: 'Night. Rain outside. Mira has just found the letter.',
    );
    initiator.updateScene(
      initiator.project.scenes.last.id,
      context: 'Morning market, crowded. Everyone is listening.',
    );
    initiator.updateCharacter(
      initiator.project.characters.first.id,
      description: 'Village doctor, 40s, dry humor.',
    );
    initiator.setUsageTerms(
      'Recordings may be used in Mountain Village and its marketing.',
    );
    initiator.updateDetails(
      description: 'A cozy mystery set in a mountain village.',
      minSampleRateHz: 44100,
      minBitDepth: 16,
    );
    home.createProject(
      title: 'Harbor Lights demo',
      sourceLanguage: 'ja',
      otherLanguages: ['en'],
    );
    await initiator.exportPackage(projectFile);
    await home.importProject(projectFile);

    final actor = ActorController(workspace, project.id);
    actor.setActorNames(displayName: 'Alex Chen');
    actor.acceptTerms();
    final lines = actor.project.orderedLines();
    var seed = 1;
    Future<void> record(Line line, {required int takes, int? favorite}) async {
      for (var t = 0; t < takes; t++) {
        final (pending, path) = actor.beginTake(line);
        writeSpeechLikeWav(path, seed: seed++, seconds: 1.6 + (seed % 4) * 0.5);
        final take = await actor.finishTake(pending);
        if (t == favorite) actor.toggleFavorite(take!.id);
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
    }

    await record(lines[0], takes: 3, favorite: 1);
    await record(lines[1], takes: 2, favorite: 0);
    await record(lines[2], takes: 1, favorite: 0);
    await record(lines[4], takes: 2, favorite: 1);
    await actor.exportSubmission(submissionFile);
    await record(lines[3], takes: 1);

    final report = await initiator.importSubmission(submissionFile);
    expect(report.rejected, isEmpty);
    final reviewLines = initiator.project.orderedLines();
    initiator.selectTake(initiator.takesFor(reviewLines[2].id, 'en').first);
    initiator.selectTake(initiator.takesFor(reviewLines[1].id, 'en').first);
    initiator.requestRetake(
      initiator.takesFor(reviewLines[4].id, 'en').first,
      'A little more tired, less suspicious.',
    );
    initiator.setLineText(
      reviewLines[2].id,
      'en',
      'Then we only have until morning.',
      needsNewRecording: true,
    );
    await initiator.exportPackage(projectFile);
    await home.importProject(projectFile);
  });
  return (dir, services);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the main screens', (tester) async {
    expect(_shotDir, isNotEmpty, reason: 'Set OVA_SCREENSHOT_DIR');
    final (dir, services) = await _sampleWorkspace(tester);

    final shotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: OpenVoiceActorApp(services: services),
      ),
    );

    Future<void> wait([int ms = 500]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shoot(String name) async {
      await wait(450);
      final boundary =
          shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_shotDir\\$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> tapText(String text) async {
      await wait(150);
      await tester.tap(find.text(text).last);
      await wait(350);
    }

    await wait(300);
    await shoot('1_home');

    await tapText('Mountain Village');
    await shoot('2_script');
    await tapText('Add line');
    await shoot('3_line_editor');
    await tapText('Cancel');
    await tapText('Review');
    await shoot('4_review');
    await tapText('Only the two of us, doctor. And whoever wrote the letter.');
    await tester.tap(find.byTooltip('Play').first);
    await shoot('5_review_playing');
    await tester.tap(find.byTooltip('Stop').first);
    await tapText('Setup');
    await shoot('6_setup');
    await tester.pageBack();
    await wait();

    await tapText('Voice actor');
    await shoot('7_home_actor');
    await tapText('Mountain Village');
    await wait(800);
    await shoot('8_record');
    await tester.tap(find.text('Record'));
    await wait(2400);
    await shoot('9_recording');
    await tester.tap(find.text('Stop'));
    await wait(700);
    await tapText('Export takes');
    await shoot('10_export');
    await tapText('Cancel');

    // The smallest window Windows allows, less its frame. Anything that doesn't
    // fit raises an overflow error here and fails this test.
    tester.view.physicalSize = const Size(980, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await shoot('min_record');
    await tester.pageBack();
    await wait();
    await shoot('min_home_actor');
    await tapText('Project owner');
    await tapText('Mountain Village');
    await shoot('min_script');
    await tapText('Review');
    await tapText('Then we only have until morning.');
    await shoot('min_review');
    await tapText('Setup');
    await shoot('min_setup');
    await tester.pageBack();
    await wait();

    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('capture the phone screens', (tester) async {
    expect(_shotDir, isNotEmpty, reason: 'Set OVA_SCREENSHOT_DIR');
    // Android's touch sizes and scrolling, rather than the desktop's.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(tester.view.reset);
    final (dir, services) = await _sampleWorkspace(tester);

    final shotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: OpenVoiceActorApp(services: services),
      ),
    );

    Future<void> wait([int ms = 500]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shoot(String name) async {
      await wait(450);
      final boundary =
          shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_shotDir\\$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> tapText(String text) async {
      await wait(150);
      await tester.tap(find.text(text).last);
      await wait(350);
    }

    Future<void> tapTip(String tip) async {
      await wait(150);
      await tester.tap(find.byTooltip(tip).first);
      await wait(350);
    }

    Future<void> closeSheet() async {
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await wait(450);
    }

    void setSize(Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
    }

    // Walks every screen at one size. Anything that doesn't fit raises an
    // overflow error here and fails this test.
    Future<void> walk(String prefix, {bool every = true}) async {
      Future<void> shot(String name) => shoot('${prefix}_$name');

      await wait(300);
      await shot('1_home');
      await tapText('Mountain Village');
      await shot('2_script');
      await tapText('Add line');
      await shot('3_line_editor');
      await tester.tap(find.byType(CloseButton));
      await wait();
      await tapText('Review');
      await shot('4_review');
      await tapText(
        'Only the two of us, doctor. And whoever wrote the letter.',
      );
      await shot('5_review_line');
      await tester.tap(find.byTooltip('Play').first);
      await shot('6_review_playing');
      await tester.tap(find.byTooltip('Stop').first);
      await tester.pageBack();
      await wait();
      await tapText('Setup');
      await shot('7_setup');
      await tester.pageBack();
      await wait();
      await tapText('Voice actor');
      await shot('8_home_actor');
      await tapText('Mountain Village');
      await wait(800);
      await shot('9_record');
      await tapText('Line 1 of 8');
      await shot('10_script_sheet');
      await tapText(
        'Only the two of us, doctor. And whoever wrote the letter.',
      );
      await shot('11_record_line2');
      await tester.tap(find.byTooltip('Input settings'));
      await wait();
      await shot('12_input_sheet');
      await closeSheet();
      await tester.tap(find.byType(RecordButton));
      await wait(2400);
      await shot('13_recording');
      await tester.tap(find.byType(RecordButton));
      await wait(700);
      await tapTip('Export takes');
      await shot('14_export');
      await tester.tap(find.byType(CloseButton));
      await wait();
      await tester.pageBack();
      await wait();
      await tapText('Project owner');
    }

    final sizes = {
      'phone': const Size(390, 844),
      'small': const Size(320, 568),
      'side': const Size(844, 390),
      'tablet': const Size(768, 1024),
    };
    for (final MapEntry(key: prefix, value: size) in sizes.entries) {
      setSize(size);
      await walk(prefix);
    }

    dir.deleteSync(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  }, timeout: const Timeout(Duration(minutes: 10)));
}
