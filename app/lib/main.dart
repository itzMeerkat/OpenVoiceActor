import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ova_capture/windows_audio.dart';
import 'package:ova_core/ova_core.dart';

import 'services.dart';
import 'ui/design/theme.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dataRoot =
      Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
  final output = WindowsAudioOutput();
  runApp(
    OpenVoiceActorApp(
      services: AppServices(
        workspace: Workspace('$dataRoot\\OpenVoiceActor'),
        createInput: WindowsAudioInput.new,
        output: output,
        freeSpace: freeDiskBytes,
        files: const SystemFilePicker(),
      ),
    ),
  );
}

class OpenVoiceActorApp extends StatelessWidget {
  const OpenVoiceActorApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenVoiceActor',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(services: services),
    );
  }
}
