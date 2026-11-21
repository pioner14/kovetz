// Schema of JW Library v16 backups written by the GRDB-based app (Android,
// observed in an export of 2026-11-20). Schema only: no user records.
// These backups record applied migrations in grdb_migrations. Restoring a
// merge in the older v16 schema on such a device failed with "saved data is
// damaged" (2026-11-21), so a merge based on such a backup uses this schema.
// Statements are kept verbatim, in the order of the source sqlite_schema.

/// Tables, including grdb_migrations.
const grdbTableDefinitions = <String>[
  // BlockRange
  r'''
CREATE TABLE BlockRange ( BlockRangeId    INTEGER NOT NULL PRIMARY KEY, BlockType       INTEGER NOT NULL, Identifier      INTEGER NOT NULL, StartToken      INTEGER, EndToken        INTEGER, UserMarkId      INTEGER NOT NULL, CHECK (BlockType BETWEEN 1 AND 2), FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId) )''',
  // android_metadata
  r'''
CREATE TABLE android_metadata (locale TEXT)''',
  // Bookmark
  r'''
CREATE TABLE "Bookmark" (
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
    CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR ((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL))
)''',
  // TagMap
  r'''
CREATE TABLE "TagMap" (
    TagMapId          INTEGER NOT NULL PRIMARY KEY,
    PlaylistItemId    INTEGER,
    LocationId        INTEGER,
    NoteId            INTEGER,
    TagId             INTEGER NOT NULL,
    Position          INTEGER NOT NULL,
    FOREIGN KEY(TagId) REFERENCES Tag(TagId),
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
    FOREIGN KEY(NoteId) REFERENCES Note(NoteId),
    CONSTRAINT TagId_Position UNIQUE(TagId, Position),
    CONSTRAINT TagId_NoteId UNIQUE(TagId, NoteId),
    CONSTRAINT TagId_LocationId UNIQUE(TagId, LocationId),
    CHECK(
        (NoteId IS NULL AND LocationId IS NULL AND PlaylistItemId IS NOT NULL) OR
        (LocationId IS NULL AND PlaylistItemId IS NULL AND NoteId IS NOT NULL) OR
        (PlaylistItemId IS NULL AND NoteId IS NULL AND LocationId IS NOT NULL))
)''',
  // UserMark
  r'''
CREATE TABLE "UserMark" (
    UserMarkId      INTEGER NOT NULL PRIMARY KEY,
    ColorIndex      INTEGER NOT NULL,
    LocationId      INTEGER NOT NULL,
    StyleIndex      INTEGER NOT NULL,
    UserMarkGuid    TEXT NOT NULL UNIQUE,
    Version         INTEGER NOT NULL,
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId)
)''',
  // grdb_migrations
  r'''
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)''',
  // PlaylistItemAccuracy
  r'''
CREATE TABLE PlaylistItemAccuracy(
	PlaylistItemAccuracyId  INTEGER NOT NULL PRIMARY KEY,
	Description             TEXT NOT NULL UNIQUE)''',
  // IndependentMedia
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
	CHECK(length(Hash) > 0))''',
  // PlaylistItemIndependentMediaMap
  r'''
CREATE TABLE PlaylistItemIndependentMediaMap(
	PlaylistItemId      INTEGER NOT NULL,
	IndependentMediaId  INTEGER NOT NULL,
	DurationTicks       INTEGER NOT NULL,
	PRIMARY KEY(PlaylistItemId, IndependentMediaId),
	FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
	FOREIGN KEY(IndependentMediaId) REFERENCES IndependentMedia(IndependentMediaId)) 
WITHOUT ROWID''',
  // PlaylistItemLocationMap
  r'''
CREATE TABLE PlaylistItemLocationMap(
	PlaylistItemId      INTEGER NOT NULL,
	LocationId          INTEGER NOT NULL,
	MajorMultimediaType INTEGER NOT NULL,
	BaseDurationTicks   INTEGER,
	PRIMARY KEY(PlaylistItemId, LocationId),
	FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
	FOREIGN KEY(LocationId) REFERENCES Location(LocationId)) 
WITHOUT ROWID''',
  // PlaylistItemMarker
  r'''
