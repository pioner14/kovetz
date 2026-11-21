import 'package:sqlite3/sqlite3.dart';

/// Quotes an SQL identifier (table or column name) for SQLite.
String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Streams rows one at a time instead of materialising the whole result.
/// Each row is a mutable copy that callers may change freely.
Iterable<Map<String, Object?>> streamRows(
  Database db,
  String sql, [
  List<Object?> parameters = const [],
]) sync* {
  final statement = db.prepare(sql);
  try {
    final cursor = statement.selectCursor(parameters);
    while (cursor.moveNext()) {
      yield Map<String, Object?>.of(cursor.current);
    }
  } finally {
    statement.close();
  }
}

/// Inserts [row] into [table] with bound values and returns the new rowid.
int insertRow(Database db, String table, Map<String, Object?> row) {
  final columns = row.keys.map(quoteIdentifier).join(', ');
  final parameters = List.filled(row.length, '?').join(', ');
  db.execute(
    'INSERT INTO ${quoteIdentifier(table)} ($columns) VALUES ($parameters)',
    row.values.toList(),
  );
  return db.lastInsertRowId;
}

/// Reuses prepared statements for SQL that runs once per row. Preparing a
/// statement costs more than executing it for small inserts.
class StatementCache {
  StatementCache(this.db);

  final Database db;
  final _statements = <String, PreparedStatement>{};

  void execute(String sql, [List<Object?> parameters = const []]) =>
      _statements.putIfAbsent(sql, () => db.prepare(sql)).execute(parameters);

  /// Like [insertRow], reusing the statement for the same set of columns.
  int insert(String table, Map<String, Object?> row) {
    final columns = row.keys.map(quoteIdentifier).join(', ');
    final parameters = List.filled(row.length, '?').join(', ');
    execute(
      'INSERT INTO ${quoteIdentifier(table)} ($columns) VALUES ($parameters)',
      row.values.toList(),
    );
    return db.lastInsertRowId;
  }

  /// Closes every cached statement; call before closing [db].
  void dispose() {
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
  }
}
