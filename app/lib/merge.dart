import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'archive_limits.dart';
import 'schema.dart';
import 'src/notes/notes_model.dart';
import 'src/sqlite_utils.dart';

export 'archive_limits.dart' show ArchiveLimits;
export 'src/notes/notes_model.dart'
    show BackupNote, NoteSource, NoteSourceKind, NotesCollection;

part 'src/merge/archive_reader.dart';
part 'src/merge/merger.dart';
part 'src/merge/notes_reader.dart';
part 'src/merge/recovery.dart';
part 'src/merge/recovery_report.dart';
part 'src/merge/report_text.dart';

enum NoteConflictPolicy { newest, primary }

enum FieldConflictPolicy { primary, newestBackup }

class MergeOptions {
  const MergeOptions({
    this.primaryPath,
    this.notePolicy = NoteConflictPolicy.newest,
    this.fieldPolicy = FieldConflictPolicy.primary,
    this.languageCode = 'ru',
    this.limits = const ArchiveLimits(),
  });
  final String? primaryPath;
  final NoteConflictPolicy notePolicy;
  final FieldConflictPolicy fieldPolicy;
  final String languageCode;
  final ArchiveLimits limits;
}

class MergeResult {
  const MergeResult({
    required this.archivePath,
    required this.reportPath,
    this.recoveryReportPath,
    required this.primaryFileName,
    required this.options,
    required this.counts,
    required this.noteConflicts,
    required this.bookmarkConflicts,
    required this.skippedBookmarks,
    required this.fieldConflicts,
    required this.warnings,
  });

  final String archivePath;
  final String reportPath;

  /// Machine-readable details, beside the archive and never inside it; null
  /// when there is nothing to report. Not offered for saving.
  final String? recoveryReportPath;
  final String primaryFileName;
  final MergeOptions options;
  final Map<String, int> counts;
  final int noteConflicts;
  final int bookmarkConflicts;
  final int skippedBookmarks;
  final int fieldConflicts;
  final List<MergeWarning> warnings;
}

class MergeWarning {
  const MergeWarning(this.code, {this.fileName, this.count = 1});

  final String code;
  final String? fileName;
  final int count;

  Map<String, Object?> toJson() => {
    'code': code,
    'fileName': fileName,
    'count': count,
  };
}

/// Why a merge stopped. The UI maps each value to a message, so adding a
/// value is a compile error until it is described there.
enum MergeErrorCode {
  tooFew,
  invalidPrimary,
  invalidArchive,
  invalidDatabase,
  invalidReport,
  unsupportedSchema,
  brokenReferences,
  badHash,
  missingMedia,
  tooLarge,
  io,
  cancelled,
  internal,
}

class MergeFailure implements Exception {
  const MergeFailure(this.kind, [this.fileName])
    : schemaVersion = null,
      schemaTable = null,
      brokenReferences = null,
      detail = null;

  /// An unexpected failure. [detail] names the exception type and the merge
  /// stage only, never file contents or paths, so it is safe to show.
  const MergeFailure.internal(this.detail)
    : kind = MergeErrorCode.internal,
      fileName = null,
      schemaVersion = null,
      schemaTable = null,
      brokenReferences = null;

  const MergeFailure.unsupportedSchema(
    this.fileName,
    this.schemaVersion, {
    this.schemaTable,
  }) : kind = MergeErrorCode.unsupportedSchema,
       brokenReferences = null,
       detail = null;

  const MergeFailure.brokenReferences(this.fileName, this.brokenReferences)
    : kind = MergeErrorCode.brokenReferences,
      schemaTable = null,
      schemaVersion = null,
      detail = null;

  final MergeErrorCode kind;
  final String? fileName;
  final int? schemaVersion;
  final String? schemaTable;
  final int? brokenReferences;
  final String? detail;

  /// Stable name of [kind], used in tests and reports.
  String get code => kind.name;

  @override
  String toString() => [code, ?fileName, ?detail].join(': ');
}