CREATE TABLE PlaylistItemMarker(
	PlaylistItemMarkerId        INTEGER NOT NULL PRIMARY KEY,
	PlaylistItemId              INTEGER NOT NULL,
	Label                       TEXT NOT NULL,
	StartTimeTicks              INTEGER NOT NULL,
	DurationTicks               INTEGER NOT NULL,
	EndTransitionDurationTicks  INTEGER NOT NULL,
	UNIQUE(PlaylistItemId, StartTimeTicks),
	FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId))''',
  // PlaylistItemMarkerBibleVerseMap
  r'''
CREATE TABLE PlaylistItemMarkerBibleVerseMap(
	PlaylistItemMarkerId        INTEGER NOT NULL,
	VerseId                     INTEGER NOT NULL,
	PRIMARY KEY(PlaylistItemMarkerId, VerseId),
	FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId)) 
WITHOUT ROWID''',
  // PlaylistItemMarkerParagraphMap
  r'''
CREATE TABLE PlaylistItemMarkerParagraphMap(
	PlaylistItemMarkerId        INTEGER NOT NULL,
	MepsDocumentId              INTEGER NOT NULL,
	ParagraphIndex              INTEGER NOT NULL,
	MarkerIndexWithinParagraph  INTEGER NOT NULL,
	PRIMARY KEY(PlaylistItemMarkerId, MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph),
	FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId)) 
WITHOUT ROWID''',
  // Tag
  r'''
CREATE TABLE Tag(
	TagId          INTEGER NOT NULL PRIMARY KEY,
	Type           INTEGER NOT NULL,
	Name           TEXT NOT NULL,
	UNIQUE(Type, Name),
	CHECK(length(Name) > 0),
	CHECK(Type IN (0, 1, 2)))''',
  // Note
  r'''
CREATE TABLE "Note"(
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
	FOREIGN KEY(LocationId) REFERENCES Location(LocationId))''',
  // LastModified
  r'''
CREATE TABLE "LastModified"(LastModified TEXT NOT NULL)''',
  // PlaylistItem
  r'''
CREATE TABLE "PlaylistItem"(            
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
	CHECK(EndAction IN(0, 1, 2, 3)))''',
  // InputField
  r'''
CREATE TABLE "InputField"(
LocationId  INTEGER NOT NULL,
TextTag     TEXT NOT NULL,
Value       TEXT NOT NULL,
FOREIGN KEY (LocationId) REFERENCES Location (LocationId),
CONSTRAINT LocationId_TextTag PRIMARY KEY (LocationId, TextTag))''',
  // Location
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
OR Type NOT IN (2, 3)))''',
];

/// Indexes.
const grdbIndexDefinitions = <String>[
  // IX_BlockRange_UserMarkId
  r'''
CREATE INDEX IX_BlockRange_UserMarkId ON BlockRange(UserMarkId)''',
  // IX_TagMap_TagId
  r'''
CREATE INDEX IX_TagMap_TagId ON TagMap(TagId)''',
  // IX_TagMap_PlaylistItemId_TagId_Position
  r'''
CREATE INDEX IX_TagMap_PlaylistItemId_TagId_Position ON TagMap(PlaylistItemId, TagId, Position)''',
  // IX_TagMap_LocationId_TagId_Position
  r'''
CREATE INDEX IX_TagMap_LocationId_TagId_Position ON TagMap(LocationId, TagId, Position)''',
  // IX_TagMap_NoteId_TagId_Position
  r'''
CREATE INDEX IX_TagMap_NoteId_TagId_Position ON TagMap(NoteId, TagId, Position)''',
  // IX_UserMark_LocationId
  r'''
CREATE INDEX IX_UserMark_LocationId ON UserMark(LocationId)''',
  // IX_Note_LastModified_LocationId
  r'''
CREATE INDEX IX_Note_LastModified_LocationId ON Note(LastModified, LocationId)''',
  // IX_Note_LocationId_BlockIdentifier
  r'''
CREATE INDEX IX_Note_LocationId_BlockIdentifier ON Note(LocationId, BlockIdentifier)''',
  // IX_PlaylistItemIndependentMediaMap_IndependentMediaId
  r'''
CREATE INDEX IX_PlaylistItemIndependentMediaMap_IndependentMediaId ON PlaylistItemIndependentMediaMap(IndependentMediaId)''',
  // IX_PlaylistItemLocationMap_LocationId
  r'''
CREATE INDEX IX_PlaylistItemLocationMap_LocationId ON PlaylistItemLocationMap(LocationId)''',
  // IX_PlaylistItem_ThumbnailFilePath
  r'''
CREATE INDEX IX_PlaylistItem_ThumbnailFilePath ON PlaylistItem(ThumbnailFilePath)''',
  // IX_Location_KeySymbol_MepsLanguage_BookNumber_ChapterNumber
  r'''
CREATE INDEX IX_Location_KeySymbol_MepsLanguage_BookNumber_ChapterNumber ON
Location(KeySymbol, MepsLanguage, BookNumber, ChapterNumber)''',
  // IX_Location_MepsLanguage_DocumentId
  r'''
CREATE INDEX IX_Location_MepsLanguage_DocumentId ON Location(MepsLanguage, DocumentId)''',
  // IX_Location_Media
  r'''
CREATE UNIQUE INDEX IX_Location_Media ON Location(
KeySymbol,
IssueTagNumber,
MepsLanguage,
DocumentId,
Track,
Type,
COALESCE(Specialty, ''),
COALESCE(Edition, ''))''',
];

