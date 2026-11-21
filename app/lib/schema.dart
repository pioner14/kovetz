import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'schema_validation.dart';
import 'src/schema_v16_grdb.dart';
import 'src/sqlite_utils.dart';

const currentSchemaVersion = 16;
const supportedSchemaVersions = {5, 8, 14, 16};

/// A temporary, normalized copy and records the current schema cannot express.
class NormalizedSchema {
  const NormalizedSchema(this.db, this.issues);

  final Database db;

  /// JSON-ready source rows for the merge report. Never log their contents.
  final List<Map<String, Object?>> issues;
}

class SchemaFailure implements Exception {
  const SchemaFailure(this.code, [this.table]);

  final String code;
  final String? table;

  @override
  String toString() => code;
}

void validateSourceSchema(Database source, int version) {
  try {
    validateSchemaContract(source, version);
  } on SchemaContractFailure catch (error) {
    throw SchemaFailure('unsupportedSchema', error.table);
  }
}

/// Creates the Android schema observed in a fresh JW Library v16 backup.
/// Each statement is bundled separately so trigger bodies keep their semicolons.
void createCurrentSchema(Database db, {bool installTriggers = true}) {
  for (final sql in [..._tableDefinitions, ..._indexDefinitions]) {
    db.execute(sql);
  }
  db.execute('PRAGMA user_version = 16');
  db.execute('INSERT INTO LastModified VALUES (?)', [
    DateTime.now().toUtc().toIso8601String(),
  ]);
  db.execute('INSERT INTO PlaylistItemAccuracy VALUES (1, ?), (2, ?)', [
    'Accurate',
    'NeedsUserVerification',
  ]);
  db.execute("INSERT INTO android_metadata VALUES ('en')");
  if (installTriggers) installCurrentSchemaTriggers(db);
}

/// Installs the original v16 LastModified protection and maintenance triggers.
void installCurrentSchemaTriggers(Database db) {
  for (final sql in _triggerDefinitions) {
    db.execute(sql);
  }
}

/// The two v16 schemas JW Library writes. [grdb] is used by newer apps that
/// record migrations in grdb_migrations; a device restores only the variant
/// its app expects.
enum OutputSchema { legacy, grdb }

/// Migration identifiers of the bundled GRDB schema.
const knownGrdbMigrations = grdbMigrations;

final _localePattern = RegExp(r'^[a-z]{2,3}(_[A-Z]{2})?$');

/// Creates the merged database in [variant], without triggers; call
/// [installOutputTriggers] after the data is written.
void createOutputSchema(Database db, OutputSchema variant, {String? locale}) {
  if (variant == OutputSchema.legacy) {
    createCurrentSchema(db, installTriggers: false);
  } else {
    for (final sql in [...grdbTableDefinitions, ...grdbIndexDefinitions]) {
      db.execute(sql);
    }
    db.execute('PRAGMA user_version = 16');
    for (final migration in grdbMigrations) {
      db.execute('INSERT INTO grdb_migrations VALUES (?)', [migration]);
    }
    db.execute('INSERT INTO LastModified VALUES (?)', [
      formatJwTimestamp(DateTime.now()),
    ]);
    db.execute('INSERT INTO PlaylistItemAccuracy VALUES (1, ?), (2, ?)', [
      'Accurate',
      'NeedsUserVerification',
    ]);
    db.execute('INSERT INTO android_metadata VALUES (?)', ['en']);
  }
  if (locale != null && _localePattern.hasMatch(locale)) {
    db.execute('UPDATE android_metadata SET locale = ?', [locale]);
  }
}

/// Installs the maintenance triggers of [variant].
void installOutputTriggers(Database db, OutputSchema variant) {
  if (variant == OutputSchema.legacy) {
    installCurrentSchemaTriggers(db);
  } else {
    for (final sql in grdbTriggerDefinitions) {
      db.execute(sql);
    }
  }
}

/// Timestamp in the form JW Library writes: UTC, whole seconds, `Z`.
String formatJwTimestamp(DateTime time) =>
    '${time.toUtc().toIso8601String().substring(0, 19)}Z';

