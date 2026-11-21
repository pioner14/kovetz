import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:backup_merge/merge.dart';
import 'package:backup_merge/notes_export.dart' show PdfFonts;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const fixtureEarlier = '2025-01-01T10:00:00Z';
const fixtureLater = '2025-02-01T10:00:00Z';

String writeBackup(
  Directory scratch,
  String name, {
  int version = 14,
  String date = fixtureEarlier,
  bool wal = false,
  bool allowBrokenReferences = false,
  bool verifyForeignKeys = true,
  Map<String, List<int>> media = const {},
  required void Function(Database) prepare,
}) {
  final dir = Directory('${scratch.path}/$name')..createSync();
  final databaseName = version == 8 ? 'user_data.db' : 'userData.db';
  final path = '${dir.path}/$databaseName';
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA foreign_keys = ${allowBrokenReferences ? "OFF" : "ON"}');
    // Build synthetic schema atomically; individual DDL fsyncs make the
    // suite depend on disk contention rather than merge correctness.
    db.execute('BEGIN IMMEDIATE');
    for (final filename in [
      if (version != 5) 'shared.sql',
      'v${version >= 14 ? 14 : version}.sql',
      if (version == 16) 'v16.sql',
    ]) {
      for (final sql in File(
        'test/fixtures/$filename',
      ).readAsStringSync().split(';')) {
        if (sql.trim().isNotEmpty) db.execute(sql);
      }
    }
    db.execute('PRAGMA user_version = $version');
    db.execute('INSERT INTO LastModified VALUES (?)', [date]);
    db.execute('COMMIT');
    if (wal) {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA wal_autocheckpoint = 0');
    }
    prepare(db);
    if (verifyForeignKeys) {
      expect(
        db.select('PRAGMA foreign_key_check'),
        allowBrokenReferences ? isNotEmpty : isEmpty,
      );
    }

    final database = File(path).readAsBytesSync();
    final manifest = utf8.encode(
      jsonEncode({
        'name': name,
        'creationDate': date,
        'version': 1,
        'type': 0,
        'userDataBackup': {
          'databaseName': databaseName,
          'schemaVersion': version,
          'deviceName': 'Synthetic device',
          'lastModifiedDate': date,
          'hash': sha256.convert(database).toString(),
        },
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile(databaseName, database.length, database))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    if (wal) {
      final walBytes = File('$path-wal').readAsBytesSync();
      expect(walBytes.length, greaterThan(32));
      archive.addFile(
        ArchiveFile('$databaseName-wal', walBytes.length, walBytes),
      );
    }
    for (final entry in media.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final file = File('${scratch.path}/$name.jwlibrary');
    file.writeAsBytesSync(ZipEncoder().encode(archive));
    return file.path;
  } finally {
    db.close();
  }
}

({Database db, Archive archive}) readOutput(
  Directory scratch,
  String path, {
  required int version,
}) {
  final file = File(path);
  // Register cleanup before any assertion about the returned archive can fail.
  addTearDown(() async {
    if (await file.parent.exists()) await file.parent.delete(recursive: true);
  });
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  final manifest = jsonDecode(
    utf8.decode(archive.findFile('manifest.json')!.content),
  ) as Map<String, dynamic>;
  final metadata = manifest['userDataBackup'] as Map<String, dynamic>;
  expect(metadata['schemaVersion'], version);
  final dbFile = archive.findFile(metadata['databaseName'] as String)!;
  expect(metadata['hash'], sha256.convert(dbFile.content).toString());
  final out = File('${scratch.path}/output.db')
    ..writeAsBytesSync(dbFile.content);
  final db = sqlite3.open(out.path, mode: OpenMode.readOnly);
  addTearDown(db.close);
  expect(db.select('PRAGMA user_version').single.values.single, version);
  expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
  expect(db.select('PRAGMA foreign_key_check'), isEmpty);
  return (db: db, archive: archive);
}

void addDocument(Database db, int id, int document) {
  db.execute(
    '''
    INSERT INTO Location(LocationId, DocumentId, KeySymbol, MepsLanguage, Type)
    VALUES (?, ?, 'test', 0, 0)
  ''',
    [id, document],
  );
}

void publication(Database db) => addDocument(db, 9, 100);

void note(
  Database db, {
  required int id,
  required String guid,
  required int? location,
  required String body,
  String date = fixtureEarlier,
}) {
  db.execute(
    '''
    INSERT INTO Note (NoteId, Guid, LocationId, Content, LastModified)
    VALUES (?, ?, ?, ?, ?)
  ''',
    [id, guid, location, body, date],
  );
}

void highlight(Database db, String guid, int location) {
  db.execute('INSERT INTO UserMark VALUES (1, 2, ?, 0, ?, 1)', [
    location,
    guid,
  ]);
  db.execute('INSERT INTO BlockRange VALUES (1, 1, ?, 0, 5, 1)', [location]);
}

void studyData(
  Database db, {
  required String bookmarkTitle,
  required String fieldValue,
}) {
  db.execute("INSERT INTO Tag VALUES (1, 1, 'Study'), (2, 0, 'Favorites')");
  db.execute('INSERT INTO TagMap VALUES (3, NULL, 1, NULL, 2, 0)');
  db.execute("INSERT INTO InputField VALUES (1, 'question', ?)", [fieldValue]);
  db.execute(
    '''
    INSERT INTO Bookmark (BookmarkId, LocationId, PublicationLocationId, Slot, Title)
    VALUES (1, 1, 9, 0, ?)
  ''',
    [bookmarkTitle],
  );
}

void playlist(
  Database db, {
  required int document,
  required String name,
  required List<int> bytes,
  required String thumbnail,
  required int verse,
}) {
  addDocument(db, 1, document);
  final hash = sha256.convert(bytes).toString();
  db.execute(
    "INSERT INTO PlaylistItemAccuracy VALUES (1, 'Accurate'), (2, 'NeedsUserVerification')",
  );
  db.execute(
    "INSERT INTO IndependentMedia VALUES (1, 'clip.mp4', 'clip.mp4', 'video/mp4', ?)",
    [hash],
  );
  if (thumbnail != 'clip.mp4') {
    db.execute(
      "INSERT INTO IndependentMedia VALUES (2, ?, ?, 'video/mp4', ?)",
      [thumbnail, thumbnail, hash],
    );
  }
  db.execute(
    '''
    INSERT INTO PlaylistItem (PlaylistItemId, Label, Accuracy, EndAction, ThumbnailFilePath)
    VALUES (1, ?, 1, 0, ?)
  ''',
    [name, thumbnail],
  );
  db.execute('INSERT INTO PlaylistItemIndependentMediaMap VALUES (1, 1, 200)');
  db.execute('INSERT INTO PlaylistItemLocationMap VALUES (1, 1, 1, 200)');
  db.execute("INSERT INTO PlaylistItemMarker VALUES (1, 1, 'Part', 0, 200, 0)");
  db.execute('INSERT INTO PlaylistItemMarkerBibleVerseMap VALUES (1, ?)', [
    verse,
  ]);
  db.execute('INSERT INTO PlaylistItemMarkerParagraphMap VALUES (1, ?, 5, 1)', [
    document,
  ]);
  db.execute("INSERT INTO Tag VALUES (1, 2, 'Playlist')");
  db.execute('INSERT INTO TagMap VALUES (1, 1, NULL, NULL, 1, 0)');
}

void bookmark(
  Database db, {
  required int id,
  required int location,
  required int publication,
  required int slot,
  required String title,
}) {
  db.execute(
    'INSERT INTO Bookmark(BookmarkId,LocationId,PublicationLocationId,Slot,Title) VALUES(?,?,?,?,?)',
    [id, location, publication, slot, title],
  );
}

/// Machine report written beside [result], or null when nothing was reported.
Map<String, dynamic>? recoveryReport(MergeResult result) {
  final path = result.recoveryReportPath;
  if (path == null) return null;
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

/// Rewrites [result]'s archive as versions up to 0.4.2 stored it, with the
/// machine report inside. Such results exist on users' devices, and importing
/// their history must keep working.
void embedReportLikeOldVersions(MergeResult result) {
  final report = recoveryReport(result);
  if (report == null) return;
  final file = File(result.archivePath);
  final zip = ZipDecoder().decodeBytes(file.readAsBytesSync());
  final bytes = utf8.encode(jsonEncode(report));
  zip.addFile(ArchiveFile('recovery-report.json', bytes.length, bytes));
  file.writeAsBytesSync(ZipEncoder().encode(zip));
}

/// The only entries a JW Library archive may contain: anything else makes
/// JW Library reject the restore as damaged data.
void expectOnlyJwLibraryEntries(Archive archive) {
  for (final entry in archive.files) {
    expect(
      entry.name,
      isNot(anyOf(startsWith('recovery-'), endsWith('-journal'))),
      reason: 'JW Library rejects archives with extra files.',
    );
  }
}

/// Bundled PDF fonts, read from the asset folder (tests run from `app/`).
PdfFonts bundledPdfFonts() {
  Uint8List read(String name) => File('assets/fonts/$name').readAsBytesSync();
  return PdfFonts(
    serif: read('NotoSerif-Regular.ttf'),
    serifBold: read('NotoSerif-Bold.ttf'),
    serifItalic: read('NotoSerif-Italic.ttf'),
    sans: read('NotoSans-Regular.ttf'),
    sansBold: read('NotoSans-Bold.ttf'),
    fallbacks: [
      read('NotoSansArmenian-Regular.ttf'),
      read('NotoSansHebrew-Regular.ttf'),
    ],
  );
}

void _location(Database db, int id, Map<String, Object?> values) {
  final row = {'LocationId': id, 'Type': 0, 'MepsLanguage': 0, ...values};
  db.execute(
    'INSERT INTO Location (${row.keys.join(', ')}) '
    'VALUES (${List.filled(row.length, '?').join(', ')})',
    row.values.toList(),
  );
}

void _addNote(
  Database db,
  int id,
  String title,
  String content, {
  int? location,
  int blockType = 0,
  int? block,
  String date = fixtureEarlier,
}) => db.execute(
  'INSERT INTO Note (NoteId, Guid, LocationId, Title, Content, '
  'LastModified, Created, BlockType, BlockIdentifier) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [id, 'guid-$id', location, title, content, date, date, blockType, block],
);

void _tag(Database db, int id, int type, String name) =>
    db.execute('INSERT INTO Tag VALUES (?, ?, ?)', [id, type, name]);

var _tagLink = 0;
void _tagNote(Database db, int tag, int note) => db.execute(
  'INSERT INTO TagMap (TagMapId, NoteId, TagId, Position) VALUES (?, ?, ?, ?)',
  [++_tagLink, note, tag, _tagLink],
);

/// A backup with Bible and publication notes, tags of every kind and one
/// untagged note, for the notes export tests.
String writeNotesBackup(Directory scratch) => writeBackup(
  scratch,
  'notes',
  version: 16,
  prepare: (db) {
    _location(db, 1, {
      'BookNumber': 45,
      'ChapterNumber': 15,
      'KeySymbol': 'nwtsty',
    });
    _location(db, 2, {
      'BookNumber': 19,
      'ChapterNumber': 23,
      'KeySymbol': 'nwtsty',
    });
    _location(db, 3, {
      'DocumentId': 1991123,
      'KeySymbol': 'w',
      'IssueTagNumber': 19910215,
      'Title': 'Соответствующий выкуп для всех',
    });
    _addNote(
      db,
      1,
      'Надежда',
      'Бог надежды',
      location: 1,
      blockType: 2,
      block: 13,
    );
    _addNote(
      db,
      2,
      'Пастух: "Иегова"',
      'Строка 1\nСтрока 2',
      location: 2,
      blockType: 2,
      block: 1,
    );
    _addNote(
      db,
      3,
      'Выкуп',
      'Мысль из статьи',
      location: 3,
      blockType: 1,
      block: 3,
    );
    _addNote(db, 4, 'Без тега', 'Свободная заметка');
    _addNote(db, 5, '', '');
    _tag(db, 10, 1, 'Ободрение');
    _tag(db, 11, 1, 'english');
    _tag(db, 12, 1, 'English');
    _tag(db, 13, 2, 'Плейлист');
    _tagNote(db, 10, 1);
    _tagNote(db, 11, 1);
    _tagNote(db, 10, 2);
    _tagNote(db, 12, 3);
    _tagNote(db, 13, 3);
  },
);

/// Invented notes for screenshots and the guide's sample PDF.
String writeGuideBackup(
  Directory scratch, {
  required String name,
  required String languageCode,
  String date = '2026-11-20T10:00:00Z',
  int firstNote = 0,
}) {
  final russian = languageCode == 'ru';
  final tags = russian
      ? ['Ободрение', 'Служение', 'Семья']
      : ['Encouragement', 'Ministry', 'Family'];
  final notes = [
    (
      45,
      15,
      13,
      0,
      'Надежда',
      'Hope',
      'Нужно вспомнить в служении.',
      'Remember this in the ministry.',
    ),
    (
      19,
      23,
      1,
      0,
      'Поддержка',
      'Support',
      'Поделиться с тем, кто сейчас переживает трудности.',
      'Share with someone going through a hard time.',
    ),
    (
      20,
      15,
      1,
      2,
      'Спокойный ответ',
      'A calm answer',
      'Попробовать сначала выслушать собеседника.',
      'Try listening before replying.',
    ),
    (
      51,
      4,
      6,
      1,
      'Добрые слова',
      'Kind words',
      'Подготовить простой вопрос для разговора.',
      'Prepare a simple question for a conversation.',
    ),
    (
      50,
      4,
      6,
      0,
      'Минута тишины',
      'A quiet moment',
      'Выделить немного времени на размышление.',
      'Set aside a little time to reflect.',
    ),
    (
      49,
      4,
      32,
      2,
      'Забота дома',
      'Care at home',
      'Обсудить, как помочь друг другу на этой неделе.',
      'Talk about how to help each other this week.',
    ),
    (
      59,
      1,
      19,
      1,
      'Внимательно слушать',
      'Listen carefully',
      'Дать человеку время закончить мысль.',
      'Give the other person time to finish their thought.',
    ),
    (
      19,
      46,
      1,
      0,
      'Ободряющая мысль',
      'An encouraging thought',
      'Вспомнить перед звонком другу.',
      'Remember this before calling a friend.',
    ),
    (
      46,
      13,
      4,
      2,
      'Терпение',
      'Patience',
      'Подумать, где сегодня можно проявить терпение.',
      'Think of where to show patience today.',
    ),
    (
      40,
      5,
      16,
      1,
      'Маленькие дела',
      'Small acts',
      'Заранее подумать, кому предложить помощь.',
      'Think ahead about whom to offer help.',
    ),
    (
      58,
      10,
      24,
      0,
      'Встреча с другом',
      'Meeting a friend',
      'Спросить, как прошла неделя.',
      'Ask how the week went.',
    ),
    (
      19,
      119,
      105,
      null,
      'План чтения',
      'Reading plan',
      'Вернуться к этой главе в выходные.',
      'Come back to this chapter at the weekend.',
    ),
  ];
  return writeBackup(
    scratch,
    name,
    version: 16,
    date: date,
    prepare: (db) {
      for (final (index, tag) in tags.indexed) {
        _tag(db, index + 1, 1, tag);
      }
      for (var index = firstNote; index < notes.length; index++) {
        final (book, chapter, verse, tag, ruTitle, enTitle, ruText, enText) =
            notes[index];
        final id = index + 1;
        _location(db, id, {
          'BookNumber': book,
          'ChapterNumber': chapter,
          'KeySymbol': 'nwtsty',
        });
        _addNote(
          db,
          id,
          russian ? ruTitle : enTitle,
          russian ? ruText : enText,
          location: id,
          blockType: 2,
          block: verse,
          date: DateTime.utc(
            2026,
            index < 6 ? 10 : 11,
            10 + index % 6,
            10,
          ).toIso8601String(),
        );
        if (tag != null) {
          db.execute(
            'INSERT INTO TagMap (TagMapId, NoteId, TagId, Position) '
            'VALUES (?, ?, ?, ?)',
            [id, id, tag + 1, index],
          );
        }
      }
      if (firstNote == 0) {
        highlight(db, 'guide-highlight', 1);
        addDocument(db, 100, 100);
        bookmark(
          db,
          id: 1,
          location: 1,
          publication: 100,
          slot: 0,
          title: russian ? 'Надежда' : 'Hope',
        );
      }
    },
  );
}

/// Removes a test folder. On Windows a file still being written by a widget
/// test's background save cannot be deleted yet; leftovers sit in the ignored
/// `.work/test-runs` folder and do not matter.
Future<void> deleteScratch(Directory scratch) async {
  try {
    await scratch.delete(recursive: true);
  } on FileSystemException {
    // Still open on Windows; harmless.
  }
}
