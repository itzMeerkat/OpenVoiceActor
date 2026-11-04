// Runs the real Windows app and native engine, driven through its screens, with
// a generated signal instead of a microphone. Nothing here touches real devices.
//
//   flutter test integration_test -d windows
//
// Set OVA_SCREENSHOT_DIR to save a picture of each main screen.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openvoiceactor/main.dart';
import 'package:openvoiceactor/services.dart';
import 'package:ova_capture/ova_capture.dart';
import 'package:ova_capture/windows_audio.dart';
import 'package:ova_core/ova_core.dart';

class ScriptedFiles implements FilePicker {
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // A tap that lands on something else means a control is covered on screen.
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('a project travels from initiator to actor and back', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ova_app_flow');
    final files = ScriptedFiles();
    final projectFile = '${dir.path}\\game.ovaproject';
    final submissionFile = '${dir.path}\\alex.ovasubmission';
    final shotDir = Platform.environment['OVA_SCREENSHOT_DIR'];

    final services = AppServices(
      workspace: Workspace('${dir.path}\\data'),
      createInput: () => SyntheticAudioInput(format: SampleFormat.s24),
      output: WindowsAudioOutput(),
      freeSpace: freeDiskBytes,
      files: files,
    );

    Future<void> pumpUntil(Finder finder) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isNotEmpty) return;
      }
      final onScreen = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .join(' | ');
      fail('Timed out waiting for $finder. On screen: $onScreen');
    }

    Future<void> tapText(String text) async {
      await pumpUntil(find.text(text));
      await tester.tap(find.text(text).last);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> shoot(String name) async {
      if (shotDir == null) return;
      await tester.pump(const Duration(milliseconds: 400));
      final boundary = tester.renderObject(
        find.byType(RepaintBoundary).first,
      ) as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir\\$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await tester.pumpWidget(OpenVoiceActorApp(services: services));

    // Initiator: create a project with a line, and export it.
    await tapText('New project');
    await tester.enterText(find.byType(TextField).first, 'Mountain Village');
    await tester.pump();
    await tapText('Create');
    await tapText('Add line');
    await tester.tap(find.text('New').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mira');
    await tester.tap(find.text('Add').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'The clinic',
    );
    await tester.tap(find.text('Add').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextField, 'Line (en)'),
      'Who else knows about this?',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Direction'),
      'Quietly, to herself.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await pumpUntil(find.text('Who else knows about this?'));
    await shoot('1_script');

    files.next = projectFile;
    await tapText('Export project');
    await pumpUntil(find.textContaining('Exported revision 1'));
    expect(File(projectFile).existsSync(), isTrue);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));

    // Actor: import it, record twice, keep a favorite, and export.
    await tapText('Voice actor');
    await tapText('Import project');
    await pumpUntil(find.text('Mountain Village'));
    await tapText('Mountain Village');
    await pumpUntil(find.text('Record'));
    expect(find.textContaining('24-bit · 48 kHz'), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Record'));
      await pumpUntil(find.text('Stop'));
      await tester.pump(const Duration(milliseconds: 600));
      if (i == 1) await shoot('2_recording');
      await tester.tap(find.text('Stop'));
      await pumpUntil(find.text('Record'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.star_border_rounded).first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    await shoot('3_takes');

    await tapText('Export takes');
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Alex');
    await tester.pump(const Duration(milliseconds: 200));
    await shoot('4_export');
    files.next = submissionFile;
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await pumpUntil(find.textContaining('Exported 1 take'));
    expect(File(submissionFile).existsSync(), isTrue);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 800));

    // Initiator: import the take, play it, and select it.
    await tapText('Project owner');
    await tapText('Mountain Village');
    await tapText('Review');
    await tapText('Import submission');
    await pumpUntil(find.text('Takes from Alex'));
    expect(find.textContaining('1 imported'), findsOneWidget);
    await tapText('OK');
    await pumpUntil(find.text('Select'));
    await tester.tap(find.text('Select'));
    await pumpUntil(find.text('Unselect'));
    expect(find.textContaining('Approved', findRichText: true), findsOneWidget);
    await shoot('5_review');

    final engineFolder = '${dir.path}\\engine';
    Directory(engineFolder).createSync();
    files.next = engineFolder;
    await tapText('Export selected takes for the game');
    await pumpUntil(find.textContaining('Copied 1 take'));
    final exported = Directory('$engineFolder\\en')
        .listSync()
        .whereType<File>()
        .single;
    final info = readWavInfo(exported.path);
    expect(info.bitDepth, 24, reason: 'Exactly what was captured');
    expect(info.sampleRateHz, 48000);
    expect(info.channels, 1);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    dir.deleteSync(recursive: true);
  });
}
