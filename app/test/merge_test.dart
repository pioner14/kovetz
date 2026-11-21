import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:backup_merge/merge.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

const _earlier = '2025-01-01T10:00:00Z';
const _later = '2025-02-01T10:00:00Z';

void main() {
  late Directory scratch;

  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('kovetz-test-');
  });

  tearDown(() async {
    await scratch.delete(recursive: true);
  });

  for (final (leftVersion, rightVersion) in [
    (5, 5),
    (5, 8),
    (8, 8),
    (14, 14),
    (5, 16),
  ]) {
    test(
      'upgrades v$leftVersion + v$rightVersion to v16 without editing inputs',
      () async {
        String source(String name, int version, int document) => writeBackup(
          scratch,
          name,
          version: version,
          prepare: (db) {
            addDocument(db, 4, document);
            note(
              db,
              id: 4,
              guid: name,
              location: 4,
              body: 'Сохранённый текст $name',
            );
            db.execute(
              "INSERT INTO Tag(TagId, Type, Name) VALUES (1, 1, 'Общее'), (2, 0, 'Favorites')",
            );
            if (version == 5) {
              db.execute(
                'INSERT INTO TagMap VALUES (1, 1, 4, 1, 0), (2, 0, 4, 2, 0)',
              );
            } else {
              db.execute(
                'INSERT INTO TagMap VALUES (1, NULL, NULL, 4, 1, 0), (2, NULL, 4, NULL, 2, 0)',
              );
            }
          },
        );
        final left = source('left', leftVersion, 301);
        final right = source('right', rightVersion, 302);
        final before = [left, right]
            .map(
              (path) => sha256.convert(File(path).readAsBytesSync()).toString(),
            )
            .toList();
        final result = await mergeArchives([left, right], (_) {});
        final output = readOutput(scratch, result.archivePath, version: 16);
        expect(
          output.db
              .select(
                'SELECT Guid, Content, DocumentId FROM Note JOIN Location USING(LocationId) ORDER BY Guid',
              )
              .map((row) => row.values.toList()),
          [
            ['left', 'Сохранённый текст left', 301],
            ['right', 'Сохранённый текст right', 302],
          ],
        );
        expect(
          output.db
              .select(
                "SELECT Guid FROM TagMap JOIN Note USING(NoteId) JOIN Tag USING(TagId) WHERE Tag.Name = 'Общее'",
              )
              .map((row) => row['Guid']),
          unorderedEquals(['left', 'right']),
        );
        expect(
          output.db
              .select(
                'SELECT DocumentId FROM TagMap JOIN Location USING(LocationId) JOIN Tag USING(TagId) WHERE Tag.Type = 0',
              )
              .map((row) => row['DocumentId']),
          unorderedEquals([301, 302]),
        );
        expect(
          output.db
              .select('PRAGMA table_info(Location)')
              .map((row) => row['name']),
          containsAll(['Specialty', 'Edition']),
        );
        expect(
          output.db.select('PRAGMA table_info(Note)').map((row) => row['name']),
          contains('Created'),
        );
        if (leftVersion < 14) {
          expect(
            output.db
                .select("SELECT Created FROM Note WHERE Guid = 'left'")
                .single['Created'],
            _earlier,
          );
        }
        if (rightVersion < 14) {
          expect(
            output.db
                .select("SELECT Created FROM Note WHERE Guid = 'right'")
                .single['Created'],
            _earlier,
          );
        }
        expect(
          [left, right].map(
            (path) => sha256.convert(File(path).readAsBytesSync()).toString(),
          ),
          before,
        );
      },
    );
  }

  test(
    'merges v16 editions with v14 and v8 as distinct media locations',
    () async {
      final modern = writeBackup(
        scratch,
        'modern',
        version: 16,
        date: _later,
        prepare: (db) {
          addDocument(db, 1, 301);
          note(
            db,
            id: 1,
            guid: 'shared',
            location: 1,
            body: 'new',
            date: _later,
          );
          for (final (id, specialty, edition) in [
            (10, null, null),
            (11, 'special-a', null),
            (12, 'special-b', null),
            (13, null, 'edition-a'),
          ]) {
            db.execute(
              '''
            INSERT INTO Location(LocationId, DocumentId, Track, KeySymbol,
              MepsLanguage, Type, Specialty, Edition)
            VALUES (?, 910, 1, 'media', 0, 3, ?, ?)
          ''',
              [id, specialty, edition],
            );
            note(db, id: id, guid: 'media-$id', location: id, body: 'marker');
          }
        },
      );
      final previous = writeBackup(
        scratch,
        'previous',
        prepare: (db) {
          addDocument(db, 1, 302);
          note(db, id: 1, guid: 'shared', location: 1, body: 'old');
          db.execute('''
        INSERT INTO Location(LocationId, DocumentId, Track, KeySymbol, MepsLanguage, Type)
        VALUES (2, 910, 1, 'media', 0, 3)
      ''');
          note(db, id: 2, guid: 'previous-media', location: 2, body: 'marker');
        },
      );
      final legacy = writeBackup(
        scratch,
        'legacy',
        version: 8,
        prepare: (db) {
          addDocument(db, 1, 401);
          note(db, id: 1, guid: 'legacy', location: 1, body: 'older format');
        },
      );
      final result = await mergeArchives([legacy, previous, modern], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(output.db.select('PRAGMA user_version').single.values.single, 16);
      expect(
        output.db.select('SELECT Content FROM Note WHERE Guid = ?', [
          'shared',
        ]).single['Content'],
        'new',
      );
      expect(
        output.db
            .select('SELECT Specialty, Edition FROM Location WHERE Type = 3')
            .map((row) => row.values.toList()),
        unorderedEquals([
          [null, null],
          ['special-a', null],
          ['special-b', null],
          [null, 'edition-a'],
        ]),
      );
      expect(
        output.db.select('''
      SELECT COUNT(DISTINCT LocationId) AS n FROM Note
      WHERE Guid IN ('media-10', 'previous-media')
    ''').single['n'],
        1,
      );
      expect(result.counts['Note'], 7);
    },
  );

  test('preserves v16 playlists and media when merging with v14', () async {
    final bytes = utf8.encode('synthetic media');
    final newest = writeBackup(
      scratch,
      'v16-playlist',
      version: 16,
      date: _later,
      media: {'clip.mp4': bytes},
      prepare: (db) {
        playlist(
          db,
          document: 301,
          name: 'New playlist',
          bytes: bytes,
          thumbnail: 'clip.mp4',
          verse: 5,
        );
      },
    );
    final previous = writeBackup(
      scratch,
      'v14-playlist',
      media: {'clip.mp4': bytes},
      prepare: (db) {
        playlist(
          db,
          document: 302,
          name: 'Previous playlist',
          bytes: bytes,
          thumbnail: 'clip.mp4',
          verse: 6,
        );
      },
    );
    final result = await mergeArchives([previous, newest], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(result.counts['PlaylistItem'], 2);
    expect(result.counts['IndependentMedia'], 1);
    expect(
      output.db
          .select('SELECT COUNT(*) AS n FROM PlaylistItemMarker')
          .single['n'],
      2,
    );
    expect(output.archive.findFile('clip.mp4')!.content, bytes);
  });

  test(
    'keeps valid notes and reports orphaned tag links without editing inputs',
    () async {
      final broken = writeBackup(
        scratch,
        'broken',
        version: 16,
        allowBrokenReferences: true,
        prepare: (db) {
          addDocument(db, 1, 301);
          note(db, id: 1, guid: 'kept', location: 1, body: 'valid note');
          db.execute('INSERT INTO TagMap VALUES (1, NULL, NULL, 99, 99, 0)');
        },
      );
      final healthy = writeBackup(
        scratch,
        'healthy',
        prepare: (db) {
          addDocument(db, 1, 302);
          note(db, id: 1, guid: 'healthy', location: 1, body: 'healthy source');
        },
      );
      final original = File(broken).readAsBytesSync();
      final result = await mergeArchives([broken, healthy], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(
        output.db.select('SELECT Guid FROM Note').map((row) => row['Guid']),
        unorderedEquals(['kept', 'healthy']),
      );
      expect(output.db.select('SELECT * FROM TagMap'), isEmpty);
      expect(
        result.warnings.map((warning) => warning.code),
        contains('unresolvedLinks'),
      );
      expectOnlyJwLibraryEntries(output.archive);
      final report = recoveryReport(result)!;
      // Format 2 preserves alternatives and stable warning event identities.
      expect(report['formatVersion'], 2);
      expect(report['outputSchemaVersion'], 16);
      final unresolved = report['unresolvedRecords'] as List<dynamic>;
      expect(
        unresolved,
        contains(
          isA<Map<String, dynamic>>()
              .having((entry) => entry['table'], 'table', 'TagMap')
              .having(
                (entry) => entry['record'],
                'record',
                containsPair('TagId', 99),
              ),
        ),
      );
      final reportText = File(result.recoveryReportPath!).readAsStringSync();
      expect(reportText, contains('NoteId'));
      expect(reportText, contains('99'));
      expect(File(broken).readAsBytesSync(), original);
    },
  );

  test('keeps valid data and reports missing attached media', () async {
    final missing = writeBackup(
      scratch,
      'missing-media',
      version: 16,
      prepare: (db) {
        playlist(
          db,
          document: 401,
          name: 'Missing clip',
          bytes: utf8.encode('absent clip'),
          thumbnail: 'clip.mp4',
          verse: 4,
        );
        note(
          db,
          id: 1,
          guid: 'readable-note',
          location: 1,
          body: 'preserved despite missing clip',
        );
      },
    );
    final healthy = writeBackup(scratch, 'healthy-media', prepare: (_) {});
    final original = File(missing).readAsBytesSync();
    final result = await mergeArchives([missing, healthy], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      output.db.select('SELECT Content FROM Note').single['Content'],
      'preserved despite missing clip',
    );
    expect(
      result.warnings.map((warning) => warning.code),
      contains('missingMedia'),
    );
    expectOnlyJwLibraryEntries(output.archive);
    expect(recoveryReport(result)!['outputSchemaVersion'], 16);
    expect(
      File(result.recoveryReportPath!).readAsStringSync(),
      contains('clip.mp4'),
    );
    expect(File(missing).readAsBytesSync(), original);
  });

  test(
    'recovers missing media by content hash from a differently named file',
    () async {
      final clip = utf8.encode('shared synthetic clip bytes');
      final missing = writeBackup(
        scratch,
        'missing-recoverable',
        version: 16,
        prepare: (db) => playlist(
          db,
          document: 301,
          name: 'Recovered clip',
          bytes: clip,
          thumbnail: 'clip.mp4',
          verse: 7,
        ),
      );
      final donor = writeBackup(
        scratch,
        'media-donor',
        version: 16,
        media: {'different-name.mp4': clip},
        prepare: (_) {},
      );
      final result = await mergeArchives([missing, donor], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(
        result.warnings.map((warning) => warning.code),
        contains('recoveredMedia'),
      );
      expect(
        result.warnings.map((warning) => warning.code),
        isNot(contains('missingMedia')),
      );
      final row = output.db.select('''
      SELECT item.Label, media.FilePath, media.Hash
      FROM PlaylistItem AS item
      JOIN PlaylistItemIndependentMediaMap USING(PlaylistItemId)
      JOIN IndependentMedia AS media USING(IndependentMediaId)
    ''').single;
      expect(row['Label'], 'Recovered clip');
      expect(row['Hash'], sha256.convert(clip).toString());
      expect(output.archive.findFile(row['FilePath'] as String)!.content, clip);
      expect(
        output.db.select('SELECT * FROM PlaylistItemMarker'),
        hasLength(1),
      );
    },
  );

  test(
    'imports recovery history from an older result without embedding files',
    () async {
      final broken = writeBackup(
        scratch,
        'original-orphan',
        version: 16,
        allowBrokenReferences: true,
        prepare: (db) {
          addDocument(db, 1, 301);
          note(
            db,
            id: 1,
            guid: 'original-note',
            location: 1,
            body: 'original body',
          );
          db.execute('INSERT INTO TagMap VALUES (1, NULL, NULL, 99, 99, 0)');
        },
      );
      final healthy = writeBackup(scratch, 'first-healthy', prepare: (_) {});
      final first = await mergeArchives([broken, healthy], (_) {});
      final firstOutput = readOutput(scratch, first.archivePath, version: 16);
      expectOnlyJwLibraryEntries(firstOutput.archive);
      final firstReport = recoveryReport(first)!;
      // Results of versions up to 0.4.2 carried the report and source copies
      // inside the archive; history is still imported from such results.
      embedReportLikeOldVersions(first);
      final legacy = ZipDecoder().decodeBytes(
        File(first.archivePath).readAsBytesSync(),
      )..addFile(ArchiveFile('recovery-sources/old.jwlibrary', 3, [1, 2, 3]));
      File(first.archivePath).writeAsBytesSync(ZipEncoder().encode(legacy));
      final further = writeBackup(
        scratch,
        'further-healthy',
        version: 16,
        prepare: (db) {
          addDocument(db, 1, 302);
          note(
            db,
            id: 1,
            guid: 'further-note',
            location: 1,
            body: 'further body',
          );
        },
      );
      final second = await mergeArchives([first.archivePath, further], (_) {});
      final secondScratch = Directory('${scratch.path}/second-output')
        ..createSync();
      final output = readOutput(secondScratch, second.archivePath, version: 16);
      expectOnlyJwLibraryEntries(output.archive);
      final report = recoveryReport(second)!;
      expect(
        second.warnings.map((warning) => warning.code),
        contains('unresolvedLinks'),
      );
      expect(
        report['warnings'],
        containsAll(firstReport['warnings'] as List<dynamic>),
      );
      expect(
        report['unresolvedRecords'],
        containsAll(firstReport['unresolvedRecords'] as List<dynamic>),
      );
      expect(
        output.db.select('SELECT Guid FROM Note').map((row) => row['Guid']),
        unorderedEquals(['original-note', 'further-note']),
      );
    },
  );

  test(
    'keeps ten bookmark slots and reports overflowing original records',
    () async {
      String source(String name, int offset) => writeBackup(
        scratch,
        name,
        version: 16,
        prepare: (db) {
          publication(db);
          for (var slot = 0; slot < 6; slot++) {
            addDocument(db, slot + 20, offset + slot);
            db.execute(
              '''
            INSERT INTO Bookmark(BookmarkId, LocationId, PublicationLocationId, Slot, Title)
            VALUES (?, ?, 9, ?, ?)
          ''',
              [slot + 1, slot + 20, slot, '$name bookmark $slot'],
            );
          }
        },
      );
      final left = source('left-bookmarks', 301);
      final right = source('right-bookmarks', 401);
      final originals = {
        for (final path in [left, right])
          sha256.convert(File(path).readAsBytesSync()).toString(): File(path)
              .readAsBytesSync(),
      };
      final result = await mergeArchives([left, right], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(result.counts['Bookmark'], 10);
      expect(result.skippedBookmarks, 2);
      expect(
        output.db.select('SELECT Slot FROM Bookmark').map((row) => row['Slot']),
        unorderedEquals(List.generate(10, (index) => index)),
      );
      expectOnlyJwLibraryEntries(output.archive);
      final report = recoveryReport(result)!;
      final overflow = (report['unresolvedRecords'] as List<dynamic>)
          .where((entry) => entry['reason'] == 'bookmarkSlotsFull')
          .toList();
      expect(overflow, hasLength(2));
      for (final entry in overflow) {
        expect(entry['table'], 'Bookmark');
        expect(entry['record']['BookmarkId'], isA<int>());
        expect(entry['record']['PublicationLocationId'], 9);
        expect(entry['record']['Title'], contains('bookmark'));
        // The record names the untouched source backup it came from.
        expect(originals.keys, contains(entry['sourceFingerprint']));
      }
      expect(
        output.db
            .select('SELECT Title FROM Bookmark')
            .map((row) => row['Title'])
            .toSet()
            .union(overflow.map((entry) => entry['record']['Title']).toSet()),
        hasLength(12),
      );
    },
  );

  test('reports unknown schema versions with the version number', () async {
    final input = writeBackup(scratch, 'future', prepare: (db) {});
    final original = ZipDecoder().decodeBytes(File(input).readAsBytesSync());
    final manifest = original.findFile('manifest.json')!;
    final metadata =
        jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
    metadata['userDataBackup']['schemaVersion'] = 99;
    final changed = utf8.encode(jsonEncode(metadata));
    final archive = Archive();
    for (final file in original.files) {
      archive.addFile(
        file.name == 'manifest.json'
            ? ArchiveFile(file.name, changed.length, changed)
            : file,
      );
    }
    File(input).writeAsBytesSync(ZipEncoder().encode(archive));
    await expectLater(
      mergeArchives([input, input], (_) {}),
      throwsA(
        isA<MergeFailure>()
            .having((e) => e.code, 'code', 'unsupportedSchema')
            .having((e) => e.schemaVersion, 'schema', 99),
      ),
    );
  });

  test(
    'merges independent IDs, edited notes, tags, fields and favorites',
    () async {
      final newer = writeBackup(
        scratch,
        'newer',
        date: _later,
        prepare: (db) {
          addDocument(db, 1, 301);
          addDocument(db, 2, 302);
          publication(db);
          note(
            db,
            id: 1,
            guid: 'shared-note',
            location: 1,
            body: 'new',
            date: _later,
          );
          note(db, id: 2, guid: 'new-only', location: 2, body: 'new source');
          highlight(db, 'new mark', 2);
          studyData(
            db,
            bookmarkTitle: 'new bookmark',
            fieldValue: 'new answer',
          );
          db.execute('''
        INSERT INTO TagMap(TagMapId, NoteId, TagId, Position)
        VALUES (1, 2, 1, 0), (2, 1, 1, 1)
      ''');
        },
      );
      final older = writeBackup(
        scratch,
        'older',
        prepare: (db) {
          addDocument(db, 1, 401);
          addDocument(db, 2, 402);
          publication(db);
          note(db, id: 1, guid: 'old-only', location: 1, body: 'old source');
          note(db, id: 2, guid: 'shared-note', location: 2, body: 'old');
          highlight(db, 'old mark', 1);
          studyData(
            db,
            bookmarkTitle: 'old bookmark',
            fieldValue: 'old answer',
          );
          db.execute('''
        INSERT INTO TagMap(TagMapId, NoteId, TagId, Position)
        VALUES (1, 1, 1, 0), (2, 2, 1, 1)
      ''');
        },
      );

      final localPort = ReceivePort();
      addTearDown(localPort.close);
      final stages = <String>[];
      final result = await mergeArchives([newer, older], (stage) {
        stages.add(stage);
        localPort.sendPort.send(stage);
      });
      expect(stages, ['reading', 'merging', 'checking', 'packing']);
      expect(result.noteConflicts, 1);
      final output = readOutput(scratch, result.archivePath, version: 16);
      final db = output.db;

      expect(
        db
            .select('''
      SELECT Guid, Content, DocumentId
      FROM Note JOIN Location USING(LocationId)
      ORDER BY Guid
    ''')
            .map((row) => row.values.toList()),
        [
          ['new-only', 'new source', 302],
          ['old-only', 'old source', 401],
          ['shared-note', 'new', 301],
        ],
      );
      final tagged = db
          .select('''
      SELECT Guid FROM TagMap JOIN Note USING(NoteId) JOIN Tag USING(TagId)
      WHERE Tag.Type = 1 AND Tag.Name = 'Study' ORDER BY Position
    ''')
          .map((row) => row['Guid'])
          .toList();
      expect(tagged, unorderedEquals(['new-only', 'old-only', 'shared-note']));
      expect(
        tagged.indexOf('new-only'),
        lessThan(tagged.indexOf('shared-note')),
      );
      expect(
        db
            .select('''
      SELECT DocumentId, Value FROM InputField JOIN Location USING(LocationId)
      ORDER BY DocumentId
    ''')
            .map((row) => row.values.toList()),
        [
          [301, 'new answer'],
          [401, 'old answer'],
        ],
      );
      expect(
        db
            .select('''
      SELECT DocumentId
      FROM TagMap JOIN Tag USING(TagId) JOIN Location USING(LocationId)
      WHERE Tag.Type = 0 ORDER BY DocumentId
    ''')
            .map((row) => row['DocumentId']),
        [301, 401],
      );
      expect(
        db
            .select('''
      SELECT Bookmark.Title, actual.DocumentId, publication.DocumentId
      FROM Bookmark
      JOIN Location AS actual ON Bookmark.LocationId = actual.LocationId
      JOIN Location AS publication ON Bookmark.PublicationLocationId = publication.LocationId
      ORDER BY Bookmark.Title
    ''')
            .map((row) => row.values.toList()),
        [
          ['new bookmark', 301, 100],
          ['old bookmark', 401, 100],
        ],
      );
      expect(db.select('SELECT DISTINCT Slot FROM Bookmark'), hasLength(2));
      expect(
        db
            .select('''
          SELECT UserMarkGuid, DocumentId, Identifier
          FROM UserMark JOIN Location USING(LocationId)
          JOIN BlockRange USING(UserMarkId) ORDER BY UserMarkGuid
        ''')
            .map((row) => row.values.toList()),
        [
          ['new mark', 302, 2],
          ['old mark', 401, 1],
        ],
      );
    },
  );

  test('copies a v8 backup into the v16 schema using logical IDs', () async {
    final old = writeBackup(
      scratch,
      'legacy',
      version: 8,
      prepare: (db) {
        addDocument(db, 4, 501);
        note(db, id: 4, guid: 'legacy-note', location: 4, body: 'legacy');
        db.execute("INSERT INTO Tag(TagId, Type, Name) VALUES (4, 1, 'Both')");
        db.execute('INSERT INTO TagMap VALUES (4, NULL, NULL, 4, 4, 0)');
        db.execute("INSERT INTO InputField VALUES (4, 'legacy', 'answer')");
      },
    );
    final modern = writeBackup(
      scratch,
      'modern',
      prepare: (db) {
        addDocument(db, 4, 502);
        note(db, id: 4, guid: 'modern-note', location: 4, body: 'modern');
        db.execute("INSERT INTO Tag VALUES (4, 1, 'Both')");
        db.execute('INSERT INTO TagMap VALUES (4, NULL, NULL, 4, 4, 0)');
      },
    );

    final result = await mergeArchives([old, modern], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);

    expect(
      output.db
          .select('''
      SELECT Guid, Created, DocumentId, Tag.Name
      FROM Note JOIN Location ON Note.LocationId = Location.LocationId
      JOIN TagMap USING(NoteId) JOIN Tag USING(TagId) ORDER BY Guid
    ''')
          .map((row) => [row['Guid'], row['DocumentId'], row['Name']]),
      [
        ['legacy-note', 501, 'Both'],
        ['modern-note', 502, 'Both'],
      ],
    );
    expect(
      output.db
          .select('''
      SELECT DocumentId, Value FROM InputField JOIN Location USING(LocationId)
    ''')
          .single
          .values
          .toList(),
      [501, 'answer'],
    );
  });

  test(
    'preserves colliding media paths, aliases and the playlist graph',
    () async {
      final bytesA = utf8.encode('first synthetic media');
      final bytesB = utf8.encode('second synthetic media');
      final one = writeBackup(
        scratch,
        'one',
        media: {'clip.mp4': bytesA, 'copy.mp4': bytesA},
        prepare: (db) => playlist(
          db,
          document: 601,
          name: 'One',
          bytes: bytesA,
          thumbnail: 'copy.mp4',
          verse: 10,
        ),
      );
      final two = writeBackup(
        scratch,
        'two',
        media: {'clip.mp4': bytesB},
        prepare: (db) => playlist(
          db,
          document: 602,
          name: 'Two',
          bytes: bytesB,
          thumbnail: 'clip.mp4',
          verse: 11,
        ),
      );

      final result = await mergeArchives([one, two], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);

      final locations = output.db.select('''
      SELECT item.Label, location.DocumentId, m.VerseId, p.ParagraphIndex
      FROM PlaylistItem AS item
      JOIN PlaylistItemLocationMap AS map USING(PlaylistItemId)
      JOIN Location AS location USING(LocationId)
      JOIN PlaylistItemMarker USING(PlaylistItemId)
      JOIN PlaylistItemMarkerBibleVerseMap AS m USING(PlaylistItemMarkerId)
      JOIN PlaylistItemMarkerParagraphMap AS p USING(PlaylistItemMarkerId)
      ORDER BY item.Label
    ''');
      expect(locations.map((row) => row.values.toList()), [
        ['One', 601, 10, 5],
        ['Two', 602, 11, 5],
      ]);
      final items = output.db.select('''
      SELECT item.Label, item.ThumbnailFilePath, media.FilePath, media.Hash
      FROM PlaylistItem AS item
      JOIN PlaylistItemIndependentMediaMap USING(PlaylistItemId)
      JOIN IndependentMedia AS media USING(IndependentMediaId)
      JOIN TagMap USING(PlaylistItemId) JOIN Tag USING(TagId)
      WHERE Tag.Type = 2 AND Tag.Name = 'Playlist'
      ORDER BY item.Label
    ''');
      expect(items, hasLength(2));
      expect(items[0]['FilePath'], isNot(items[1]['FilePath']));
      for (final (index, bytes) in [bytesA, bytesB].indexed) {
        final item = items[index];
        expect(
          item['Hash'].toString().toLowerCase(),
          sha256.convert(bytes).toString(),
        );
        for (final column in ['ThumbnailFilePath', 'FilePath']) {
          final member = output.archive.findFile(item[column] as String);
          expect(member, isNotNull);
          expect(member!.content, bytes);
        }
      }
    },
  );

  test(
    'reports legacy playlist records while retaining attached files in v16',
    () async {
      final clip = utf8.encode('legacy clip');
      final poster = utf8.encode('legacy poster');
      final legacy = writeBackup(
        scratch,
        'legacy-playlist',
        version: 8,
        media: {'clip.mp4': clip, 'poster.jpg': poster},
        prepare: (db) {
          db.execute(
            "INSERT INTO PlaylistMedia VALUES (1, 1, 'Clip', 'clip.mp4', NULL)",
          );
          db.execute(
            "INSERT INTO PlaylistItem VALUES (1, 'Legacy', 0, NULL, NULL, 0, 'poster.jpg', 1)",
          );
          db.execute(
            "INSERT INTO PlaylistItemChild VALUES (1, 100, 2, 'Marker', 20, 5, 1)",
          );
          db.execute("INSERT INTO Tag VALUES (1, 2, 'Playlist', 'poster.jpg')");
          db.execute('INSERT INTO TagMap VALUES (1, 1, NULL, NULL, 1, 0)');
        },
      );
      final other = writeBackup(
        scratch,
        'legacy-study',
        version: 8,
        prepare: (_) {},
      );

      final result = await mergeArchives([other, legacy], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(output.db.select('SELECT * FROM PlaylistItem'), isEmpty);
      expect(
        result.warnings.map((warning) => warning.code),
        contains('unresolvedLinks'),
      );
      expectOnlyJwLibraryEntries(output.archive);
      final report = recoveryReport(result)!;
      final records = report['unresolvedRecords'] as List<dynamic>;
      expect(
        records.map((record) => record['table']),
        containsAll([
          'PlaylistMedia',
          'PlaylistItem',
          'PlaylistItemChild',
          'TagMap',
        ]),
      );
      expect(jsonEncode(records), contains('Marker'));
      expect(output.archive.findFile('clip.mp4')!.content, clip);
      expect(output.archive.findFile('poster.jpg')!.content, poster);
    },
  );

  test('reports legacy playlists when merging with a modern backup', () async {
    final legacy = writeBackup(
      scratch,
      'legacy-playlist',
      version: 8,
      prepare: (db) {
        addDocument(db, 1, 900);
        db.execute('INSERT INTO PlaylistMedia VALUES (1, 1, NULL, NULL, 1)');
        db.execute(
          "INSERT INTO PlaylistItem VALUES (1, 'Legacy', 0, NULL, NULL, 0, NULL, 1)",
        );
      },
    );
    final modern = writeBackup(scratch, 'modern-backup', prepare: (_) {});

    final result = await mergeArchives([modern, legacy], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      result.warnings.map((warning) => warning.code),
      contains('unresolvedLinks'),
    );
    expectOnlyJwLibraryEntries(output.archive);
    final report = recoveryReport(result)!;
    final records = report['unresolvedRecords'] as List<dynamic>;
    expect(
      records,
      contains(
        isA<Map<String, dynamic>>()
            .having(
              (entry) => entry['fileName'],
              'fileName',
              'legacy-playlist.jwlibrary',
            )
            .having((entry) => entry['table'], 'table', 'PlaylistItem'),
      ),
    );
  });

  test('reads committed WAL rows alongside the main database', () async {
    final wal = writeBackup(
      scratch,
      'wal',
      wal: true,
      prepare: (db) {
        addDocument(db, 1, 701);
        note(db, id: 1, guid: 'wal-note', location: 1, body: 'saved in WAL');
      },
    );
    final second = writeBackup(
      scratch,
      'second',
      prepare: (db) {
        addDocument(db, 1, 702);
        note(
          db,
          id: 1,
          guid: 'other-note',
          location: 1,
          body: 'saved in main DB',
        );
      },
    );

    final result = await mergeArchives([wal, second], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      output.db
          .select('SELECT Guid FROM Note ORDER BY Guid')
          .map((row) => row['Guid']),
      ['other-note', 'wal-note'],
    );
  });
  test(
    'keeps primary bookmark slots and over 100 favorites in primary order',
    () async {
      final primary = writeBackup(
        scratch,
        'older-primary',
        date: _earlier,
        prepare: (db) {
          db.execute('BEGIN IMMEDIATE');
          addDocument(db, 900, 9000);
          addDocument(db, 901, 9001);
          bookmark(
            db,
            id: 1,
            location: 901,
            publication: 900,
            slot: 7,
            title: 'Primary slot seven',
          );
          db.execute(
            "INSERT INTO Tag(TagId,Type,Name) VALUES(1,0,'Favorites')",
          );
          for (var position = 0; position < 120; position++) {
            final document = 1000 + 119 - position;
            addDocument(db, position + 1, document);
            db.execute('INSERT INTO TagMap VALUES(?,NULL,?,NULL,1,?)', [
              position + 1,
              position + 1,
              position,
            ]);
          }
          db.execute('COMMIT');
        },
      );
      final newer = writeBackup(
        scratch,
        'newer-extra',
        date: _later,
        prepare: (db) {
          db.execute('BEGIN IMMEDIATE');
          addDocument(db, 900, 9000);
          addDocument(db, 901, 9002);
          bookmark(
            db,
            id: 1,
            location: 901,
            publication: 900,
            slot: 7,
            title: 'Secondary slot seven',
          );
          db.execute(
            "INSERT INTO Tag(TagId,Type,Name) VALUES(1,0,'Favorites')",
          );
          for (var position = 0; position < 140; position++) {
            addDocument(db, position + 1, 1000 + position);
            db.execute('INSERT INTO TagMap VALUES(?,NULL,?,NULL,1,?)', [
              position + 1,
              position + 1,
              position,
            ]);
          }
          db.execute('COMMIT');
        },
      );
      final result = await mergeArchives(
        [newer, primary],
        (_) {},
        options: MergeOptions(primaryPath: primary),
      );
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(
        output.db
            .select(
              "SELECT Slot FROM Bookmark WHERE Title='Primary slot seven'",
            )
            .single['Slot'],
        7,
      );
      expect(output.db.select('SELECT * FROM Bookmark'), hasLength(2));
      expect(
        output.db
            .select('SELECT count(DISTINCT Slot) AS n FROM Bookmark')
            .single['n'],
        2,
      );
      expect(
        output.db
            .select('''
      SELECT DocumentId FROM TagMap JOIN Tag USING(TagId) JOIN Location USING(LocationId)
      WHERE Tag.Type=0 ORDER BY Position
    ''')
            .map((row) => row['DocumentId']),
        [
          for (var i = 119; i >= 0; i--) 1000 + i,
          for (var i = 120; i < 140; i++) 1000 + i,
        ],
      );
      expect(result.counts['Favorite'], 140);
      expect(result.primaryFileName, 'older-primary.jwlibrary');
      expect(result.options.primaryPath, primary);
      expect(result.options.notePolicy, NoteConflictPolicy.newest);
      expect(result.options.fieldPolicy, FieldConflictPolicy.primary);
      expect(result.options.languageCode, 'ru');
    },
  );

  for (final policy in NoteConflictPolicy.values) {
    test(
      'applies note policy ${policy.name} independently of primary archive age',
      () async {
        final primary = writeBackup(
          scratch,
          'primary-note',
          date: _earlier,
          prepare: (db) {
            addDocument(db, 1, 301);
            note(
              db,
              id: 1,
              guid: 'shared-note',
              location: 1,
              body: 'Primary text',
              date: _earlier,
            );
          },
        );
        final newer = writeBackup(
          scratch,
          'newer-note',
          date: _later,
          prepare: (db) {
            addDocument(db, 8, 301);
            note(
              db,
              id: 9,
              guid: 'shared-note',
              location: 8,
              body: 'Newest text',
              date: _later,
            );
          },
        );
        final result = await mergeArchives(
          [newer, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary, notePolicy: policy),
        );
        final output = readOutput(scratch, result.archivePath, version: 16);
        expect(
          output.db.select('SELECT Content FROM Note').single['Content'],
          policy == NoteConflictPolicy.primary ? 'Primary text' : 'Newest text',
        );
        expect(result.noteConflicts, 1);
      },
    );
  }

  test(
    'defaults to newest note text when an older primary is selected',
    () async {
      final primary = writeBackup(
        scratch,
        'default-primary',
        date: _earlier,
        prepare: (db) {
          note(
            db,
            id: 1,
            guid: 'unattached',
            location: null,
            body: 'Earlier',
            date: _earlier,
          );
        },
      );
      final newer = writeBackup(
        scratch,
        'default-newer',
        date: _later,
        prepare: (db) {
          note(
            db,
            id: 1,
            guid: 'unattached',
            location: null,
            body: 'Later',
            date: _later,
          );
        },
      );
      final result = await mergeArchives(
        [primary, newer],
        (_) {},
        options: MergeOptions(primaryPath: primary),
      );
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(
        output.db.select('SELECT Content FROM Note').single['Content'],
        'Later',
      );
    },
  );

  for (final policy in FieldConflictPolicy.values) {
    test(
      'applies field policy ${policy.name} while keeping primary bookmark slots',
      () async {
        String make(String name, String date, String value) => writeBackup(
          scratch,
          name,
          date: date,
          prepare: (db) {
            addDocument(db, 1, 301);
            addDocument(db, 2, 302);
            addDocument(db, 3, 300);
            db.execute("INSERT INTO InputField VALUES(1,'question',?)", [
              value,
            ]);
            bookmark(
              db,
              id: 1,
              location: name == 'primary-field' ? 1 : 2,
              publication: 3,
              slot: 4,
              title: name,
            );
          },
        );
        final primary = make('primary-field', _earlier, 'Primary answer');
        final newer = make('newer-field', _later, 'Latest backup answer');
        final result = await mergeArchives(
          [newer, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary, fieldPolicy: policy),
        );
        final output = readOutput(scratch, result.archivePath, version: 16);
        expect(
          output.db.select('SELECT Value FROM InputField').single['Value'],
          policy == FieldConflictPolicy.primary
              ? 'Primary answer'
              : 'Latest backup answer',
        );
        expect(
          output.db
              .select("SELECT Slot FROM Bookmark WHERE Title='primary-field'")
              .single['Slot'],
          4,
        );
        expect(result.fieldConflicts, 1);
      },
    );
  }

  test('lists each overflow bookmark with its publication, slot, source and reason in TXT', () async {
    final primary = writeBackup(
      scratch,
      'full-primary',
      date: _earlier,
      prepare: (db) {
        addDocument(db, 100, 900);
        db.execute(
          "UPDATE Location SET Title='Synthetic publication' WHERE LocationId=100",
        );
        for (var slot = 0; slot < 10; slot++) {
          addDocument(db, slot + 1, 1000 + slot);
          bookmark(
            db,
            id: slot + 1,
            location: slot + 1,
            publication: 100,
            slot: slot,
            title: 'Kept primary $slot',
          );
        }
      },
    );
    final extra = writeBackup(
      scratch,
      'overflow-source',
      date: _later,
      prepare: (db) {
        addDocument(db, 100, 900);
        db.execute(
          "UPDATE Location SET Title='Synthetic publication' WHERE LocationId=100",
        );
        for (var slot = 2; slot <= 3; slot++) {
          addDocument(db, slot, 2000 + slot);
          bookmark(
            db,
            id: slot,
            location: slot,
            publication: 100,
            slot: slot,
            title: 'Overflow bookmark $slot',
          );
        }
      },
    );
    final result = await mergeArchives(
      [extra, primary],
      (_) {},
      options: MergeOptions(primaryPath: primary),
    );
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(output.db.select('SELECT * FROM Bookmark'), hasLength(10));
    expect(result.skippedBookmarks, 2);
    final text = await File(result.reportPath).readAsString();
    for (final title in ['Overflow bookmark 2', 'Overflow bookmark 3']) {
      expect(text, contains(title));
    }
    expect(text, contains('Synthetic publication'));
    expect(text, contains('overflow-source.jwlibrary'));
    expect(text, matches(RegExp(r'Slot:\s*2(?:\r?\n|$)')));
    expect(text, matches(RegExp(r'Slot:\s*3(?:\r?\n|$)')));
    expect(
      text.toLowerCase(),
      matches(RegExp(r'позиц|слот|мест|slot|position')),
    );
    expect(
      text.toLowerCase(),
      matches(
        RegExp(
          r'занят|нет свобод|лимит|переполн|полны|no free|occupied|capacity|full',
        ),
      ),
    );
  });

  for (final language in ['ru', 'en']) {
    test(
      'writes a readable $language TXT summary and selected rules for a clean merge',
      () async {
        final primary = writeBackup(
          scratch,
          'summary-primary',
          date: _earlier,
          prepare: (db) {
            addDocument(db, 1, 301);
            note(db, id: 1, guid: 'summary-note-a', location: 1, body: 'One');
          },
        );
        final extra = writeBackup(
          scratch,
          'summary-extra',
          date: _later,
          prepare: (db) {
            addDocument(db, 1, 302);
            note(db, id: 1, guid: 'summary-note-b', location: 1, body: 'Two');
          },
        );
        final result = await mergeArchives(
          [extra, primary],
          (_) {},
          options: MergeOptions(primaryPath: primary, languageCode: language),
        );
        readOutput(scratch, result.archivePath, version: 16);
        expect(result.warnings, isEmpty);
        expect(result.reportPath.toLowerCase(), endsWith('.txt'));
        final text = await File(result.reportPath).readAsString();
        expect(text, contains('summary-primary.jwlibrary'));
        expect(text, contains('summary-extra.jwlibrary'));
        expect(text, contains('16'));
        expect(text, contains('2'));
        final lower = text.toLowerCase();
        if (language == 'en') {
          expect(lower, matches(RegExp(r'notes:\s*2(?:\r?\n|$)')));
          expect(lower, contains('primary'));
          expect(lower, matches(RegExp(r'newest|latest|recent')));
          expect(lower, isNot(contains('замет')));
        } else {
          expect(lower, matches(RegExp(r'заметки:\s*2(?:\r?\n|$)')));
          expect(lower, matches(RegExp(r'основн|главн')));
          expect(lower, matches(RegExp(r'нов|последн')));
        }
      },
    );
  }
  test(
    'keeps warning summaries bounded while reporting a large damaged workload',
    () async {
      const rows = 6000;
      final damaged = writeBackup(
        scratch,
        'large-damaged',
        version: 16,
        allowBrokenReferences: true,
        prepare: (db) {
          db.execute('BEGIN');
          for (var id = 1; id <= rows; id++) {
            note(
              db,
              id: id,
              guid: 'damaged-$id',
              location: 999999,
              body: 'Recoverable synthetic text $id',
            );
            db.execute('UPDATE Note SET Title=? WHERE NoteId=?', [
              'Large workload note $id',
              id,
            ]);
          }
          db.execute('COMMIT');
        },
      );
      final clean = writeBackup(scratch, 'large-clean', prepare: (_) {});
      final result = await mergeArchives([damaged, clean], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(result.counts['Note'], rows);
      expect(
        output.db
            .select('SELECT count(*) AS n FROM Note WHERE LocationId IS NULL')
            .single['n'],
        rows,
      );
      expect(result.warnings.length, lessThanOrEqualTo(4));
      expect(
        result.warnings
            .where((warning) => warning.code == 'unresolvedLinks')
            .fold<int>(0, (total, warning) => total + warning.count),
        rows,
      );
      final text = await File(result.reportPath).readAsString();
      expect(text, contains('Large workload note 1'));
      expect(text, contains('Large workload note $rows'));
      expect(text, contains('large-damaged.jwlibrary'));
      expect(text, contains('$rows'));
      expectOnlyJwLibraryEntries(output.archive);
      final report = recoveryReport(result)!;
      expect(report['unresolvedRecords'], hasLength(rows));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('an ambiguous location is reported instead of stopping the merge', () async {
    const insert =
        'INSERT INTO Location(LocationId, BookNumber, ChapterNumber, DocumentId, Track, KeySymbol, MepsLanguage, Type) VALUES (?, ?, ?, ?, ?, ?, 0, 0)';
    final first = writeBackup(
      scratch,
      'two-places',
      version: 16,
      date: _later,
      prepare: (db) {
        db.execute(insert, [1, 1, 1, 7, null, 'nwtsty']);
        db.execute(insert, [2, null, null, 8, 2, 'nwtsty']);
      },
    );
    final second = writeBackup(
      scratch,
      'both-places',
      version: 16,
      prepare: (db) {
        db.execute(insert, [1, 1, 1, 8, 2, 'nwtsty']);
        note(db, id: 1, guid: 'kept-note', location: 1, body: 'kept text');
      },
    );
    final result = await mergeArchives([first, second], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(
      output.db.select('SELECT Content FROM Note').map((row) => row['Content']),
      ['kept text'],
    );
    expect(
      result.warnings.map((warning) => warning.code),
      contains('unresolvedLinks'),
    );
    expectOnlyJwLibraryEntries(output.archive);
    final report = recoveryReport(result)!;
    expect(
      (report['unresolvedRecords'] as List).map((record) => record['reason']),
      contains('ambiguousLocation'),
    );
    File(result.archivePath).parent.deleteSync(recursive: true);
  });
}