/// Copies an extracted database into a separate current-format database.
///
/// Foreign keys remain disabled during normalization. Orphaned references are
/// intentionally retained for the caller's explicit validation and reporting.
NormalizedSchema normalizeSchema(
  Database source,
  int sourceVersion,
  String destinationPath,
) {
  if (!supportedSchemaVersions.contains(sourceVersion)) {
    throw const SchemaFailure('unsupportedSchema');
  }
  validateSourceSchema(source, sourceVersion);
  final db = sqlite3.open(destinationPath);
  final issues = <Map<String, Object?>>[];
  try {
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('BEGIN IMMEDIATE');
    createCurrentSchema(db, installTriggers: false);
    final sourceTables = source
        .select("SELECT name FROM sqlite_schema WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    final expected = {
      ..._commonTables,
      if (sourceVersion >= 8) 'InputField',
      if (sourceVersion == 8) ..._legacyPlaylistTables,
      if (sourceVersion >= 14) ..._modernPlaylistTables,
      'LastModified',
    };
    if (!sourceTables.containsAll(expected)) {
      throw const SchemaFailure('unsupportedSchema');
    }

    void retain(String code, String table, Map<String, Object?> row) {
      issues.add({'code': code, 'table': table, 'record': Map.of(row)});
    }

    for (final table in _commonTables) {
      if (table == 'TagMap') continue;
      final targetColumns = db
          .select('PRAGMA table_info("$table")')
          .map((row) => row['name'] as String)
          .toSet();
      for (final record in streamRows(source, 'SELECT * FROM "$table"')) {
        final row = Map<String, Object?>.of(record);
        if (table == 'Tag' && row.containsKey('ImageFilename')) {
          final image = row.remove('ImageFilename');
          if (image != null) retain('legacyTagImage', table, record);
        }
        if (table == 'Note' && !row.containsKey('Created')) {
          // Old backups do not record creation time. LastModified is the only
          // per-note timestamp available, so the caller can preserve it.
          row['Created'] = row['LastModified'];
        }
        if (!targetColumns.containsAll(row.keys)) {
          throw const SchemaFailure('unsupportedSchema');
        }
        insertRow(db, table, row);
      }
    }

    if (sourceTables.contains('InputField')) {
      _copyTable(source, db, 'InputField');
    }
    if (sourceVersion >= 14) {
      db.execute('DELETE FROM PlaylistItemAccuracy');
      for (final table in _modernPlaylistTables) {
        _copyTable(source, db, table);
      }
    } else if (sourceVersion == 8) {
      for (final table in _legacyPlaylistTables) {
        for (final row in streamRows(source, 'SELECT * FROM "$table"')) {
          retain('legacyPlaylist', table, row);
        }
      }
    }

    final tagPositions = <int, int>{};
    final tagTargets = <String>{};
    final links = streamRows(
      source,
      'SELECT * FROM TagMap ORDER BY TagId, Position, TagMapId',
    );
    for (final record in links) {
      final row = Map<String, Object?>.of(record);
      if (sourceVersion == 5) {
        final type = row.remove('Type');
        final target = row.remove('TypeId');
        row.addAll({
          'PlaylistItemId': null,
          'LocationId': type == 0 ? target : null,
          'NoteId': type == 1 ? target : null,
        });
        if (type != 0 && type != 1) {
          retain('unknownTagTarget', 'TagMap', record);
          continue;
        }
      } else if (sourceVersion == 8 && row['PlaylistItemId'] != null) {
        retain('legacyPlaylist', 'TagMap', record);
        continue;
      }
      final tag = row['TagId'] as int;
      final key = jsonEncode([
        tag,
        row['PlaylistItemId'],
        row['LocationId'],
        row['NoteId'],
      ]);
      if (!tagTargets.add(key)) {
        final item = row['PlaylistItemId'];
        if (sourceVersion >= 14 &&
            item is int &&
            db.select('SELECT 1 FROM PlaylistItem WHERE PlaylistItemId = ?', [
              item,
            ]).isNotEmpty) {
          // Older supported schemas permit multiple positions pointing to one
          // item. Our output requires distinct item IDs, so clone the entire
          // graph instead of losing an intentional playback repetition.
          row['PlaylistItemId'] = _clonePlaylistItem(db, item);
          tagTargets.add(
            jsonEncode([
              tag,
              row['PlaylistItemId'],
              row['LocationId'],
              row['NoteId'],
            ]),
          );
        } else {
          retain('duplicateTagLink', 'TagMap', record);
          continue;
        }
      }
      row['Position'] = tagPositions.update(
        tag,
        (position) => position + 1,
        ifAbsent: () => 0,
      );
      insertRow(db, 'TagMap', row);
    }

    final modified = source.select('SELECT LastModified FROM LastModified');
    if (modified.length != 1) throw const SchemaFailure('invalidDatabase');
    db.execute('UPDATE LastModified SET LastModified = ?', [
      modified.single['LastModified'],
    ]);
    installCurrentSchemaTriggers(db);
    db.execute('COMMIT');
    return NormalizedSchema(db, issues);
  } on Object catch (error) {
    db.close();
    if (error is SchemaFailure) rethrow;
    throw const SchemaFailure('invalidDatabase');
  }
}

