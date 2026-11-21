-- Schema-only fixture based on the 2019 JW Library v5 table layout.

CREATE TABLE Location (
                LocationId             INTEGER NOT NULL PRIMARY KEY,
                BookNumber             INTEGER,
                ChapterNumber          INTEGER,
                DocumentId             INTEGER,
                Track                  INTEGER,
                IssueTagNumber         INTEGER NOT NULL DEFAULT 0,
                KeySymbol              TEXT NOT NULL,
                MepsLanguage           INTEGER NOT NULL,
                Type                   INTEGER NOT NULL,
                Title                  TEXT,
                CHECK (
                    (Type = 0 AND (DocumentId IS NOT NULL AND DocumentId != 0) AND BookNumber IS NULL AND ChapterNumber IS NULL AND Track IS NULL) OR
                    (Type = 0 AND DocumentId IS NULL AND (BookNumber IS NOT NULL AND BookNumber != 0) AND (ChapterNumber IS NOT NULL AND ChapterNumber != 0) AND Track IS NULL) OR
                    (Type = 1 AND BookNumber IS NULL AND ChapterNumber IS NULL AND DocumentId IS NULL AND Track IS NULL) OR
                    (Type IN (2, 3) AND BookNumber IS NULL AND ChapterNumber IS NULL)
                )
            );

CREATE TABLE UserMark (
                UserMarkId          INTEGER NOT NULL PRIMARY KEY,
                ColorIndex          INTEGER NOT NULL,
                LocationId          INTEGER NOT NULL,
                StyleIndex          INTEGER NOT NULL,
                UserMarkGuid        TEXT NOT NULL UNIQUE,
                Version             INTEGER NOT NULL,
                CHECK (LocationId > 0),
                FOREIGN KEY(LocationId) REFERENCES Location(LocationId)
            );

CREATE TABLE BlockRange (
                BlockRangeId    INTEGER NOT NULL PRIMARY KEY,
                BlockType       INTEGER NOT NULL,
                Identifier      INTEGER NOT NULL,
                StartToken      INTEGER,
                EndToken        INTEGER,
                UserMarkId      INTEGER NOT NULL,
                CHECK (BlockType BETWEEN 1 AND 2),
                FOREIGN KEY(UserMarkId) REFERENCES UserMark(UserMarkId)
            );

CREATE TABLE Tag(TagId INTEGER NOT NULL PRIMARY KEY, Type INTEGER NOT NULL,Name TEXT NOT NULL,UNIQUE (Type, Name), CHECK (length(Name) > 0));

CREATE TABLE TagMap (
                TagMapId INTEGER NOT NULL PRIMARY KEY,
                Type INTEGER NOT NULL,
                TypeId INTEGER NOT NULL,
                TagId INTEGER NOT NULL,
                Position INTEGER NOT NULL,
                FOREIGN KEY(TagId) REFERENCES Tag(TagId)
                CONSTRAINT Type_TypeId_TagId_Position UNIQUE (Type, TypeId, TagId, Position));

CREATE TABLE Note( NoteId INTEGER NOT NULL PRIMARY KEY, Guid TEXT NOT NULL UNIQUE, UserMarkId INTEGER, LocationId INTEGER, Title TEXT, Content TEXT, LastModified TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), BlockType INTEGER NOT NULL DEFAULT 0, BlockIdentifier INTEGER, CHECK ((BlockType = 0 AND BlockIdentifier IS NULL) OR (BlockType != 0 AND BlockIdentifier IS NOT NULL)));

CREATE TABLE Bookmark(
            BookmarkId INTEGER NOT NULL PRIMARY KEY,
            LocationId INTEGER NOT NULL,
            PublicationLocationId INTEGER NOT NULL,
            Slot INTEGER NOT NULL,
            Title TEXT NOT NULL,
            Snippet TEXT,
            BlockType INTEGER NOT NULL DEFAULT 0,
            BlockIdentifier INTEGER,
            FOREIGN KEY(LocationId) REFERENCES Location(LocationId),
            FOREIGN KEY(PublicationLocationId) REFERENCES Location(LocationId),
            CONSTRAINT PublicationLocationId_Slot UNIQUE (PublicationLocationId, Slot));

CREATE TABLE LastModified(LastModified TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%SZ', 'now')));
