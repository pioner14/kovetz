import 'dart:io';

import 'package:backup_merge/notes_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('notes-export-');
  });
  tearDown(() => scratch.delete(recursive: true));

  test('reads notes with sources in reading order', () async {
    final notes = await readBackupNotes(writeNotesBackup(scratch));
    expect(notes.notes.map((n) => n.source.label), [
      'Псалом 23:1',
      'Римлянам 15:13',
      'w91 15/2 «Соответствующий выкуп для всех», абз. 3',
      'Без привязки к публикации',
    ]);
    final ransom = notes.notes.singleWhere((n) => n.title == 'Выкуп');
    expect(ransom.tags, [
      'English',
    ], reason: 'Playlist tags are not user tags.');
    expect(notes.tagCounts, {'Ободрение': 2, 'English': 1, 'english': 1});
  });

  test('English labels use English book names', () async {
    final notes = await readBackupNotes(
      writeNotesBackup(scratch),
      languageCode: 'en',
    );
    expect(notes.notes.first.source.label, 'Psalm 23:1');
  });

  test('Markdown export: one file per tagged note, indexes per tag', () async {
    final notes = await readBackupNotes(writeNotesBackup(scratch));
    final files = buildMarkdownExport(
      notes,
      MarkdownOptions(exportedAt: DateTime.utc(2026, 11, 21)),
    );
    final noteFiles = files.keys
        .where((k) => k.startsWith('Заметки/'))
        .toList();
    expect(noteFiles, hasLength(3), reason: 'Untagged notes are excluded.');
    expect(noteFiles.every((k) => !k.contains(':')), isTrue);
    final tagFiles = files.keys.where((k) => k.startsWith('Теги/')).toSet();
    expect(
      tagFiles.map((k) => k.toLowerCase()).toSet(),
      hasLength(tagFiles.length),
      reason: 'Case-only different tags need distinct files.',
    );
    final romans = files.entries.singleWhere(
      (e) => e.key.startsWith('Заметки/Римлянам'),
    );
    expect(romans.value, contains('source: "Римлянам 15:13"'));
    expect(romans.value, contains('jw/Ободрение'));
    final encouragement = files['Теги/Ободрение.md']!;
    expect(encouragement, contains('Заметок: 2.'));
    expect(
      RegExp(r'\[\[Заметки/').allMatches(encouragement),
      hasLength(2),
      reason: 'A note with two tags is listed in both indexes once.',
    );
    final psalm = files.entries.singleWhere(
      (e) => e.key.startsWith('Заметки/Псалом'),
    );
    expect(psalm.value, contains(r'title: "Пастух: \"Иегова\""'));
    expect(psalm.value, contains('Строка 1\nСтрока 2'));
    expect(files['Указатель.md'], contains('Заметок: 3'));

    final all = buildMarkdownExport(
      notes,
      const MarkdownOptions(includeUntagged: true),
    );
    expect(all.keys, contains('Теги/Без тега.md'));

    final out = Directory('${scratch.path}/vault');
    await writeMarkdownExport(files, out);
    expect(File('${out.path}/Теги/Ободрение.md').existsSync(), isTrue);
  });

  test('PDF export builds a book with cover and one section per tag', () async {
    final notes = await readBackupNotes(writeNotesBackup(scratch));
    final bytes = await buildNotesPdf(
      notes,
      bundledPdfFonts(),
      const PdfOptions(),
    );
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    final text = String.fromCharCodes(bytes);
    // Cover, "Ободрение", "English"; "english" has no note of its own that
    // is tagged, and untagged notes are excluded by default.
    // The page tree states its size; other /Count entries (outlines) are 0.
    final pages = RegExp(r'/Count (\d+)')
        .allMatches(text)
        .map((m) => int.parse(m.group(1)!))
        .reduce((a, b) => a > b ? a : b);
    expect(pages, greaterThanOrEqualTo(3));
    expect(bytes.length, greaterThan(20000), reason: 'fonts are embedded');
    final withUntagged = await buildNotesPdf(
      notes,
      bundledPdfFonts(),
      const PdfOptions(includeUntagged: true, order: NoteOrder.date),
    );
    expect(withUntagged.length, greaterThan(bytes.length));
  });
}
