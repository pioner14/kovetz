import 'dart:io';

import 'package:kovetz/merge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('preservation-');
  });
  tearDown(() => scratch.delete(recursive: true));

  for (final policy in NoteConflictPolicy.values) {
    test(
      'note policy $policy selects one version and retains both texts in TXT',
      () async {
        String input(String name, String body, String date) => writeBackup(
          scratch,
          name,
          version: 16,
          date: date,
          prepare: (db) {
            addDocument(db, 1, 101);
            note(
              db,
              id: 1,
              guid: 'same-guid',
              location: 1,
              body: body,
              date: date,
            );
          },
        );
        final primary = input(
          'primary',
          'Earlier independent annotation',
          fixtureEarlier,
        );
        final newer = input(
          'newer',
          'Later independent annotation',
          fixtureLater,
        );
        final result = await mergeArchives(
          [newer, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary, notePolicy: policy),
        );
        final output = readOutput(scratch, result.archivePath, version: 16);
        expect(
          output.db.select('SELECT Content FROM Note').single['Content'],
          policy == NoteConflictPolicy.primary
              ? 'Earlier independent annotation'
              : 'Later independent annotation',
        );
        final report = File(result.reportPath).readAsStringSync();
        expect(
          report,
          contains('Earlier independent annotation'),
          reason: 'The non-selected version must remain recoverable without opening the source archive.',
        );
        expect(report, contains('Later independent annotation'));
        expect(report, contains('primary.jwlibrary'));
        expect(report, contains('newer.jwlibrary'));
      },
    );
  }

  for (final policy in FieldConflictPolicy.values) {
    test(
      'answer policy $policy selects one value and retains both values in TXT',
      () async {
        String input(String name, String value, String date) => writeBackup(
          scratch,
          name,
          version: 16,
          date: date,
          prepare: (db) {
            addDocument(db, 1, 101);
            db.execute('INSERT INTO InputField VALUES(1, ?, ?)', [
              'question',
              value,
            ]);
          },
        );
        final primary = input(
          'primary',
          'Earlier complete answer',
          fixtureEarlier,
        );
        final newer = input('newer', 'Later complete answer', fixtureLater);
        final result = await mergeArchives(
          [newer, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary, fieldPolicy: policy),
        );
        final output = readOutput(scratch, result.archivePath, version: 16);
        expect(
          output.db.select('SELECT Value FROM InputField').single['Value'],
          policy == FieldConflictPolicy.primary
              ? 'Earlier complete answer'
              : 'Later complete answer',
        );
        final report = File(result.reportPath).readAsStringSync();
        expect(report, contains('Earlier complete answer'));
        expect(report, contains('Later complete answer'));
      },
    );
  }

  test(
    'same bookmark moved to another slot is retained once in the primary slot',
    () async {
      String input(String name, int slot) => writeBackup(
        scratch,
        name,
        version: 16,
        prepare: (db) {
          publication(db);
          addDocument(db, 1, 101);
          bookmark(
            db,
            id: 1,
            location: 1,
            publication: 9,
            slot: slot,
            title: 'Same place',
          );
        },
      );
      final primary = input('primary', 7), other = input('other', 1);
      final result = await mergeArchives(
        [other, primary],
        (_) {},
        options: MergeOptions(primaryPath: primary),
      );
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(
        output.db.select('SELECT Slot FROM Bookmark').map((r) => r['Slot']),
        [7],
      );
      expect(result.skippedBookmarks, 0);
    },
  );

  test('ten bookmarks reordered on another device do not create false overflow', () async {
    String input(String name, int offset) => writeBackup(
      scratch,
      name,
      version: 16,
      prepare: (db) {
        publication(db);
        for (var i = 0; i < 10; i++) {
          addDocument(db, 20 + i, 1000 + i);
          bookmark(
            db,
            id: i + 1,
            location: 20 + i,
            publication: 9,
            slot: (i + offset) % 10,
            title: 'Place $i',
          );
        }
      },
    );
    final primary = input('primary', 0), other = input('other', 3);
    final result = await mergeArchives(
      [other, primary],
      (_) {},
      options: MergeOptions(primaryPath: primary),
    );
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(output.db.select('SELECT * FROM Bookmark'), hasLength(10));
    expect(
      result.skippedBookmarks,
      0,
      reason:
          'Different positions do not make ten existing bookmarks into twenty.',
    );
    expect(result.warnings, isEmpty);
  });

  Future<MergeResult> initialResult() async {
    final bad = writeBackup(
      scratch,
      'bad',
      version: 16,
      allowBrokenReferences: true,
      prepare: (db) {
        note(db, id: 1, guid: 'orphan', location: 999, body: 'Detached note');
      },
    );
    final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
    final first = await mergeArchives([bad, clean], (_) {});
    addTearDown(() => File(first.archivePath).parent.delete(recursive: true));
    expect(first.warnings.single.count, 1);
    // History is imported from results of versions that embedded it.
    embedReportLikeOldVersions(first);
    return first;
  }

  void expectSingleHistoricalProblem(MergeResult result) {
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      result.warnings.single.count,
      1,
      reason: 'One source problem must not be counted again for shared recovery history.',
    );
    expectOnlyJwLibraryEntries(output.archive);
    expect(recoveryReport(result)!['unresolvedRecords'], hasLength(1));
  }

  test(
    'byte-identical input copies do not duplicate recovery history',
    () async {
      final first = await initialResult();
      final copy = File(first.archivePath)
          .copySync('${scratch.path}/renamed-copy.jwlibrary');
      final result = await mergeArchives([
        first.archivePath,
        copy.path,
      ], (_) {});
      expectSingleHistoricalProblem(result);
    },
  );

  test(
    'different merge results with a common ancestor deduplicate shared history',
    () async {
      final first = await initialResult();
      Future<MergeResult> branch(String name, int documentId) async {
        final extra = writeBackup(
          scratch,
          name,
          version: 16,
          prepare: (db) {
            addDocument(db, 1, documentId);
            note(db, id: 1, guid: name, location: 1, body: 'Branch $name');
          },
        );
        final result = await mergeArchives([first.archivePath, extra], (_) {});
        addTearDown(
          () => File(result.archivePath).parent.delete(recursive: true),
        );
        embedReportLikeOldVersions(result);
        return result;
      }

      final left = await branch('left', 101),
          right = await branch('right', 102);
      final result = await mergeArchives([
        left.archivePath,
        right.archivePath,
      ], (_) {});
      expectSingleHistoricalProblem(result);
    },
  );
}