/// Merges [inputPaths] in a background isolate.
///
/// When [cancel] completes, the worker is stopped, its temporary copies are
/// removed and the future fails with [MergeErrorCode.cancelled].
Future<MergeResult> mergeArchives(
  List<String> inputPaths,
  void Function(String) onStage, {
  MergeOptions options = const MergeOptions(),
  Future<void>? cancel,
}) async {
  if (inputPaths.length < 2) throw const MergeFailure(MergeErrorCode.tooFew);
  final progress = ReceivePort();
  progress.listen((message) => onStage(message as String));
  // Folders are created here, not in the worker, so they can be removed even
  // if the worker is stopped part-way through.
  final work = await Directory.systemTemp.createTemp('kovetz-work-');
  final output = await Directory.systemTemp.createTemp('kovetz-result-');
  final replies = ReceivePort();
  final exited = Completer<void>();
  final result = Completer<MergeResult>();
  var succeeded = false;
  replies.listen((message) {
    switch (message) {
      case MergeResult():
        if (!result.isCompleted) result.complete(message);
      case MergeFailure():
        if (!result.isCompleted) result.completeError(message);
      case List():
        // Uncaught error reported by the isolate: [error, stack].
        if (!result.isCompleted) {
          result.completeError(
            MergeFailure.internal('worker (${message.first})'),
          );
        }
      case null:
        exited.complete();
        if (!result.isCompleted) {
          result.completeError(const MergeFailure.internal('worker exited'));
        }
    }
  });
  try {
    final isolate = await Isolate.spawn(
      _runWorker,
      _Job(
        inputPaths,
        progress.sendPort,
        replies.sendPort,
        options,
        work.path,
        output.path,
      ),
      onError: replies.sendPort,
      onExit: replies.sendPort,
    );
    unawaited(
      cancel?.then((_) {
        if (result.isCompleted) return;
        isolate.kill(priority: Isolate.immediate);
        result.completeError(const MergeFailure(MergeErrorCode.cancelled));
      }),
    );
    final merged = await result.future;
    succeeded = true;
    return merged;
  } finally {
    // Wait briefly for the worker to stop so its files are closed.
    await exited.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    replies.close();
    progress.close();
    await _deleteQuietly(work);
    if (!succeeded) await _deleteQuietly(output);
  }
}

Future<void> _deleteQuietly(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // Leftovers are removed on the next start of the app.
  }
}

/// Everything the worker isolate needs; sent by value.
class _Job {
  const _Job(
    this.paths,
    this.progress,
    this.replies,
    this.options,
    this.workPath,
    this.outputPath,
  );

  final List<String> paths;
  final SendPort progress;
  final SendPort replies;
  final MergeOptions options;
  final String workPath;
  final String outputPath;
}

Future<void> _runWorker(_Job job) async {
  try {
    job.replies.send(
      await _merge(
        job.paths,
        job.progress,
        job.options,
        Directory(job.workPath),
        Directory(job.outputPath),
      ),
    );
  } on MergeFailure catch (failure) {
    job.replies.send(failure);
  }
}