/// Triggers, installed after the data is written.
const grdbTriggerDefinitions = <String>[
  // TR_Update_LastModified_Insert_Tag
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Tag
	INSERT ON Tag 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_Tag
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Tag 
	UPDATE ON Tag 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_Tag
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Tag 
	DELETE ON Tag 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_TagMap
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_TagMap
	INSERT ON TagMap 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_TagMap
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_TagMap 
	UPDATE ON TagMap 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_TagMap
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_TagMap 
	DELETE ON TagMap 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_Note
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Note
	INSERT ON Note 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_Note
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Note 
	UPDATE ON Note 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_Note
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Note 
	DELETE ON Note 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_Bookmark
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_Bookmark
	INSERT ON Bookmark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_Bookmark
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_Bookmark 
	UPDATE ON Bookmark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_Bookmark
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_Bookmark 
	DELETE ON Bookmark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_UserMark
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_UserMark
	INSERT ON UserMark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_UserMark
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_UserMark 
	UPDATE ON UserMark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_UserMark
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_UserMark 
	DELETE ON UserMark 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_BlockRange
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_BlockRange
	INSERT ON BlockRange 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_BlockRange
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_BlockRange 
	UPDATE ON BlockRange 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_BlockRange
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_BlockRange 
	DELETE ON BlockRange 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Insert_IndependentMedia
  r'''
CREATE TRIGGER TR_Update_LastModified_Insert_IndependentMedia
	INSERT ON IndependentMedia 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Update_IndependentMedia
  r'''
CREATE TRIGGER TR_Update_LastModified_Update_IndependentMedia 
	UPDATE ON IndependentMedia 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Update_LastModified_Delete_IndependentMedia
  r'''
CREATE TRIGGER TR_Update_LastModified_Delete_IndependentMedia 
	DELETE ON IndependentMedia 
	BEGIN 
		UPDATE LastModified SET LastModified = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'); 
	END''',
  // TR_Raise_Error_Before_Insert_LastModified
  r'''
CREATE TRIGGER TR_Raise_Error_Before_Insert_LastModified 
	BEFORE INSERT ON LastModified 
	BEGIN
		SELECT RAISE (FAIL, 'INSERT INTO LastModified not allowed');
	END''',
  // TR_Raise_Error_Before_Delete_LastModified
  r'''
CREATE TRIGGER TR_Raise_Error_Before_Delete_LastModified 
	BEFORE DELETE ON LastModified 
	BEGIN
		SELECT RAISE (FAIL, 'DELETE FROM LastModified not allowed');
	END''',
];

/// Migration identifiers applied by the app that wrote this schema.
const grdbMigrations = <String>['v9', 'v10', 'v11', 'v12', 'v13'];