void _copyTable(Database source, Database target, String table) {
  for (final row in streamRows(source, 'SELECT * FROM "$table"')) {
    insertRow(target, table, row);
  }
}

int _clonePlaylistItem(Database db, int original) {
  final row = Map<String, Object?>.of(
    db.select('SELECT * FROM PlaylistItem WHERE PlaylistItemId = ?', [
      original,
    ]).single,
  )..remove('PlaylistItemId');
  final item = insertRow(db, 'PlaylistItem', row);
  for (final table in [
    'PlaylistItemLocationMap',
    'PlaylistItemIndependentMediaMap',
  ]) {
    for (final child in db.select(
      'SELECT * FROM "$table" WHERE PlaylistItemId = ?',
      [original],
    )) {
      insertRow(db, table, {...child, 'PlaylistItemId': item});
    }
  }
  for (final marker in db.select(
    'SELECT * FROM PlaylistItemMarker WHERE PlaylistItemId = ? ORDER BY StartTimeTicks',
    [original],
  )) {
    final data = Map<String, Object?>.of(marker);
    final old = data.remove('PlaylistItemMarkerId');
    data['PlaylistItemId'] = item;
    final id = insertRow(db, 'PlaylistItemMarker', data);
    for (final table in [
      'PlaylistItemMarkerBibleVerseMap',
      'PlaylistItemMarkerParagraphMap',
    ]) {
      for (final child in db.select(
        'SELECT * FROM "$table" WHERE PlaylistItemMarkerId = ?',
        [old],
      )) {
        insertRow(db, table, {...child, 'PlaylistItemMarkerId': id});
      }
    }
  }
  return item;
}

const _commonTables = [
  'Location',
  'UserMark',
  'Tag',
  'Note',
  'Bookmark',
  'BlockRange',
  'TagMap',
];
const _legacyPlaylistTables = [
  'PlaylistMedia',
  'PlaylistItem',
  'PlaylistItemChild',
];
const _modernPlaylistTables = [
  'PlaylistItemAccuracy',
  'IndependentMedia',
  'PlaylistItem',
  'PlaylistItemIndependentMediaMap',
  'PlaylistItemLocationMap',
  'PlaylistItemMarker',
  'PlaylistItemMarkerBibleVerseMap',
  'PlaylistItemMarkerParagraphMap',
];

