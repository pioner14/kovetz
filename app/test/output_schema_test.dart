import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:kovetz/merge.dart';
import 'package:kovetz/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/merge_fixtures.dart';

/// The merged database must use the v16 schema the restoring app expects:
/// GRDB-based JW Library rejects the older schema as damaged data.
void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('output-schema-');
  });
  tearDown(() => scratch.delete(recursive: true));

  void grdb(Database db, [List<String> migrations = knownGrdbMigrations]) {
    db.execute(
      'CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)',
    );
    for (final migration in migrations) {
      db.execute('INSERT INTO grdb_migrations VALUES (?)', [migration]);
    }
  }

  String backup(String name, {bool modern = false, String? date}) =>
      writeBackup(
        scratch,
        name,
        version: 16,
        date: date ?? fixtureEarlier,
        prepare: (db) {
          addDocument(db, 1, 101);
          note(db, id: 1, guid: 'n-$name', location: 1, body: name);
          if (modern) grdb(db);
        },
      );

  Set<String> objects(Database db, String type) => {
    for (final row in db.select(
      'SELECT name FROM sqlite_master WHERE type = ? AND sql IS NOT NULL',
      [type],
    ))
      row['name'] as String,
  };

  test('a GRDB input selects the GRDB schema even if not primary', () async {
    final older = backup('older');
    final modern = backup('modern', modern: true, date: fixtureLater);
    final result = await mergeArchives(
      [older, modern],
      (_) {},
      options: MergeOptions(primaryPath: older),
    );
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      output.db
          .select('SELECT identifier FROM grdb_migrations ORDER BY rowid')
          .map((row) => row['identifier']),
      knownGrdbMigrations,
    );
    expect(
      objects(output.db, 'index'),
      isNot(contains('IX_Tag_Name_Type_TagId')),
    );
    expect(objects(output.db, 'trigger'), hasLength(23));
    expect(
      output.db.select('SELECT Content FROM Note').map((r) => r['Content']),
      unorderedEquals(['older', 'modern']),
    );
  });

  test('older inputs keep the older v16 schema', () async {
    final result = await mergeArchives([
      backup('left'),
      backup('right', date: fixtureLater),
    ], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(objects(output.db, 'table'), isNot(contains('grdb_migrations')));
    expect(objects(output.db, 'index'), contains('IX_Tag_Name_Type_TagId'));
  });

  test('an unknown GRDB migration set is reported, not guessed', () async {
    final newer = writeBackup(
      scratch,
      'newer-app',
      version: 16,
      prepare: (db) => grdb(db, [...knownGrdbMigrations, 'v14']),
    );
    await expectLater(
      mergeArchives([newer, backup('other')], (_) {}),
      throwsA(
        isA<MergeFailure>()
            .having((e) => e.code, 'code', 'unsupportedSchema')
            .having((e) => e.schemaTable, 'table', 'grdb_migrations'),
      ),
    );
  });

  test('archive matches JW Library conventions', () async {
    final source = backup('with-journal');
    final zip = ZipDecoder().decodeBytes(File(source).readAsBytesSync())
      ..addFile(ArchiveFile('userData.db-journal', 0, <int>[]));
    File(source).writeAsBytesSync(ZipEncoder().encode(zip));
    final result = await mergeArchives([source, backup('plain')], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      output.archive.files.map((f) => f.name),
      isNot(contains('userData.db-journal')),
    );
    final manifest = jsonDecode(
      utf8.decode(output.archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;
    final whole = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$');
    expect(manifest['name'], result.archivePath.split(RegExp(r'[/\\]')).last);
    expect(manifest['userDataBackup']['lastModifiedDate'], matches(whole));
    expect(
      output.db.select('SELECT LastModified FROM LastModified').single.values,
      [matches(whole)],
    );
  });
}
