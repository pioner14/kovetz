-- JW Library v8 user-data table definitions for synthetic fixtures.

CREATE TABLE LastModified(LastModified TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')));

CREATE TABLE "Tag" ( TagId INTEGER NOT NULL PRIMARY KEY,
    Type INTEGER NOT NULL,
    Name TEXT NOT NULL,
    ImageFilename TEXT, UNIQUE(Type, Name),
    CHECK(length(Name) > 0),
    CHECK(Type IN (0, 1, 2)) );

CREATE TABLE "Note" ( NoteId INTEGER NOT NULL PRIMARY KEY,
    Guid TEXT NOT NULL UNIQUE,
    UserMarkId INTEGER,
    LocationId INTEGER,
    Title TEXT,
    Content TEXT,
    LastModified TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    BlockType INTEGER NOT NULL DEFAULT 0,
    BlockIdentifier INTEGER,
    CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR ((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL)),
    FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId),
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId) );

CREATE TABLE PlaylistMedia( PlaylistMediaId INTEGER NOT NULL PRIMARY KEY,
    MediaType INTEGER NOT NULL,
    Label TEXT,
    Filename TEXT UNIQUE,
    LocationId INTEGER,
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
    CONSTRAINT MediaType_LocationId UNIQUE(MediaType, LocationId),
    CHECK( (LocationId IS NULL AND Filename IS NOT NULL AND Label IS NOT NULL) OR (LocationId IS NOT NULL AND Filename IS NULL AND Label IS NULL) OR (LocationId IS NOT NULL AND Filename IS NOT NULL)),
    CHECK(MediaType IN(1, 2, 3)) );

CREATE TABLE PlaylistItem( PlaylistItemId INTEGER NOT NULL PRIMARY KEY,
    Label TEXT NOT NULL,
    AccuracyStatement INTEGER NOT NULL,
    StartTimeOffsetTicks INTEGER,
    EndTimeOffsetTicks INTEGER,
    EndAction INTEGER NOT NULL,
    ThumbnailFilename TEXT,
    PlaylistMediaId INTEGER NOT NULL,
    FOREIGN KEY(PlaylistMediaId) REFERENCES PlaylistMedia(PlaylistMediaId),
    CHECK(length(Label) > 0),
    CHECK(AccuracyStatement IN(0, 1, 2, 3)),
    CHECK(EndAction IN(0, 1, 2, 3)) );

CREATE TABLE PlaylistItemChild( PlaylistItemChildId INTEGER NOT NULL PRIMARY KEY,
    BaseDurationTicks INTEGER NOT NULL,
    MarkerId INTEGER,
    MarkerLabel TEXT,
    MarkerStartTimeTicks INTEGER,
    MarkerEndTransitionDurationTicks INTEGER,
    PlaylistItemId INTEGER NOT NULL,
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
    CHECK( (MarkerId IS NULL AND MarkerLabel IS NULL AND MarkerStartTimeTicks IS NULL AND MarkerEndTransitionDurationTicks IS NULL) OR (MarkerId IS NOT NULL AND MarkerLabel IS NOT NULL AND MarkerStartTimeTicks IS NOT NULL) ) );

CREATE TABLE "Location" ( LocationId INTEGER NOT NULL PRIMARY KEY,
    BookNumber INTEGER,
    ChapterNumber INTEGER,
    DocumentId INTEGER,
    Track INTEGER,
    IssueTagNumber INTEGER NOT NULL DEFAULT 0,
    KeySymbol TEXT,
    MepsLanguage INTEGER NOT NULL,
    Type INTEGER NOT NULL,
    Title TEXT, UNIQUE(BookNumber, ChapterNumber, KeySymbol, MepsLanguage, Type), UNIQUE(KeySymbol, IssueTagNumber, MepsLanguage, DocumentId, Track, Type),
    CHECK ( ((TYPE IN (0, 1) AND KeySymbol IS NOT NULL) AND ((Type = 0 AND (DocumentId IS NOT NULL AND DocumentId != 0) AND BookNumber IS NULL AND ChapterNumber IS NULL AND Track IS NULL) OR (Type = 0 AND DocumentId IS NULL AND (BookNumber IS NOT NULL AND BookNumber != 0) AND (ChapterNumber IS NOT NULL AND ChapterNumber != 0) AND Track IS NULL) OR (Type = 1 AND BookNumber IS NULL AND ChapterNumber IS NULL AND DocumentId IS NULL AND Track IS NULL))) OR (Type IN (2, 3) AND BookNumber IS NULL AND ChapterNumber IS NULL) ) );