Future<MergeResult> _merge(
  List<String> paths,
  SendPort progress,
  MergeOptions options,
  Directory work,
  Directory output,
) async {
  final sources = <_Source>[];
  _RecoveryReport? report;
  var stage = 'reading';
  void enter(String next) {
    stage = next;
    progress.send(next);
  }

  try {
    enter('reading');
    for (final (index, path) in paths.indexed) {
      final source = await _readSource(
        path,
        Directory(p.join(work.path, '$index')),
        options.limits,
      );
      final duplicate = sources.indexWhere(
        (s) => s.fingerprint == source.fingerprint,
      );
      if (duplicate < 0) {
        sources.add(source);
      } else if (options.primaryPath != null &&
          p.equals(p.absolute(path), p.absolute(options.primaryPath!))) {
        sources[duplicate].db.close();
        sources[duplicate] = source;
      } else {
        source.db.close();
      }
    }
    sources.sort((a, b) {
      final date = b.modified.compareTo(a.modified);
      return date == 0 ? a.fingerprint.compareTo(b.fingerprint) : date;
    });
    if (options.primaryPath != null) {
      final index = sources.indexWhere(
        (s) =>
            p.equals(p.absolute(s.inputPath), p.absolute(options.primaryPath!)),
      );
      if (index < 0) throw const MergeFailure(MergeErrorCode.invalidPrimary);
      sources.insert(0, sources.removeAt(index));
    }
    final template = sources.first;
    report = _RecoveryReport(p.join(work.path, 'report.db'));
    report.primaryName = template.name;
    report.options = options;
    report.sourceNames = sources.map((s) => s.name).toList();
    for (final source in sources) {
      try {
        report.inherit(source);
      } on Object catch (error) {
        // A previous result's report with unexpected field types must not be
        // shown to the user as a storage or permission problem.
        if (error is MergeFailure || error is SqliteException) rethrow;
        throw MergeFailure(MergeErrorCode.invalidReport, source.name);
      }
      for (final issue in source.migrationIssues) {
        report.retain(
          source,
          issue['table'] as String,
          issue['code'] as String,
          Map<String, Object?>.from(issue['record'] as Map),
        );
      }
    }
    final digests = <String, String>{};
    await _recoverMedia(sources, report, digests);
    for (final source in sources) {
      _sanitizeReferences(source, report);
    }
    final dbFile = File(p.join(work.path, 'merged.db'));
    final db = sqlite3.open(dbFile.path);
    // A device restores only the schema its app expects. Apps move from the
    // older v16 schema to the GRDB one, so any GRDB-based input selects it.
    for (final source in sources) {
      final migrations = source.grdbMigrations;
      if (migrations != null && !_sameList(migrations, knownGrdbMigrations)) {
        db.close();
        throw MergeFailure.unsupportedSchema(
          source.name,
          currentSchemaVersion,
          schemaTable: 'grdb_migrations',
        );
      }
    }
    final grdb = sources.any((source) => source.grdbMigrations != null)
        ? knownGrdbMigrations
        : null;
    final variant = grdb == null ? OutputSchema.legacy : OutputSchema.grdb;
    createOutputSchema(db, variant, locale: template.locale);
    final merger = _Merger(db, report, options);
    final media = _Media(digests);
    final now = DateTime.now().toUtc();
    late Map<String, int> counts;
    try {
      db.execute('PRAGMA trusted_schema = OFF');
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('BEGIN IMMEDIATE');
      db.execute('PRAGMA defer_foreign_keys = ON');
      merger.readAccuracy();
      enter('merging');
      for (final source in sources) {
        try {
          merger.add(source, await media.add(source));
        } on SqliteException {
          throw MergeFailure(MergeErrorCode.invalidDatabase, source.name);
        }
      }
      merger.writeBookmarks();
      db.execute('UPDATE LastModified SET LastModified = ?', [
        formatJwTimestamp(now),
      ]);
      enter('checking');
      _checkDatabase(db);
      db.execute('COMMIT');
      installOutputTriggers(db, variant);
      counts = merger.counts;
    } finally {
      merger.dispose();
      db.close();
    }

    enter('packing');
    final manifest = Map<String, dynamic>.of(template.manifest);
    final info = Map<String, dynamic>.of(template.info);
    final date = formatJwTimestamp(now);
    final archiveName =
        'Merged-${date.substring(0, 19).replaceAll(':', '-')}.jwlibrary';
    // JW Library names a backup after its file and writes whole seconds.
    manifest['name'] = archiveName;
    manifest['creationDate'] = date.substring(0, 10);
    info['databaseName'] = 'userData.db';
    info['schemaVersion'] = currentSchemaVersion;
    info['lastModifiedDate'] = date;
    info['hash'] = await _digest(dbFile);
    info['deviceName'] = 'Kovetz';
    if (info.containsKey('userMarkCount')) {
      info['userMarkCount'] = counts['UserMark'] ?? 0;
    }
    manifest['userDataBackup'] = info;
    final manifestFile = File(p.join(work.path, 'manifest.json'))
      ..writeAsStringSync(jsonEncode(manifest));
    final archivePath = p.join(output.path, archiveName);
    final encoder = ZipFileEncoder()..create(archivePath);
    try {
      await encoder.addFile(dbFile, 'userData.db');
      await encoder.addFile(manifestFile, 'manifest.json');
      for (final entry in media.files.entries) {
        await encoder.addFile(entry.value, entry.key);
      }
    } finally {
      await encoder.close();
    }

    // JW Library rejects a backup that carries any extra file ("saved data is
    // damaged", confirmed on a device 2026-11-21), so the machine report
    // stays outside the archive and source copies are never embedded.
    String? recoveryReportPath;
    if (report.hasDetails) {
      recoveryReportPath = p.setExtension(archivePath, '.recovery.json');
      report.writeJson(File(recoveryReportPath));
    }
    final reportPath = p.setExtension(archivePath, '.report.txt');
    report.writeText(File(reportPath), counts, merger);
    return MergeResult(
      reportPath: reportPath,
      recoveryReportPath: recoveryReportPath,
      primaryFileName: template.name,
      options: options,
      archivePath: archivePath,
      counts: counts,
      noteConflicts: merger.noteConflicts,
      bookmarkConflicts: merger.bookmarkConflicts,
      skippedBookmarks: merger.skippedBookmarks,
      fieldConflicts: merger.fieldConflicts,
      warnings: report.warnings,
    );
  } on Object catch (error) {
    if (error is MergeFailure) rethrow;
    if (error is SqliteException) {
      throw const MergeFailure(MergeErrorCode.invalidDatabase);
    }
    if (error is FileSystemException) {
      throw const MergeFailure(MergeErrorCode.io);
    }
    throw MergeFailure.internal('${error.runtimeType} ($stage)');
  } finally {
    for (final source in sources) {
      source.db.close();
    }
    report?.close();
  }
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
