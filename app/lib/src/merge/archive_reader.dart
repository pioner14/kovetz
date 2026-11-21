// Reading one untrusted `.jwlibrary` archive into a normalized working copy.
part of '../../merge.dart';

const _coreTables = [
  'Location',
  'UserMark',
  'Tag',
  'Note',
  'Bookmark',
  'BlockRange',
  'InputField',
  'TagMap',
];
const _legacyTables = ['PlaylistMedia', 'PlaylistItem', 'PlaylistItemChild'];
const _playlistTables = [
  'IndependentMedia',
  'PlaylistItemAccuracy',
  'PlaylistItem',
  'PlaylistItemLocationMap',
  'PlaylistItemIndependentMediaMap',
  'PlaylistItemMarker',
  'PlaylistItemMarkerBibleVerseMap',
  'PlaylistItemMarkerParagraphMap',
];
const _metadataTables = {'LastModified', 'android_metadata', 'grdb_migrations'};

class _Source {
  _Source({
    required this.name,
    required this.inputPath,
    required this.manifest,
    required this.info,
    required this.db,
    required this.media,
    required this.modified,
    required this.fingerprint,
    required this.archive,
    required this.migrationIssues,
    required this.previousReport,
    required this.grdbMigrations,
    required this.locale,
  });

  final String name;
  final String inputPath;
  final Map<String, dynamic> manifest;
  final Map<String, dynamic> info;
  final Database db;
  final Map<String, File> media;
  final DateTime modified;
  final String fingerprint;
  final File archive;
  final List<Map<String, Object?>> migrationIssues;
  final Map<String, dynamic>? previousReport;

  /// Migrations recorded by a GRDB-based JW Library, or null for older apps.
  final List<String>? grdbMigrations;

  /// Locale stored by the app in android_metadata, if any.
  final String? locale;

  /// Location rows by ID, for report context. Normalization is complete when
  /// a source is created and later repairs never change Location.
  late final Map<Object?, Map<String, Object?>> locations = {
    for (final row in streamRows(db, 'SELECT * FROM Location'))
      row['LocationId']: row,
  };
}

