// Reading personal notes for export, through the same validated archive
// reading and schema normalization as a merge.
part of '../../merge.dart';

/// Reads the notes of one `.jwlibrary` backup (any supported schema) in a
/// background isolate. The input file is only read.
Future<NotesCollection> readBackupNotes(
  String path, {
  String languageCode = 'ru',
  ArchiveLimits limits = const ArchiveLimits(),
}) => Isolate.run(() async {
  final work = await Directory.systemTemp.createTemp('kovetz-work-');
  _Source? source;
  try {
    source = await _readSource(path, Directory(p.join(work.path, '0')), limits);
    return extractNotes(
      source.db,
      backupName: source.name,
      russian: languageCode == 'ru',
    );
  } on Object catch (error) {
    if (error is MergeFailure) rethrow;
    if (error is SqliteException) {
      throw MergeFailure(MergeErrorCode.invalidDatabase, p.basename(path));
    }
    if (error is FileSystemException) {
      throw MergeFailure(MergeErrorCode.io, p.basename(path));
    }
    throw MergeFailure.internal('${error.runtimeType} (notes)');
  } finally {
    source?.db.close();
    try {
      await work.delete(recursive: true);
    } on FileSystemException {
      // Removed on the next start of the app.
    }
  }
});
