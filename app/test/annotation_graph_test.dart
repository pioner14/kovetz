import 'dart:io';

import 'package:kovetz/merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('annotations-');
  });
  tearDown(() => scratch.delete(recursive: true));

  List<Map> versions(MergeResult result, String table) {
    final report = recoveryReport(result);
    expect(
      report,
      isNotNull,
      reason: 'Differing complete graphs must be retained in the report.',
    );
    return (report!['conflictVersions'] as List)
        .cast<Map>()
        .where((e) => e['table'] == table)
        .toList();
  }

  for (final revision in [1, 3]) {
    test(
      'highlight keeps complete selected ranges when secondary revision is $revision',
      () async {
        String input(String name, int color, int version, int token) =>
            writeBackup(
              scratch,
              name,
              version: 16,
              prepare: (db) {
                addDocument(db, 1, 101);
                db.execute('INSERT INTO UserMark VALUES(1, ?, 1, 0, ?, ?)', [
                  color,
                  'shared-mark',
                  version,
                ]);
                db.execute('INSERT INTO BlockRange VALUES(1, 1, 1, ?, ?, 1)', [
                  token,
                  token + 5,
                ]);
              },
            );
        final primary = input('primary', 2, 1, 0),
            other = input('other', 3, revision, 20);
        final result = await mergeArchives(
          [other, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary),
        );
        final out = readOutput(scratch, result.archivePath, version: 16);
        expect(
          out.db.select('SELECT ColorIndex FROM UserMark').single['ColorIndex'],
          revision > 1 ? 3 : 2,
        );
        expect(
          out.db
              .select('SELECT StartToken FROM BlockRange')
              .map((r) => r['StartToken']),
          [revision > 1 ? 20 : 0],
          reason: 'Never synthesize a hybrid of two differing highlights.',
        );
        final all = versions(result, 'UserMark');
        expect(all, hasLength(2));
        expect(all.where((v) => v['selected'] == true), hasLength(1));
        expect(
          all.map(
            (v) => ((v['record'] as Map)['BlockRanges'] as List)
                .single['StartToken'],
          ),
          unorderedEquals([0, 20]),
        );
      },
    );
  }

  test('identical highlight metadata with different ranges uses the primary whole version', () async {
    String input(String name, int start) => writeBackup(
      scratch,
      name,
      version: 16,
      prepare: (db) {
        addDocument(db, 1, 101);
        highlight(db, 'shared', 1);
        db.execute('UPDATE BlockRange SET StartToken = ?, EndToken = ?', [
          start,
          start + 5,
        ]);
      },
    );
    final primary = input('primary', 0), other = input('other', 20);
    final result = await mergeArchives(
      [primary, other],
      (_) {},
      options: MergeOptions(primaryPath: primary),
    );
    final out = readOutput(scratch, result.archivePath, version: 16);
    expect(
      out.db
          .select('SELECT StartToken FROM BlockRange')
          .map((r) => r['StartToken']),
      [0],
    );
    expect(versions(result, 'UserMark'), hasLength(2));
  });

  test('identical highlights do not produce false conflict graphs', () async {
    String input(String name) => writeBackup(
      scratch,
      name,
      version: 16,
      prepare: (db) {
        addDocument(db, 1, 101);
        highlight(db, name == 'one' ? 'SAME' : 'same', 1);
      },
    );
    final result = await mergeArchives([input('one'), input('two')], (_) {});
    final out = readOutput(scratch, result.archivePath, version: 16);
    expect(out.db.select('SELECT * FROM UserMark'), hasLength(1));
    expect(out.db.select('SELECT * FROM BlockRange'), hasLength(1));
    expect(
      result.recoveryReportPath,
      isNull,
      reason: 'Case alone in a GUID does not create a differing highlight.',
    );
    expect(result.warnings, isEmpty);
  });

  test(
    'different playlist marker graphs are both active and documented',
    () async {
      String input(String name, int verse) => writeBackup(
        scratch,
        name,
        version: 16,
        media: {
          'clip.mp4': [1, 2, 3],
        },
        prepare: (db) => playlist(
          db,
          document: 101,
          name: 'Clip',
          bytes: [1, 2, 3],
          thumbnail: 'clip.mp4',
          verse: verse,
        ),
      );
      final primary = input('primary', 1), other = input('other', 2);
      final result = await mergeArchives(
        [other, primary],
        (_) {},
        options: MergeOptions(primaryPath: primary),
      );
      final out = readOutput(scratch, result.archivePath, version: 16);
      expect(out.db.select('SELECT * FROM PlaylistItem'), hasLength(2));
      expect(
        out.db
            .select(
              'SELECT VerseId FROM PlaylistItemMarkerBibleVerseMap ORDER BY VerseId',
            )
            .map((r) => r['VerseId']),
        [1, 2],
      );
      final alternatives = versions(result, 'Playlist');
      expect(alternatives, hasLength(2));
      for (final version in alternatives) {
        final graph =
            ((version['record'] as Map)['Items'] as List).single as Map;
        expect((graph['Thumbnail'] as Map)['FilePath'], 'clip.mp4');
        expect((graph['Thumbnail'] as Map)['Hash'], isNotEmpty);
      }
    },
  );

  test(
    'same playlist media content under another filename is not duplicated',
    () async {
      String input(String name, String filename) => writeBackup(
        scratch,
        name,
        version: 16,
        media: {
          filename: [1, 2, 3],
        },
        prepare: (db) {
          playlist(
            db,
            document: 101,
            name: 'Clip',
            bytes: [1, 2, 3],
            thumbnail: 'clip.mp4',
            verse: 1,
          );
          db.execute('BEGIN');
          db.execute('PRAGMA defer_foreign_keys = ON');
          db.execute('UPDATE IndependentMedia SET FilePath = ?', [filename]);
          db.execute('UPDATE PlaylistItem SET ThumbnailFilePath = ?', [
            filename,
          ]);
          db.execute('COMMIT');
        },
      );
      final result = await mergeArchives([
        input('one', 'one.mp4'),
        input('two', 'two.mp4'),
      ], (_) {});
      final out = readOutput(scratch, result.archivePath, version: 16);
      expect(out.db.select('SELECT * FROM PlaylistItem'), hasLength(1));
      expect(out.db.select('SELECT * FROM TagMap'), hasLength(1));
    },
  );

  test('playlist keeps primary order and intentional repeated items', () async {
    String input(String name, List<int> order) => writeBackup(
      scratch,
      name,
      version: 16,
      media: {
        'clip.mp4': [1, 2, 3],
      },
      prepare: (db) {
        playlist(
          db,
          document: 101,
          name: 'A',
          bytes: [1, 2, 3],
          thumbnail: 'clip.mp4',
          verse: 1,
        );
        _duplicateClip(db);
        db.execute(
          "INSERT INTO PlaylistItem(PlaylistItemId,Label,Accuracy,EndAction) VALUES(3,'B',1,0)",
        );
        db.execute('DELETE FROM TagMap');
        for (var i = 0; i < order.length; i++) {
          db.execute('INSERT INTO TagMap VALUES(?,?,NULL,NULL,1,?)', [
            i + 1,
            order[i],
            i,
          ]);
        }
      },
    );
    final primary = input('primary', [1, 2, 3]),
        other = input('other', [3, 2, 1]);
    final result = await mergeArchives(
      [other, primary],
      (_) {},
      options: MergeOptions(primaryPath: primary),
    );
    final out = readOutput(scratch, result.archivePath, version: 16);
    expect(
      out.db
          .select(
            'SELECT Label FROM TagMap JOIN PlaylistItem USING(PlaylistItemId) ORDER BY Position',
          )
          .map((r) => r['Label']),
      ['A', 'A', 'B'],
    );
    expect(versions(result, 'Playlist'), hasLength(2));
  });
  for (final version in [14, 16]) {
    test(
      'expands repeated references to one playlist item in schema $version',
      () async {
        final source = writeBackup(
          scratch,
          'repeated',
          version: version,
          media: {
            'clip.mp4': [1, 2, 3],
          },
          prepare: (db) {
            playlist(
              db,
              document: 101,
              name: 'Repeat clip',
              bytes: [1, 2, 3],
              thumbnail: 'clip.mp4',
              verse: 1,
            );
            db.execute('INSERT INTO TagMap VALUES(2,1,NULL,NULL,1,1)');
          },
        );
        final clean = writeBackup(
          scratch,
          'clean',
          version: 16,
          prepare: (_) {},
        );
        final result = await mergeArchives([source, clean], (_) {});
        final out = readOutput(scratch, result.archivePath, version: 16);
        expect(
          out.db
              .select(
                'SELECT Label FROM TagMap JOIN PlaylistItem USING(PlaylistItemId) ORDER BY Position',
              )
              .map((r) => r['Label']),
          ['Repeat clip', 'Repeat clip'],
        );
        expect(out.db.select('SELECT * FROM PlaylistItemMarker'), hasLength(2));
        expect(
          out.db.select('SELECT * FROM PlaylistItemMarkerBibleVerseMap'),
          hasLength(2),
        );
        expect(
          out.db.select('SELECT * FROM PlaylistItemMarkerParagraphMap'),
          hasLength(2),
        );
        expect(
          result.warnings,
          isEmpty,
          reason: 'A valid intentional repeat is not a broken link.',
        );
      },
    );
  }
  test('equal items shared by different playlists are matched within each playlist', () async {
    String input(String name, bool swapped) => writeBackup(
      scratch,
      name,
      version: 16,
      media: {
        'clip.mp4': [1, 2, 3],
      },
      prepare: (db) {
        playlist(
          db,
          document: 101,
          name: 'A',
          bytes: [1, 2, 3],
          thumbnail: 'clip.mp4',
          verse: 1,
        );
        _duplicateClip(db);
        db.execute("INSERT INTO Tag VALUES(2,2,'Other')");
        db.execute('INSERT INTO TagMap VALUES(2,2,NULL,NULL,2,0)');
        if (swapped) {
          db.execute(
            'UPDATE TagMap SET PlaylistItemId = CASE PlaylistItemId WHEN 1 THEN 2 ELSE 1 END',
          );
        }
      },
    );
    final primary = input('primary', false), other = input('other', true);
    final result = await mergeArchives(
      [other, primary],
      (_) {},
      options: MergeOptions(primaryPath: primary),
    );
    final out = readOutput(scratch, result.archivePath, version: 16);
    expect(
      out.db
          .select(
            'SELECT Name,count(*) AS n FROM Tag JOIN TagMap USING(TagId) GROUP BY Name ORDER BY Name',
          )
          .map((r) => r.values.toList()),
      [
        ['Other', 1],
        ['Playlist', 1],
      ],
    );
    expect(result.warnings, isEmpty);
  });
}

