-- Schema-only v14 to v16 fixture change, taken from the supplied backup.
DROP TABLE Location;
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
OR Type NOT IN (2, 3)));
CREATE UNIQUE INDEX IX_Location_Media ON Location(
KeySymbol,
IssueTagNumber,
MepsLanguage,
DocumentId,
Track,
Type,
COALESCE(Specialty, ''),
COALESCE(Edition, ''));
