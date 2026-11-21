-- Shared user-data table definitions for synthetic JW Library fixtures.

CREATE TABLE BlockRange ( BlockRangeId INTEGER NOT NULL PRIMARY KEY,
    BlockType INTEGER NOT NULL,
    Identifier INTEGER NOT NULL,
    StartToken INTEGER,
    EndToken INTEGER,
    UserMarkId INTEGER NOT NULL,
    CHECK (BlockType BETWEEN 1 AND 2),
    FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId) );

CREATE TABLE "Bookmark" ( BookmarkId INTEGER NOT NULL PRIMARY KEY,
    LocationId INTEGER NOT NULL,
    PublicationLocationId INTEGER NOT NULL,
    Slot INTEGER NOT NULL,
    Title TEXT NOT NULL,
    Snippet TEXT,
    BlockType INTEGER NOT NULL DEFAULT 0,
    BlockIdentifier INTEGER,
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
    FOREIGN KEY(PublicationLocationId) REFERENCES Location(LocationId),
    CONSTRAINT PublicationLocationId_Slot UNIQUE (PublicationLocationId, Slot),
    CHECK((BlockType = 0 AND BlockIdentifier IS NULL) OR ((BlockType BETWEEN 1 AND 2) AND BlockIdentifier IS NOT NULL)) );

CREATE TABLE "TagMap" ( TagMapId INTEGER NOT NULL PRIMARY KEY,
    PlaylistItemId INTEGER,
    LocationId INTEGER,
    NoteId INTEGER,
    TagId INTEGER NOT NULL,
    Position INTEGER NOT NULL,
    FOREIGN KEY(TagId) REFERENCES Tag(TagId),
    FOREIGN KEY(PlaylistItemId) REFERENCES PlaylistItem(PlaylistItemId),
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
    FOREIGN KEY(NoteId) REFERENCES Note(NoteId),
    CONSTRAINT TagId_Position UNIQUE(TagId, Position),
    CONSTRAINT TagId_NoteId UNIQUE(TagId, NoteId),
    CONSTRAINT TagId_LocationId UNIQUE(TagId, LocationId),
    CHECK( (NoteId IS NULL AND LocationId IS NULL AND PlaylistItemId IS NOT NULL) OR (LocationId IS NULL AND PlaylistItemId IS NULL AND NoteId IS NOT NULL) OR (PlaylistItemId IS NULL AND NoteId IS NULL AND LocationId IS NOT NULL)) );

CREATE TABLE "UserMark" ( UserMarkId INTEGER NOT NULL PRIMARY KEY,
    ColorIndex INTEGER NOT NULL,
    LocationId INTEGER NOT NULL,
    StyleIndex INTEGER NOT NULL,
    UserMarkGuid TEXT NOT NULL UNIQUE,
    Version INTEGER NOT NULL,
    FOREIGN KEY(LocationId) REFERENCES Location(LocationId) );

CREATE TABLE "InputField"( LocationId INTEGER NOT NULL,
    TextTag TEXT NOT NULL,
    Value TEXT NOT NULL,
    FOREIGN KEY (LocationId) REFERENCES Location (LocationId),
    CONSTRAINT LocationId_TextTag PRIMARY KEY (LocationId, TextTag));
