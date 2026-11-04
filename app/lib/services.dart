import 'package:file_selector/file_selector.dart';
import 'package:ova_core/ova_core.dart';

/// Everything screens need from outside the app. Tests pass in stand-ins.
class AppServices {
  AppServices({
    required this.workspace,
    required this.createInput,
    required this.output,
    required this.freeSpace,
    required this.files,
  });

  final Workspace workspace;
  final AudioInput Function() createInput;
  final AudioOutput output;
  final FreeSpaceLookup freeSpace;
  final FilePicker files;
}

abstract interface class FilePicker {
  Future<String?> pickFile(String label, List<String> extensions);
  Future<String?> pickSaveLocation(
    String suggestedName,
    String label,
    String extension,
  );
  Future<String?> pickFolder();
}

class SystemFilePicker implements FilePicker {
  const SystemFilePicker();

  @override
  Future<String?> pickFile(String label, List<String> extensions) async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
    );
    return file?.path;
  }

  @override
  Future<String?> pickSaveLocation(
    String suggestedName,
    String label,
    String extension,
  ) async {
    final location = await getSaveLocation(
      suggestedName: '$suggestedName.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: [extension]),
      ],
    );
    final path = location?.path;
    if (path == null) return null;
    return path.toLowerCase().endsWith('.$extension')
        ? path
        : '$path.$extension';
  }

  @override
  Future<String?> pickFolder() => getDirectoryPath();
}
