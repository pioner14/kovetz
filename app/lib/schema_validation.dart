import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema_contracts.dart';
import 'src/sqlite_utils.dart';

class SchemaContractFailure implements Exception {
  const SchemaContractFailure(this.table);
  final String table;
}

/// Matches reviewed structural contracts, independently of table contents.
/// Input SQL is only tokenized; none of it is executed by this validator.
void validateSchemaContract(Database db, int version) {
  if (db.select('PRAGMA user_version').single.values.single != version) {
    throw const SchemaContractFailure('user_version');
  }
  final contracts = knownSchemaContracts[version];
  if (contracts == null) throw const SchemaContractFailure('version');
  for (final entry in contracts.entries) {
    final definition = db.select(
      "SELECT sql FROM sqlite_schema WHERE type='table' AND name = ?",
      [entry.key],
    );
    if (definition.isEmpty || definition.single['sql'] == null) {
      throw SchemaContractFailure(entry.key);
    }
    final shape = _shape(db, entry.key, definition.single['sql'] as String);
    final digest = sha256.convert(utf8.encode(_canonical(shape))).toString();
    if (!entry.value.contains(digest)) throw SchemaContractFailure(entry.key);
  }
}

String _affinity(String value) {
  final type = value.toUpperCase();
  if (type.contains('INT')) return 'INTEGER';
  if (['CHAR', 'CLOB', 'TEXT'].any(type.contains)) return 'TEXT';
  if (type.isEmpty || type.contains('BLOB')) return 'BLOB';
  if (['REAL', 'FLOA', 'DOUB'].any(type.contains)) return 'REAL';
  return 'NUMERIC';
}

String _canonical(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(v[k])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

final _sqlToken = RegExp(
  r'''--[^\r\n]*|/\*[\s\S]*?\*/|'(?:''|[^'])*'|"(?:""|[^"])*"|`(?:``|[^`])*`|\[(?:\]\]|[^\]])*\]|[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?|<>|!=|<=|>=|==|\S''',
);
List<String> _tokens(String sql) => [
  for (final match in _sqlToken.allMatches(sql))
    if (!match[0]!.startsWith('--') && !match[0]!.startsWith('/*'))
      _normalizeToken(match[0]!),
];
String _normalizeToken(String token) {
  if (token.startsWith("'")) return token;
  if ('"`['.contains(token[0])) {
    final last = token[token.length - 1];
    return token
        .substring(1, token.length - 1)
        .replaceAll('$last$last', last)
        .toLowerCase();
  }
  return token.toLowerCase();
}

Map<String, Object?> _shape(Database db, String table, String sql) {
  final columns = [
    for (final row in db.select(
      'PRAGMA table_xinfo(${quoteIdentifier(table)})',
    ))
      [
        (row['name'] as String).toLowerCase(),
        _affinity(row['type'] as String),
        row['notnull'],
        row['pk'],
        row['hidden'],
      ],
  ]..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  final foreign = [
    for (final row in db.select(
      'PRAGMA foreign_key_list(${quoteIdentifier(table)})',
    ))
      [
        (row['from'] as String).toLowerCase(),
        (row['table'] as String).toLowerCase(),
        (row['to'] as String? ?? '').toLowerCase(),
      ],
  ]..sort((a, b) => _canonical(a).compareTo(_canonical(b)));
  final unique = <List<Object?>>[];
  for (final index in db.select(
    'PRAGMA index_list(${quoteIdentifier(table)})',
  )) {
    if (index['unique'] != 1) continue;
    final keys = [
      for (final row in db.select(
        'PRAGMA index_xinfo(${quoteIdentifier(index['name'] as String)})',
      ))
        if (row['key'] == 1)
          [
            (row['name'] as String?)?.toLowerCase(),
            (row['coll'] as String? ?? '').toLowerCase(),
          ],
    ];
    List<String> expression = [];
    if (keys.any((k) => k[0] == null)) {
      final text =
          db.select('SELECT sql FROM sqlite_schema WHERE name = ?', [
                index['name'],
              ]).single['sql']
              as String;
      final tokens = _tokens(text);
      expression = tokens.sublist(tokens.indexOf('on') + 1);
    }
    unique.add([index['partial'], keys, expression]);
  }
  unique.sort((a, b) => _canonical(a).compareTo(_canonical(b)));
  final tokens = _tokens(sql);
  final checks = <String>[];
  for (var i = 0; i < tokens.length - 1; i++) {
    if (tokens[i] != 'check' || tokens[i + 1] != '(') continue;
    var depth = 0;
    for (var j = i + 1; j < tokens.length; j++) {
      if (tokens[j] == '(') depth++;
      if (tokens[j] == ')') depth--;
      if (depth == 0) {
        checks.add(tokens.sublist(i + 1, j + 1).join(' '));
        break;
      }
    }
  }
  checks.sort();
  return {
    'columns': columns,
    'foreignKeys': foreign,
    'unique': unique,
    'checks': checks,
  };
}