const _tableDefinitions = <String>[
  r'''
CREATE TABLE BlockRange(
BlockRangeId  INTEGER NOT NULL PRIMARY KEY,
BlockType     INTEGER NOT NULL,
Identifier    INTEGER NOT NULL,
StartToken    INTEGER,
EndToken      INTEGER,
UserMarkId    INTEGER NOT NULL,
CHECK (BlockType BETWEEN 1 AND 2),
FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId))
''',
  r'''
CREATE TABLE Bookmark(
BookmarkId              INTEGER NOT NULL PRIMARY KEY,
LocationId              INTEGER NOT NULL,
PublicationLocationId   INTEGER NOT NULL,
Slot                    INTEGER NOT NULL,
Title                   TEXT NOT NULL,
Snippet                 TEXT,
BlockType               INTEGER NOT NULL DEFAULT 0,
BlockIdentifier         INTEGER,
FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
FOREIGN KEY(PublicationLocationId) REFERENCES Location(LocationId),
CONSTRAINT PublicationLocationId_Slot UNIQUE (PublicationLocationId, Slot),
CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL)))
''',
  r'''
CREATE TABLE IndependentMedia(
IndependentMediaId  INTEGER NOT NULL PRIMARY KEY,
OriginalFilename    TEXT NOT NULL,
FilePath            TEXT NOT NULL UNIQUE,
MimeType            TEXT NOT NULL,
Hash                TEXT NOT NULL,
CHECK(length(OriginalFilename) > 0),
CHECK(length(FilePath) > 0),
CHECK(length(MimeType) > 0),
CHECK(length(Hash) > 0))
''',
  r'''
CREATE TABLE InputField(
LocationId  INTEGER NOT NULL,
TextTag     TEXT NOT NULL,
Value       TEXT NOT NULL,
FOREIGN KEY (LocationId) REFERENCES Location (LocationId),
CONSTRAINT LocationId_TextTag PRIMARY KEY (LocationId, TextTag))
''',
  r'''
CREATE TABLE LastModified(LastModified TEXT NOT NULL)
''',
  r'''
CREATE TABLE "Location"(
LocationId      INTEGER NOT NULL PRIMARY KEY,
BookNumber      INTEGER,
ChapterNumber   INTEGER,
DocumentId      INTEGER,
Track           INTEGER,
IssueTagNumber  INTEGER NOT NULL DEFAULT 0,
KeySymbol       TEXT,
MepsLanguage    INTEGER,
Type            INTEGER NOT NULL,
Title           TEXT,
Specialty       TEXT,
Edition         TEXT,
UNIQUE(BookNumber, ChapterNumber, KeySymbol, MepsLanguage, Type),
CHECK ((
Type = 0 AND ( -- Document or Bible chapter
(DocumentId IS NOT NULL AND DocumentId != 0)
OR ( -- Track based. Requires DocumentId or KeySymbol.
Track IS NOT NULL AND (
(KeySymbol IS NOT NULL AND (length(KeySymbol) > 0))
OR (DocumentId IS NOT NULL AND DocumentId != 0)))
OR ( -- Bible book. Requires KeySymbol.
BookNumber IS NOT NULL AND BookNumber != 0
AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0)
AND (ChapterNumber IS NULL OR ChapterNumber = 0))
OR ( -- Bible chapter. Requires KeySymbol and BookNumber.
ChapterNumber IS NOT NULL AND ChapterNumber != 0
AND BookNumber IS NOT NULL AND BookNumber != 0
AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0))))
OR Type != 0),
CHECK((
Type = 1 -- Bible
AND (BookNumber IS NULL OR BookNumber = 0)
AND (ChapterNumber IS NULL OR ChapterNumber = 0)
AND (DocumentId IS NULL OR DocumentId = 0)
AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0)
AND Track IS NULL)
OR Type != 1),
CHECK((
Type IN (2, 3) -- Mediator audio/video
AND (BookNumber IS NULL OR BookNumber = 0)
AND (ChapterNumber IS NULL OR ChapterNumber = 0))
OR Type NOT IN (2, 3)))
''',
  r'''
CREATE TABLE Note(
NoteId           INTEGER NOT NULL PRIMARY KEY,
Guid             TEXT NOT NULL UNIQUE,
UserMarkId       INTEGER,
LocationId       INTEGER,
Title            TEXT,
Content          TEXT,
LastModified     TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
Created          TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
BlockType        INTEGER NOT NULL DEFAULT 0,
BlockIdentifier  INTEGER,
CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL)),
FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId),
FOREIGN KEY(LocationId) REFERENCES Location(LocationId))
''',
  r'''
CREATE TABLE PlaylistItem(
PlaylistItemId           INTEGER NOT NULL PRIMARY KEY,
Label                    TEXT NOT NULL,
StartTrimOffsetTicks     INTEGER,
EndTrimOffsetTicks       INTEGER,
Accuracy                 INTEGER NOT NULL,
EndAction                INTEGER NOT NULL,
ThumbnailFilePath        TEXT,
FOREIGN KEY(Accuracy) REFERENCES PlaylistItemAccuracy(PlaylistItemAccuracyId),
FOREIGN KEY(ThumbnailFilePath) REFERENCES IndependentMedia(FilePath),
CHECK(length(Label) > 0),
CHECK(EndAction IN(0, 1, 2, 3)))
''',
  r'''
CREATE TABLE PlaylistItemAccuracy(
PlaylistItemAccuracyId  INTEGER NOT NULL PRIMARY KEY,
Description             TEXT NOT NULL UNIQUE)
''',
  r'''
CREATE TABLE PlaylistItemIndependentMediaMap(
PlaylistItemId      INTEGER NOT NULL,
IndependentMediaId  INTEGER NOT NULL,
DurationTicks       INTEGER NOT NULL,
PRIMARY KEY(PlaylistItemId, IndependentMediaId),
FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
FOREIGN KEY(IndependentMediaId) REFERENCES IndependentMedia(IndependentMediaId))
WITHOUT ROWID
''',
  r'''
CREATE TABLE PlaylistItemLocationMap(
PlaylistItemId      INTEGER NOT NULL,
LocationId          INTEGER NOT NULL,
MajorMultimediaType INTEGER NOT NULL,
BaseDurationTicks   INTEGER,
PRIMARY KEY(PlaylistItemId, LocationId),
FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
FOREIGN KEY(LocationId) REFERENCES Location(LocationId))
WITHOUT ROWID
''',
  r'''
CREATE TABLE PlaylistItemMarker(
PlaylistItemMarkerId        INTEGER NOT NULL PRIMARY KEY,
PlaylistItemId              INTEGER NOT NULL,
Label                       TEXT NOT NULL,
StartTimeTicks              INTEGER NOT NULL,
DurationTicks               INTEGER NOT NULL,
EndTransitionDurationTicks  INTEGER NOT NULL,
UNIQUE(PlaylistItemId, StartTimeTicks),
FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId))
''',
  r'''
CREATE TABLE PlaylistItemMarkerBibleVerseMap(
PlaylistItemMarkerId        INTEGER NOT NULL,
VerseId                     INTEGER NOT NULL,
PRIMARY KEY(PlaylistItemMarkerId, VerseId),
FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId))
WITHOUT ROWID
''',
  r'''
CREATE TABLE PlaylistItemMarkerParagraphMap(
PlaylistItemMarkerId        INTEGER NOT NULL,
MepsDocumentId              INTEGER NOT NULL,
ParagraphIndex              INTEGER NOT NULL,
MarkerIndexWithinParagraph  INTEGER NOT NULL,
PRIMARY KEY(PlaylistItemMarkerId, MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph),
FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId))
WITHOUT ROWID
''',
  r'''
CREATE TABLE Tag(
TagId          INTEGER NOT NULL PRIMARY KEY,
Type           INTEGER NOT NULL,
Name           TEXT NOT NULL,
UNIQUE(Type, Name),
CHECK(length(Name) > 0),
CHECK(Type IN (0, 1, 2)))
''',
  r'''
CREATE TABLE TagMap(
TagMapId        INTEGER NOT NULL PRIMARY KEY,
PlaylistItemId  INTEGER,
LocationId      INTEGER,
NoteId          INTEGER,
TagId           INTEGER NOT NULL,
Position        INTEGER NOT NULL,
FOREIGN KEY(TagId) REFERENCES Tag(TagId),
FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
FOREIGN KEY(NoteId) REFERENCES Note(NoteId),
CONSTRAINT TagId_Position UNIQUE(TagId, Position),
CONSTRAINT TagId_NoteId UNIQUE(TagId, NoteId),
CONSTRAINT TagId_LocationId UNIQUE(TagId, LocationId),
CONSTRAINT TagId_PlaylistItemId UNIQUE(TagId, PlaylistItemId),
CHECK(
(NoteId IS NULL AND LocationId IS NULL AND PlaylistItemId IS NOT NULL) OR
(LocationId IS NULL AND PlaylistItemId IS NULL AND NoteId IS NOT NULL) OR
(PlaylistItemId IS NULL AND NoteId IS NULL AND LocationId IS NOT NULL)))
''',
  r'''
CREATE TABLE UserMark(
UserMarkId    INTEGER NOT NULL PRIMARY KEY,
ColorIndex    INTEGER NOT NULL,
LocationId    INTEGER NOT NULL,
StyleIndex    INTEGER NOT NULL,
UserMarkGuid  TEXT NOT NULL UNIQUE,
Version       INTEGER NOT NULL,
FOREIGN KEY(LocationId) REFERENCES Location(LocationId))
''',
  r'''
CREATE TABLE android_metadata (locale TEXT)
''',
];

