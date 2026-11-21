import 'dart:io';

import 'package:kovetz/merge.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('contracts-');
  });
  tearDown(() => scratch.delete(recursive: true));

  final mutations = <String, String Function(String)>{
    'missing current Created column': (sql) => sql.replaceAll(
      RegExp(
        r'\bCreated\s+TEXT\s+NOT NULL\s+DEFAULT\([^\n]*\),',
        caseSensitive: false,
      ),
      '',
    ),
    'wrong content affinity': (sql) => sql.replaceAll(
      RegExp(r'\bContent\s+TEXT\b', caseSensitive: false),
      'Content INTEGER',
    ),
    'missing GUID uniqueness': (sql) => sql.replaceAll(
      RegExp(r'\bGuid\s+TEXT\s+NOT NULL\s+UNIQUE', caseSensitive: false),
      'Guid TEXT NOT NULL',
    ),
    'missing GUID nullability constraint': (sql) => sql.replaceAll(
      RegExp(r'\bGuid\s+TEXT\s+NOT NULL', caseSensitive: false),
      'Guid TEXT',
    ),
    'missing primary key': (sql) => sql.replaceAll(
      RegExp(
        r'\bNoteId\s+INTEGER\s+NOT NULL\s+PRIMARY KEY',
        caseSensitive: false,
      ),
      'NoteId INTEGER NOT NULL',
    ),
    'missing Location foreign key': (sql) => sql.replaceAll(
      RegExp(
        r',\s*FOREIGN KEY\(LocationId\) REFERENCES Location\(LocationId\)',
        caseSensitive: false,
      ),
      '',
    ),
    'weakened CHECK condition': (sql) =>
        sql.replaceFirst('CHECK(', 'CHECK(1 OR '),
  };
  for (final entry in mutations.entries) {
    test('rejects an empty v16 table with ${entry.key}', () async {
      final changed = writeBackup(
        scratch,
        'changed',
        version: 16,
        verifyForeignKeys: false,
        prepare: (db) {
          final original =
              db
                      .select(
                        "SELECT sql FROM sqlite_schema WHERE name = 'Note'",
                      )
                      .single['sql']
                  as String;
          final replacement = entry.value(original);
          expect(
            replacement,
            isNot(original),
            reason: 'The malformed fixture must actually change the schema.',
          );
          db.execute('DROP TABLE Note');
          db.execute(replacement);
        },
      );
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      final before = sha256.convert(File(changed).readAsBytesSync());
      await expectLater(
        mergeArchives([changed, clean], (_) {}),
        throwsA(
          isA<MergeFailure>()
              .having((e) => e.code, 'code', 'unsupportedSchema')
              .having((e) => e.schemaVersion, 'schemaVersion', 16)
              .having((e) => e.schemaTable, 'table', 'Note'),
        ),
      );
      expect(sha256.convert(File(changed).readAsBytesSync()), before);
    });
  }

  test('rejects unknown columns even in an empty table', () async {
    final bad = writeBackup(
      scratch,
      'bad',
      version: 16,
      prepare: (db) =>
          db.execute('ALTER TABLE Note ADD COLUMN UnknownMeaning TEXT'),
    );
    final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
    await expectLater(
      mergeArchives([bad, clean], (_) {}),
      throwsA(
        isA<MergeFailure>().having((e) => e.schemaTable, 'table', 'Note'),
      ),
    );
  });

  test(
    'rejects disagreement between manifest and SQLite user_version',
    () async {
      final bad = writeBackup(
        scratch,
        'bad',
        version: 16,
        prepare: (db) => db.execute('PRAGMA user_version = 14'),
      );
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      await expectLater(
        mergeArchives([bad, clean], (_) {}),
        throwsA(
          isA<MergeFailure>().having(
            (e) => e.schemaTable,
            'table',
            'user_version',
          ),
        ),
      );
    },
  );

  test('accepts harmless quoting, whitespace and SQL comments', () async {
    final source = writeBackup(
      scratch,
      'quoted',
      version: 16,
      prepare: (db) {
        final sql =
            db
                    .select("SELECT sql FROM sqlite_schema WHERE name='Note'")
                    .single['sql']
                as String;
        db.execute('DROP TABLE Note');
        db.execute(
          sql.replaceFirst(
            'Content TEXT',
            '"Content" /* schema-only comment */ TEXT',
          ),
        );
        addDocument(db, 1, 101);
        note(db, id: 1, guid: 'kept', location: 1, body: 'Keep this text');
      },
    );
    final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
    final result = await mergeArchives([source, clean], (_) {});
    final out = readOutput(scratch, result.archivePath, version: 16);
    expect(
      out.db.select('SELECT Content FROM Note').single['Content'],
      'Keep this text',
    );
  });
}
