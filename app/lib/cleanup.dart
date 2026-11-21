import 'dart:io';

import 'package:path/path.dart' as path;

/// Prefixes of the temporary folders a merge creates. They hold copies of
/// personal backups and are normally removed when the merge or app ends.
const temporaryPrefixes = ['kovetz-work-', 'kovetz-result-'];

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Removes copies of personal data left behind by an interrupted run.
///
/// Merge folders in [temporary] are removed once older than [maxAge], so a
/// merge running in another window of the app is never touched. On Android
/// the file picker copies every chosen backup into `cache/<uuid>/` and never
/// removes it; at start-up nothing is selected yet, so [pickerCache] copies
/// are all stale.
Future<int> removeStaleTemporaryFiles({
  required Directory temporary,
  Directory? pickerCache,
  Duration maxAge = const Duration(hours: 12),
  DateTime? now,
}) async {
  final limit = (now ?? DateTime.now()).subtract(maxAge);
  var removed = 0;
  Future<void> remove(Directory directory) async {
    try {
      await directory.delete(recursive: true);
      removed++;
    } on FileSystemException {
      // Another process may still use it, or it is already gone.
    }
  }

  Future<List<Directory>> folders(Directory parent) async {
    try {
      final entries = await parent.list(followLinks: false).toList();
      return entries.whereType<Directory>().toList();
    } on FileSystemException {
      return const [];
    }
  }

  for (final folder in await folders(temporary)) {
    final name = path.basename(folder.path);
    if (!temporaryPrefixes.any(name.startsWith)) continue;
    try {
      if ((await folder.stat()).modified.isBefore(limit)) await remove(folder);
    } on FileSystemException {
      continue;
    }
  }
  if (pickerCache != null) {
    for (final folder in await folders(pickerCache)) {
      if (_uuid.hasMatch(path.basename(folder.path))) await remove(folder);
    }
  }
  return removed;
}