const _indexDefinitions = <String>[
  r'''
CREATE INDEX IX_BlockRange_UserMarkId ON BlockRange(UserMarkId)
''',
  r'''
CREATE INDEX IX_Location_KeySymbol_MepsLanguage_BookNumber_ChapterNumber ON
Location(KeySymbol, MepsLanguage, BookNumber, ChapterNumber)
''',
  r'''
CREATE UNIQUE INDEX IX_Location_Media ON Location(
KeySymbol,
IssueTagNumber,
MepsLanguage,
DocumentId,
Track,
Type,
COALESCE(Specialty, ''),
COALESCE(Edition, ''))
''',
  r'''
CREATE INDEX IX_Location_MepsLanguage_DocumentId ON Location(MepsLanguage, DocumentId)
''',
  r'''
CREATE INDEX IX_Note_LastModified_LocationId ON Note(LastModified, LocationId)
''',
  r'''
CREATE INDEX IX_Note_LocationId_BlockIdentifier ON Note(LocationId, BlockIdentifier)
''',
  r'''
CREATE INDEX IX_PlaylistItemIndependentMediaMap_IndependentMediaId ON PlaylistItemIndependentMediaMap(IndependentMediaId)
''',
  r'''
CREATE INDEX IX_PlaylistItemLocationMap_LocationId ON PlaylistItemLocationMap(LocationId)
''',
  r'''
CREATE INDEX IX_PlaylistItem_ThumbnailFilePath ON PlaylistItem(ThumbnailFilePath)
''',
  r'''
CREATE INDEX IX_TagMap_LocationId_TagId_Position ON TagMap(LocationId, TagId, Position)
''',
  r'''
CREATE INDEX IX_TagMap_NoteId_TagId_Position ON TagMap(NoteId, TagId, Position)
''',
  r'''
CREATE INDEX IX_TagMap_PlaylistItemId_TagId_Position ON TagMap(PlaylistItemId, TagId, Position)
''',
  r'''
CREATE INDEX IX_TagMap_TagId ON TagMap(TagId)
''',
  r'''
CREATE INDEX IX_Tag_Name_Type_TagId ON Tag(Name, Type, TagId)
''',
  r'''
CREATE INDEX IX_UserMark_LocationId ON UserMark(LocationId)
''',
];