Future<_Source> _readSource(
  String path,
  Directory folder,
  ArchiveLimits limits,
) async {
  final name = p.basename(path);
  folder.createSync();
  Database? db;
  try {
    final archiveCopy = await File(path)
        .copy(p.join(folder.path, 'source.jwlibrary'));
    final fingerprint = await _digest(archiveCopy);
    final input = InputFileStream(archiveCopy.path);
    late Map<String, dynamic> manifest;
    late Map<String, dynamic> info;
    late String databaseName;
    late int version;
    final extractedMedia = <String, File>{};
    final dbFile = File(p.join(folder.path, 'input.db'));
    Map<String, dynamic>? previousReport;
    try {
      final entries = <String, ArchiveFile>{};
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input, verify: true);
      final names = decoder.directory.fileHeaders.map(
        (header) => header.filename,
      );
      if (names.toSet().length != names.length) {
        throw MergeFailure(MergeErrorCode.invalidArchive, name);
      }
      for (final entry in archive.files) {
        if (!entry.isFile && !entry.isSymbolicLink) continue;
        if (entry.isSymbolicLink || !_safePath(entry.name)) {
          throw MergeFailure(MergeErrorCode.invalidArchive, name);
        }
        entries[entry.name] = entry;
      }
      // Check the declared budget before anything is written to disk.
      if (entries.length > limits.maxEntries) {
        throw MergeFailure(MergeErrorCode.tooLarge, name);
      }
      var declared = 0;
      for (final entry in entries.values) {
        if (entry.size < 0 || entry.size > limits.maxEntryBytes) {
          throw MergeFailure(MergeErrorCode.tooLarge, name);
        }
        declared += entry.size;
      }
      if (declared > limits.maxTotalBytes) {
        throw MergeFailure(MergeErrorCode.tooLarge, name);
      }
      final manifestEntry = entries.remove('manifest.json');
      if (manifestEntry == null) {
        throw MergeFailure(MergeErrorCode.invalidArchive, name);
      }
      if (manifestEntry.size > limits.maxManifestBytes) {
        throw MergeFailure(MergeErrorCode.tooLarge, name);
      }
      manifest = _readJson(
        manifestEntry,
        File(p.join(folder.path, 'manifest.json')),
      );
      info = manifest['userDataBackup'] as Map<String, dynamic>;
      databaseName = info['databaseName'] as String;
      final schema = info['schemaVersion'];
      if (!supportedSchemaVersions.contains(schema)) {
        throw MergeFailure.unsupportedSchema(
          name,
          schema is int ? schema : null,
        );
      }
      version = schema as int;
      if (!_safePath(databaseName)) {
        throw MergeFailure(MergeErrorCode.invalidArchive, name);
      }
      final dbEntry = entries.remove(databaseName);
      if (dbEntry == null) {
        throw MergeFailure(MergeErrorCode.invalidArchive, name);
      }
      _extract(dbEntry, dbFile);
      final dbDigest = await _digest(dbFile);
      if (dbDigest != (info['hash'] as String).toLowerCase()) {
        throw MergeFailure(MergeErrorCode.badHash, name);
      }
      final wal = entries.remove('$databaseName-wal');
      if (wal != null && wal.size > 0) {
        final walFile = File('${dbFile.path}-wal');
        _extract(wal, walFile);
      }
      // SQLite rebuilds the shared-memory index from the WAL.
      entries.remove('$databaseName-shm');
      // A rollback journal is SQLite bookkeeping, not media. Older apps
      // leave an empty one in backups; it must not reach the merged archive.
      entries.remove('$databaseName-journal');
      final prior = entries.remove('recovery-report.json');
      if (prior != null) {
        if (prior.size > limits.maxReportBytes) {
          throw MergeFailure(MergeErrorCode.tooLarge, name);
        }
        try {
          previousReport = _readJson(
            prior,
            File(p.join(folder.path, 'recovery-report.json')),
          );
        } on FormatException {
          throw MergeFailure(MergeErrorCode.invalidReport, name);
        }
        if (!{1, 2}.contains(previousReport['formatVersion'])) {
          throw MergeFailure(MergeErrorCode.invalidReport, name);
        }
      }
      for (final (index, entry) in entries.entries.indexed) {
        // Results of versions up to 0.4.2 embedded source copies. They are
        // not JW Library media and are no longer carried over.
        if (entry.key.startsWith('recovery-sources/')) continue;
        final file = File(p.join(folder.path, 'media-$index'));
        _extract(entry.value, file);
        extractedMedia[entry.key] = file;
      }
    } finally {
      input.closeSync();
    }

    db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    db.execute('PRAGMA trusted_schema = OFF');
    try {
      validateSourceSchema(db, version);
    } on SchemaFailure catch (error) {
      throw MergeFailure.unsupportedSchema(
        name,
        version,
        schemaTable: error.table,
      );
    }
    if (db.select('PRAGMA integrity_check(1)').first.values.single != 'ok') {
      throw MergeFailure(MergeErrorCode.invalidDatabase, name);
    }
    final tables = db
        .select(
          "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row['name'] as String)
        .toSet();
    final expected = {
      ..._coreTables.where((table) => version >= 8 || table != 'InputField'),
      if (version == 8) ..._legacyTables,
      if (version >= 14) ..._playlistTables,
      'LastModified',
    };
    if (!tables.containsAll(expected) ||
        tables.difference(expected).difference(_metadataTables).isNotEmpty) {
      throw MergeFailure.unsupportedSchema(name, version);
    }
    // Which JW Library wrote the backup decides the schema of a merge based
    // on it: GRDB-based apps record their applied migrations.
    final grdbMigrations = tables.contains('grdb_migrations')
        ? db
              .select('SELECT identifier FROM grdb_migrations ORDER BY rowid')
              .map((row) => row['identifier'])
              .whereType<String>()
              .toList()
        : null;
    final locale = tables.contains('android_metadata')
        ? db.select('SELECT locale FROM android_metadata LIMIT 1').firstOrNull
        : null;

    // Never modify the source schema: even ordinary SQL triggers in a v16
    // backup could change unrelated records during recovery. Copy values into
    // our own tables and install only the bundled maintenance triggers.
    late List<Map<String, Object?>> migrationIssues;
    try {
      final normalized = normalizeSchema(
        db,
        version,
        p.join(folder.path, 'normalized.db'),
      );
      db.close();
      db = normalized.db;
      migrationIssues = normalized.issues;
    } on SchemaFailure catch (error) {
      if (error.code == 'unsupportedSchema') {
        throw MergeFailure.unsupportedSchema(
          name,
          version,
          schemaTable: error.table,
        );
      }
      throw MergeFailure(
        error.code == 'unsupportedSchema'
            ? MergeErrorCode.unsupportedSchema
            : MergeErrorCode.invalidDatabase,
        name,
      );
    }

    final timestamp =
        _timestamp(info['lastModifiedDate']) ??
        _timestamp(manifest['creationDate']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return _Source(
      name: name,
      inputPath: path,
      manifest: manifest,
      info: info,
      db: db,
      media: extractedMedia,
      modified: timestamp,
      fingerprint: fingerprint,
      archive: archiveCopy,
      migrationIssues: migrationIssues,
      previousReport: previousReport,
      grdbMigrations: grdbMigrations,
      locale: locale?['locale'] as String?,
    );
  } on Object catch (error) {
    db?.close();
    if (error is MergeFailure) rethrow;
    if (error is SqliteException) {
      throw MergeFailure(MergeErrorCode.invalidDatabase, name);
    }
    // Missing, unreadable or full storage is not a damaged backup.
    if (error is FileSystemException) {
      throw MergeFailure(MergeErrorCode.io, name);
    }
    // Malformed ZIP, JSON or manifest fields surface as these types.
    if (error is FormatException ||
        error is TypeError ||
        error is RangeError ||
        error is StateError) {
      throw MergeFailure(MergeErrorCode.invalidArchive, name);
    }
    throw MergeFailure.internal('${error.runtimeType} (reading)');
  }
}

bool _safePath(String path) =>
    !path.contains('\\') &&
    !path.contains(':') &&
    !path.contains('\u0000') &&
    path
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

/// Extracts [entry], refusing to write more bytes than its declared size. The
/// declared sizes were already checked against the archive budget.
void _extract(ArchiveFile entry, File file) {
  final out = OutputFileStream(file.path);
  try {
    entry.writeContent(LimitedOutputStream(out, entry.size));
  } on ArchiveLimitExceeded {
    throw const FormatException('Archive entry exceeds its declared size');
  } finally {
    out.closeSync();
  }
  if (file.lengthSync() != entry.size) {
    throw const FormatException('Invalid archive entry size');
  }
}

/// Reads a JSON object from a bounded entry without holding the compressed
/// and decompressed copies in memory at once.
Map<String, dynamic> _readJson(ArchiveFile entry, File file) {
  _extract(entry, file);
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

DateTime? _timestamp(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.isUtc) return parsed;
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

void _checkDatabase(Database db, [String? fileName]) {
  if (db.select('PRAGMA integrity_check(1)').first.values.single != 'ok') {
    throw MergeFailure(MergeErrorCode.invalidDatabase, fileName);
  }
  final failures = db.select('PRAGMA foreign_key_check');
  if (failures.isNotEmpty) {
    throw MergeFailure.brokenReferences(fileName, failures.length);
  }
}
