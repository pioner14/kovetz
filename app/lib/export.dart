import 'dart:io';

import 'package:path/path.dart' as path;

class ExportFailure implements Exception {
  const ExportFailure({this.recoveryDirectory});

  final String? recoveryDirectory;
}

/// Stage both outputs before replacing either destination. A failed replacement
/// restores the previous pair, retaining recovery files if restoration fails.
Future<void> saveBackupPair({
  required String archiveSource,
  required String reportSource,
  required String archiveDestination,
  required String reportDestination,
}) async {
  final destinations = [archiveDestination, reportDestination];
  final sources = [archiveSource, reportSource];
  Directory? staging;
  final originals = <int>{};
  final installed = <int>{};
  var retainStaging = false;
  try {
    staging = await File(archiveDestination).parent.createTemp('.kovetz-');
    for (var index = 0; index < sources.length; index++) {
      await File(sources[index]).copy(path.join(staging.path, 'new-$index'));
    }
    for (var index = 0; index < destinations.length; index++) {
      final destination = destinations[index];
      final type = await FileSystemEntity.type(destination, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        throw const FileSystemException('Destination is a directory');
      }
      if (type != FileSystemEntityType.notFound) {
        await File(destination)
            .rename(path.join(staging.path, 'original-$index'));
        originals.add(index);
      }
      await File(path.join(staging.path, 'new-$index')).rename(destination);
      installed.add(index);
    }
  } catch (_) {
    if (staging != null) {
      for (var index = destinations.length - 1; index >= 0; index--) {
        try {
          if (installed.contains(index)) {
            await File(destinations[index]).delete();
          }
          if (originals.contains(index)) {
            await File(path.join(staging.path, 'original-$index'))
                .rename(destinations[index]);
          }
        } catch (_) {
          retainStaging = true;
        }
      }
    }
    throw ExportFailure(
      recoveryDirectory: retainStaging ? staging?.path : null,
    );
  } finally {
    if (staging != null && !retainStaging) {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // A successful export is usable even if temporary cleanup is deferred.
      }
    }
  }
}

/// Whether saving to [destination] would overwrite one of [sources], either by
/// the same path or, when the destination already exists, the same file.
Future<bool> wouldReplaceSource(
  String destination,
  bool exists,
  Iterable<String> sources,
) async {
  final target = path.normalize(path.absolute(destination));
  for (final input in sources) {
    if (path.equals(target, path.normalize(path.absolute(input)))) {
      return true;
    }
    if (exists &&
        await File(input).exists() &&
        await FileSystemEntity.identical(destination, input)) {
      return true;
    }
  }
  return false;
}
