// Walks the screens with stand-ins for audio and file dialogs. Run with the real
// engine in packages/ova_capture/test/app_flow_test.dart for the audio itself.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvoiceactor/main.dart';
import 'package:openvoiceactor/services.dart';
import 'package:openvoiceactor/ui/design/components.dart';
import 'package:ova_core/ova_core.dart';

class StubInput implements AudioInput {
  @override
  List<InputDeviceInfo> listDevices() => const [
    InputDeviceInfo(index: 0, name: 'Test mic', isDefault: true),
  ];

  @override
  InputFormat open({int? deviceIndex, required bool exclusive}) =>
      const InputFormat(
        isFloat: false,
        bitDepth: 24,
        sampleRateHz: 48000,
        channels: 1,
        exclusive: false,
        rawMode: true,
      );

  @override
  void close() {}
  @override
  void startTake(String wavPath, {required int channel, int preRollMs = 0}) {}
  @override
  void requestStop({int trimEndMs = 0}) {}
  @override
  CaptureSnapshot status() => const CaptureSnapshot(
    activity: CaptureActivity.armed,
    peaks: [0.5],
    framesWritten: 0,
    droppedFrames: 0,
    clippedSamples: 0,
    deviceLost: false,
    lastOutcome: TakeOutcome.unknown,
  );
  @override
  int recoverPartial(String partialPath) => 0;
}

class StubOutput implements AudioOutput {
  @override
  void play(String wavPath) {}
  @override
  void stop() {}
  @override
  PlaybackSnapshot status() =>
      const PlaybackSnapshot(PlaybackActivity.idle, 0, 0);
}

class StubFiles implements FilePicker {
  String? next;

  @override
  Future<String?> pickFile(String label, List<String> extensions) async => next;
  @override
  Future<String?> pickFolder() async => next;
  @override
  Future<String?> pickSaveLocation(
    String suggestedName,
    String label,
    String extension,
  ) async => next;
}

void main() {
  late Directory dir;
  late AppServices services;
  late StubFiles files;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ova_widget_test');
    files = StubFiles();
    services = AppServices(
      workspace: Workspace(dir.path),
      createInput: StubInput.new,
      output: StubOutput(),
      freeSpace: (_) => null,
      files: files,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> setLargeWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('on a phone, create a project and write a line', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(OpenVoiceActorApp(services: services));

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My Game');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Add line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mira');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Line (en)'),
      'Who else knows?',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Who else knows?'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Who else knows?'));
    await tester.pumpAndSettle();
    expect(find.text('No takes yet.'), findsOneWidget);
    expect(find.text('Line 1 of 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Mira'), findsOneWidget);
  });

  testWidgets('on a phone, an actor moves between lines and opens input', (
    tester,
  ) async {
    await setPhone(tester);
    final package = '${dir.path}/game.ovaproject';
    final home = HomeController(services.workspace);
    await tester.runAsync(() async {
      final project = home.createProject(title: 'Game', sourceLanguage: 'en');
      final initiator = InitiatorController(services.workspace, project.id);
      final mira = initiator.addCharacter('Mira');
      initiator.addLine(characterId: mira.id, text: 'First line');
      initiator.addLine(characterId: mira.id, text: 'Second line');
      await initiator.exportPackage(package);
      await home.importProject(package);
    });

    await tester.pumpWidget(OpenVoiceActorApp(services: services));
    await tester.tap(find.text('Voice actor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);

    // A swipe moves to the next line.
    await tester.fling(find.text('First line'), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Second line'), findsOneWidget);

    // Picking from the script sheet moves back, and closes the sheet.
    await tester.tap(find.text('Line 2 of 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('All characters'), findsOneWidget);
    await tester.tap(find.text('First line'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('All characters'), findsNothing);
    expect(find.text('Line 1 of 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Input settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Exclusive mode'), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The button counts in first, and pressing it again cancels the take.
    await tester.tap(find.text('Record'));
    await tester.pump();
    expect(find.text('Get ready'), findsOneWidget);
    await tester.tap(find.text('Get ready'));
    await tester.pump();
    expect(find.text('Record'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Record'), findsOneWidget);

    // Leave the screen so the meter timer stops before the test ends.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('stop fires on press, once, and record fires on release', (
    tester,
  ) async {
    var presses = 0;
    Widget button({required bool actOnPress}) => MaterialApp(
      home: Scaffold(
        body: RecordButton(
          recording: actOnPress,
          actOnPress: actOnPress,
          label: 'Button',
          onPressed: () => presses++,
        ),
      ),
    );

    await tester.pumpWidget(button(actOnPress: true));
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(RecordButton)),
    );
    await tester.pump();
    expect(presses, 1);
    // The take can finish while the button is held. Releasing must not start
    // another one.
    await tester.pumpWidget(button(actOnPress: false));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(presses, 1);

    gesture = await tester.startGesture(
      tester.getCenter(find.byType(RecordButton)),
    );
    await tester.pump();
    expect(presses, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(presses, 2);
  });

  testWidgets('the role is chosen at the top and remembered', (tester) async {
    await setLargeWindow(tester);
    await tester.pumpWidget(OpenVoiceActorApp(services: services));
    expect(find.text('Your projects'), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    await tester.tap(find.text('Voice actor'));
    await tester.pumpAndSettle();
    expect(find.text('Projects to record'), findsOneWidget);
    expect(find.text('Import project'), findsOneWidget);
    expect(find.text('New project'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(OpenVoiceActorApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Projects to record'), findsOneWidget);
  });

  testWidgets('create a project and write a line', (tester) async {
    await setLargeWindow(tester);
    await tester.pumpWidget(OpenVoiceActorApp(services: services));
    expect(find.text('New project'), findsOneWidget);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My Game');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('My Game'), findsOneWidget);
    expect(find.text('Script'), findsOneWidget);

    await tester.tap(find.text('Add line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mira');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Line (en)'),
      'Who else knows?',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Who else knows?'), findsOneWidget);

    final saved = services.workspace.initiatorProjects().single;
    expect(saved.lineCount, 1);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Not recorded', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Mira'), findsOneWidget);
  });

  testWidgets('an actor opens a project and sees the recording screen', (
    tester,
  ) async {
    await setLargeWindow(tester);
    final package = '${dir.path}/game.ovaproject';
    final home = HomeController(services.workspace);
    await tester.runAsync(() async {
      final project = home.createProject(title: 'Game', sourceLanguage: 'en');
      final initiator = InitiatorController(services.workspace, project.id);
      final mira = initiator.addCharacter('Mira', description: 'A doctor.');
      final scene = initiator.addScene('Clinic', context: 'Night. Rain.');
      initiator.addLine(
        characterId: mira.id,
        sceneId: scene.id,
        text: 'Who else knows?',
        direction: 'Quietly.',
      );
      await initiator.exportPackage(package);
      await home.importProject(package);
    });

    await tester.pumpWidget(OpenVoiceActorApp(services: services));
    await tester.tap(find.text('Voice actor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Night. Rain.'), findsOneWidget);
    expect(find.text('Quietly.'), findsOneWidget);
    expect(find.text('Test mic'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.textContaining('24-bit · 48 kHz'), findsOneWidget);

    await tester.tap(find.text('Export takes'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Nothing to export'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    // Leave the screen so the meter timer stops before the test ends.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  });
}
