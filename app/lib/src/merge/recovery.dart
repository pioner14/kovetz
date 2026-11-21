// Repairing working copies before the merge: media and broken links.
part of '../../merge.dart';

/// Uses file contents, rather than another device's local database IDs.
Future<void> _recoverMedia(
  List<_Source> sources,
  _RecoveryReport report,
  Map<String, String> digests,
) async {
  final byHash = <String, File>{};
  for (final source in sources) {
    for (final file in source.media.values) {
      final digest = digests[file.path] ??= await _digest(file);
      byHash.putIfAbsent(digest, () => file);
    }
  }
  for (final source in sources) {
    source.db.execute('PRAGMA foreign_keys = OFF');
    for (final row in source.db.select('SELECT * FROM IndependentMedia')) {
      final path = row['FilePath'] as String;
      final expected = (row['Hash'] as String).toLowerCase();
      final present = source.media[path];
      if (present != null && digests[present.path] == expected) continue;
      final replacement = byHash[expected];
      if (replacement != null) {
        source.media[path] = replacement;
        report.warn(
          'recoveredMedia',
          source.name,
          eventId: _reportId(['media', source.fingerprint, path, expected]),
        );
      } else {
        report.retain(
          source,
          'IndependentMedia',
          'missingMedia',
          Map.of(row),
          code: 'missingMedia',
        );
        source.db.execute(
          'DELETE FROM IndependentMedia WHERE IndependentMediaId = ?',
          [row['IndependentMediaId']],
        );
      }
    }
  }
}

/// Sanitizes extracted working copies. Every affected row and the original
/// source archive remain in the output report so missing identities are explicit.
void _sanitizeReferences(_Source source, _RecoveryReport report) {
  final db = source.db;
  const order = [
    'Location',
    'Tag',
    'IndependentMedia',
    'PlaylistItemAccuracy',
    'UserMark',
    'Note',
    'PlaylistItem',
    'Bookmark',
    'BlockRange',
    'InputField',
    'PlaylistItemLocationMap',
    'PlaylistItemIndependentMediaMap',
    'PlaylistItemMarker',
    'PlaylistItemMarkerBibleVerseMap',
    'PlaylistItemMarkerParagraphMap',
    'TagMap',
  ];
  db.execute('PRAGMA foreign_keys = OFF');
  db.execute('BEGIN IMMEDIATE');
  try {
    for (final table in order) {
      final foreignKeys = db.select('PRAGMA foreign_key_list("$table")');
      if (foreignKeys.isEmpty) continue;
      final columns = db.select('PRAGMA table_info("$table")');
      final primary =
          columns.where((column) => (column['pk'] as int) > 0).toList()
            ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      for (final record in streamRows(db, 'SELECT * FROM "$table"')) {
        final missing = <String>[];
        for (final key in foreignKeys) {
          final from = key['from'] as String;
          final value = record[from];
          if (value == null) continue;
          final parent = key['table'] as String;
          final to = key['to'] as String;
          final exists = db.select(
            'SELECT 1 FROM ${quoteIdentifier(parent)} WHERE ${quoteIdentifier(to)} = ? LIMIT 1',
            [value],
          );
          if (exists.isEmpty) missing.add(from);
        }
        if (missing.isEmpty) continue;
        report.retain(
          source,
          table,
          'missingReference',
          Map.of(record),
          missingReferences: missing,
        );
        final filter = primary
            .map(
              (column) => '${quoteIdentifier(column['name'] as String)} IS ?',
            )
            .join(' AND ');
        final values = [for (final column in primary) record[column['name']]];
        final canDetach =
            table == 'Note' ||
            (table == 'PlaylistItem' &&
                missing.every((column) => column == 'ThumbnailFilePath'));
        if (canDetach) {
          final assignments = missing
              .map((column) => '${quoteIdentifier(column)} = NULL')
              .join(', ');
          db.execute(
            'UPDATE ${quoteIdentifier(table)} SET $assignments WHERE $filter',
            values,
          );
        } else {
          db.execute(
            'DELETE FROM ${quoteIdentifier(table)} WHERE $filter',
            values,
          );
        }
      }
    }
    if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw MergeFailure(MergeErrorCode.invalidDatabase, source.name);
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
