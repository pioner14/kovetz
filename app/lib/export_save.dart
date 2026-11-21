import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'notes_export.dart';

const _channel = MethodChannel('dev.backupmerge/export');

/// Saves [bytes] to a file the person picks. Returns the saved path on
/// desktop, an empty string on Android (the system hides the location) and
/// null when the dialog was cancelled.
Future<String?> saveBytesWithDialog({
  required Uint8List bytes,
  required String fileName,
  required String label,
  required String extension,
}) async {
  if (Platform.isAndroid) {
    // The system dialog copies from a file, so stage one in a private folder.
    final folder = await Directory.systemTemp.createTemp('kovetz-result-');
    try {
      final file = File(path.join(folder.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      final saved = await _channel.invokeMethod<Object?>('save', {
        'path': file.path,
      });
      return saved == true ? '' : null;
    } finally {
      try {
        await folder.delete(recursive: true);
      } on FileSystemException {
        // Removed on the next start of the app.
      }
    }
  }
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: [extension]),
    ],
  );
  if (location == null) return null;
  final target = path.extension(location.path).toLowerCase() == '.$extension'
      ? location.path
      : '${location.path}.$extension';
  await File(target).writeAsBytes(bytes, flush: true);
  return target;
}

/// Writes the Markdown export into a new folder inside the folder the person
/// picks (desktop). Returns the new folder or null when cancelled. An existing
/// folder of the same name is never reused.
Future<String?> saveMarkdownFolder(
  Map<String, String> files,
  String folderName,
) async {
  final root = await getDirectoryPath();
  if (root == null) return null;
  var target = Directory(path.join(root, folderName));
  for (var n = 2; target.existsSync(); n++) {
    target = Directory(path.join(root, '$folderName ($n)'));
  }
  await writeMarkdownExport(files, target);
  return target.path;
}
