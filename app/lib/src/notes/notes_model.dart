import 'package:sqlite3/sqlite3.dart';

import 'bible_books.dart';

/// What a note is attached to in JW Library.
enum NoteSourceKind { bible, publication, none }

/// Human-readable place of a note and a key that orders notes the way a
/// reader expects: Bible books first, then publications, then loose notes.
class NoteSource {
  const NoteSource(this.kind, this.label, this.sortKey);

  final NoteSourceKind kind;

  /// "Римлянам 15:13", "w91 15/2 «Соответствующий выкуп для всех», абз. 1".
  final String label;
  final String sortKey;
}

/// A personal note with its user tags, as stored in a JW Library backup.
class BackupNote {
  const BackupNote({
    required this.guid,
    required this.title,
    required this.content,
    required this.tags,
    required this.source,
    required this.created,
    required this.modified,
  });

  final String guid;
  final String title;
  final String content;
  final List<String> tags;
  final NoteSource source;
  final String? created;
  final String? modified;

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;
}

/// All notes of one backup, ordered by source.
class NotesCollection {
  const NotesCollection(this.backupName, this.notes);

  final String backupName;
  final List<BackupNote> notes;

  /// User tags with the number of notes in each, most used first.
  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final note in notes) {
      for (final tag in note.tags) {
        counts.update(tag, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return Map.fromEntries(entries);
  }
}

/// Reads notes from a normalized (current schema) JW Library database.
///
/// Only user tags (Tag.Type 1) are kept; favourites and playlists are other
/// tag types. Notes without any text are skipped.
NotesCollection extractNotes(
  Database db, {
  required String backupName,
  bool russian = true,
}) {
  final tags = <int, List<String>>{};
  for (final row in db.select('''
    SELECT m.NoteId, t.Name FROM TagMap m JOIN Tag t USING (TagId)
    WHERE m.NoteId IS NOT NULL AND t.Type = 1
    ORDER BY m.NoteId, m.Position
  ''')) {
    final name = (row['Name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;
    (tags[row['NoteId'] as int] ??= []).add(name);
  }
  final notes = <BackupNote>[];
  for (final row in db.select('''
    SELECT n.NoteId, n.Guid, n.Title, n.Content, n.Created, n.LastModified,
           n.BlockType, n.BlockIdentifier,
           l.BookNumber, l.ChapterNumber, l.DocumentId, l.KeySymbol,
           l.IssueTagNumber, l.Title AS LocationTitle
    FROM Note n LEFT JOIN Location l USING (LocationId)
  ''')) {
    final note = BackupNote(
      guid: row['Guid'] as String,
      title: (row['Title'] as String? ?? '').trim(),
      content: (row['Content'] as String? ?? '').trim(),
      tags: List.unmodifiable(tags[row['NoteId'] as int] ?? const []),
      source: _source(row, russian: russian),
      created: row['Created'] as String?,
      modified: row['LastModified'] as String?,
    );
    if (!note.isEmpty) notes.add(note);
  }
  notes.sort((a, b) {
    final bySource = a.source.sortKey.compareTo(b.source.sortKey);
    return bySource != 0 ? bySource : a.guid.compareTo(b.guid);
  });
  return NotesCollection(backupName, List.unmodifiable(notes));
}

String _pad(Object? value, int width) => '${value ?? 0}'.padLeft(width, '0');

NoteSource _source(Row row, {required bool russian}) {
  final book = row['BookNumber'] as int?;
  final chapter = row['ChapterNumber'] as int?;
  final blockType = row['BlockType'] as int? ?? 0;
  final block = row['BlockIdentifier'] as int?;
  if (book != null && book > 0) {
    final verse = blockType == 2 ? block : null;
    return NoteSource(
      NoteSourceKind.bible,
      bibleReference(book, chapter, verse, russian: russian),
      '0|${_pad(book, 2)}|${_pad(chapter, 3)}|${_pad(verse, 3)}',
    );
  }
  final symbol = row['KeySymbol'] as String?;
  if (symbol == null && row['DocumentId'] == null) {
    return NoteSource(
      NoteSourceKind.none,
      russian ? 'Без привязки к публикации' : 'Not linked to a publication',
      '2',
    );
  }
  final issue = row['IssueTagNumber'] as int? ?? 0;
  final citation = [symbol ?? '', ?_issue(issue)].join('').trim();
  final title = (row['LocationTitle'] as String?)?.trim();
  final paragraph = blockType == 1 && block != null
      ? (russian ? 'абз. $block' : 'par. $block')
      : null;
  final publication = [
    if (citation.isNotEmpty) citation,
    if (title != null && title.isNotEmpty) '«$title»',
  ].join(' ');
  final label = [
    if (publication.isNotEmpty) publication,
    ?paragraph,
  ].join(', ');
  return NoteSource(
    NoteSourceKind.publication,
    label.isEmpty ? (russian ? 'Публикация' : 'Publication') : label,
    '1|${symbol ?? ''}|${_pad(issue, 8)}|${_pad(row['DocumentId'], 10)}|'
    '${_pad(block, 4)}',
  );
}

/// Issue in JW citation style: "91 15/2" for a dated issue (w91 15/2),
/// "16.01" for a monthly one (w16.01); null when there is no issue.
String? _issue(int issue) {
  if (issue <= 0) return null;
  final year = issue ~/ 10000;
  final month = (issue ~/ 100) % 100;
  final day = issue % 100;
  final yy = _pad(year % 100, 2);
  if (month == 0) return yy;
  if (day == 0) return '$yy.${_pad(month, 2)}';
  return '$yy $day/$month';
}
