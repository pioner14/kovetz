-- JW Library v14 user-data table definitions for synthetic fixtures.

CREATE TABLE PlaylistItemAccuracy( PlaylistItemAccuracyId INTEGER NOT NULL PRIMARY KEY,
    Description TEXT NOT NULL UNIQUE);

CREATE TABLE IndependentMedia( IndependentMediaId INTEGER NOT NULL PRIMARY KEY,
    OriginalFilename TEXT NOT NULL,
    FilePath TEXT NOT NULL UNIQUE,
    MimeType TEXT NOT NULL,
    Hash TEXT NOT NULL,
    CHECK(length(OriginalFilename) > 0),
    CHECK(length(FilePath) > 0),
    CHECK(length(MimeType) > 0),
    CHECK(length(Hash) > 0));

CREATE TABLE PlaylistItemIndependentMediaMap( PlaylistItemId INTEGER NOT NULL,
    IndependentMediaId INTEGER NOT NULL,
    DurationTicks INTEGER NOT NULL, PRIMARY KEY(PlaylistItemId, IndependentMediaId),
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
    FOREIGN KEY(IndependentMediaId) REFERENCES IndependentMedia(IndependentMediaId)) WITHOUT ROWID;

CREATE TABLE PlaylistItemLocationMap( PlaylistItemId INTEGER NOT NULL,
    LocationId INTEGER NOT NULL,
    MajorMultimediaType INTEGER NOT NULL,
    BaseDurationTicks INTEGER, PRIMARY KEY(PlaylistItemId, LocationId),
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId)) WITHOUT ROWID;

CREATE TABLE PlaylistItemMarker( PlaylistItemMarkerId INTEGER NOT NULL PRIMARY KEY,
    PlaylistItemId INTEGER NOT NULL,
    Label TEXT NOT NULL,
    StartTimeTicks INTEGER NOT NULL,
    DurationTicks INTEGER NOT NULL,
    EndTransitionDurationTicks INTEGER NOT NULL, UNIQUE(PlaylistItemId, StartTimeTicks),
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId));

CREATE TABLE PlaylistItemMarkerBibleVerseMap( PlaylistItemMarkerId INTEGER NOT NULL,
    VerseId INTEGER NOT NULL, PRIMARY KEY(PlaylistItemMarkerId, VerseId),
    FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId)) WITHOUT ROWID;

CREATE TABLE PlaylistItemMarkerParagraphMap( PlaylistItemMarkerId INTEGER NOT NULL,
    MepsDocumentId INTEGER NOT NULL,
    ParagraphIndex INTEGER NOT NULL,
    MarkerIndexWithinParagraph INTEGER NOT NULL, PRIMARY KEY(PlaylistItemMarkerId, MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph),
    FOREIGN KEY(PlaylistItemMarkerId) REFERENCES PlaylistItemMarker(PlaylistItemMarkerId)) WITHOUT ROWID;

CREATE TABLE Tag( TagId INTEGER NOT NULL PRIMARY KEY,
    Type INTEGER NOT NULL,
    Name TEXT NOT NULL, UNIQUE(Type, Name),
    CHECK(length(Name) > 0),
    CHECK(Type IN (0, 1, 2)));

CREATE TABLE "Note"( NoteId INTEGER NOT NULL PRIMARY KEY,
    Guid TEXT NOT NULL UNIQUE,
    UserMarkId INTEGER,
    LocationId INTEGER,
    Title TEXT,
    Content TEXT,
    LastModified TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    Created TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    BlockType INTEGER NOT NULL DEFAULT 0,
    BlockIdentifier INTEGER,
    CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL)),
    FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId),
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId));

CREATE TABLE "LastModified"(LastModified TEXT NOT NULL);

CREATE TABLE "PlaylistItem"( PlaylistItemId INTEGER NOT NULL PRIMARY KEY,
    Label TEXT NOT NULL,
    StartTrimOffsetTicks INTEGER,
    EndTrimOffsetTicks INTEGER,
    Accuracy INTEGER NOT NULL,
    EndAction INTEGER NOT NULL,
    ThumbnailFilePath TEXT,
    FOREIGN KEY(Accuracy) REFERENCES PlaylistItemAccuracy(PlaylistItemAccuracyId),
    FOREIGN KEY(ThumbnailFilePath) REFERENCES IndependentMedia(FilePath),
    CHECK(length(Label) > 0),
    CHECK(EndAction IN(0, 1, 2, 3)));

CREATE TABLE "Location"( LocationId INTEGER NOT NULL PRIMARY KEY,
    BookNumber INTEGER,
    ChapterNumber INTEGER,
    DocumentId INTEGER,
    Track INTEGER,
    IssueTagNumber INTEGER NOT NULL DEFAULT 0,
    KeySymbol TEXT,
    MepsLanguage INTEGER,
    Type INTEGER NOT NULL,
    Title TEXT, UNIQUE(BookNumber, ChapterNumber, KeySymbol, MepsLanguage, Type), UNIQUE(KeySymbol, IssueTagNumber, MepsLanguage, DocumentId, Track, Type),
    CHECK (( Type = 0 AND ( (DocumentId IS NOT NULL AND DocumentId != 0) OR ( Track IS NOT NULL AND ( (KeySymbol IS NOT NULL AND (length(KeySymbol) > 0)) OR (DocumentId IS NOT NULL AND DocumentId != 0))) OR ( BookNumber IS NOT NULL AND BookNumber != 0 AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0) AND (ChapterNumber IS NULL OR ChapterNumber = 0)) OR ( ChapterNumber IS NOT NULL AND ChapterNumber != 0 AND BookNumber IS NOT NULL AND BookNumber != 0 AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0)))) OR Type != 0),
    CHECK(( Type = 1 AND (BookNumber IS NULL OR BookNumber = 0) AND (ChapterNumber IS NULL OR ChapterNumber = 0) AND (DocumentId IS NULL OR DocumentId = 0) AND KeySymbol IS NOT NULL AND (length(KeySymbol) > 0) AND Track IS NULL) OR Type != 1),
    CHECK(( Type IN (2, 3) AND (BookNumber IS NULL OR BookNumber = 0) AND (ChapterNumber IS NULL OR ChapterNumber = 0)) OR Type NOT IN (2, 3)));