void _duplicateClip(Database db) {
  db.execute(
    'INSERT INTO PlaylistItem SELECT 2, Label, StartTrimOffsetTicks, EndTrimOffsetTicks, Accuracy, EndAction, ThumbnailFilePath FROM PlaylistItem WHERE PlaylistItemId=1',
  );
  db.execute(
    'INSERT INTO PlaylistItemLocationMap SELECT 2, LocationId, MajorMultimediaType, BaseDurationTicks FROM PlaylistItemLocationMap WHERE PlaylistItemId=1',
  );
  db.execute(
    'INSERT INTO PlaylistItemIndependentMediaMap SELECT 2, IndependentMediaId, DurationTicks FROM PlaylistItemIndependentMediaMap WHERE PlaylistItemId=1',
  );
  db.execute(
    'INSERT INTO PlaylistItemMarker SELECT 2, 2, Label, StartTimeTicks, DurationTicks, EndTransitionDurationTicks FROM PlaylistItemMarker WHERE PlaylistItemMarkerId=1',
  );
  db.execute(
    'INSERT INTO PlaylistItemMarkerBibleVerseMap SELECT 2, VerseId FROM PlaylistItemMarkerBibleVerseMap WHERE PlaylistItemMarkerId=1',
  );
  db.execute(
    'INSERT INTO PlaylistItemMarkerParagraphMap SELECT 2, MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph FROM PlaylistItemMarkerParagraphMap WHERE PlaylistItemMarkerId=1',
  );
}