const _triggerDefinitions = <String>[
  r'''
CREATE TRIGGER TR_Raise_Error_Before_Delete_LastModified
BEFORE DELETE ON LastModified
BEGIN
SELECT RAISE (FAIL, 'DELETE FROM LastModified not allowed');
END
''',
  r'''
CREATE TRIGGER TR_Raise_Error_Before_Insert_LastModified
BEFORE INSERT ON LastModified
BEGIN
SELECT RAISE (FAIL, 'INSERT INTO LastModified not allowed');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_BlockRange
DELETE ON BlockRange
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Bookmark
DELETE ON Bookmark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_IndependentMedia
DELETE ON IndependentMedia
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_InputField
DELETE ON InputField
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Note
DELETE ON Note
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_PlaylistItem
DELETE ON PlaylistItem
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Tag
DELETE ON Tag
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_TagMap
DELETE ON TagMap
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_UserMark
DELETE ON UserMark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_BlockRange
INSERT ON BlockRange
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Bookmark
INSERT ON Bookmark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_IndependentMedia
INSERT ON IndependentMedia
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_InputField
INSERT ON InputField
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Note
INSERT ON Note
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_PlaylistItem
INSERT ON PlaylistItem
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Tag
INSERT ON Tag
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_TagMap
INSERT ON TagMap
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_UserMark
INSERT ON UserMark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_BlockRange
UPDATE ON BlockRange
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Bookmark
UPDATE ON Bookmark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_IndependentMedia
UPDATE ON IndependentMedia
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_InputField
UPDATE ON InputField
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Note
UPDATE ON Note
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_PlaylistItem
UPDATE ON PlaylistItem
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Tag
UPDATE ON Tag
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_TagMap
UPDATE ON TagMap
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_UserMark
UPDATE ON UserMark
BEGIN
UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now');
END
''',
];
