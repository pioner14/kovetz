import 'dart:convert';
import 'dart:io';

import 'package:backup_merge/notes_export.dart';
import 'package:backup_merge/src/notes/bible_books.dart';
import 'package:backup_merge/src/notes/notes_model.dart' show extractNotes;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/merge_fixtures.dart';

BackupNote _note(
  String guid,
  String title, {
  List<String> tags = const ['Study'],
  String content = 'Note body',
}) => BackupNote(
  guid: guid,
  title: title,
  content: content,
  tags: tags,
  source: const NoteSource(NoteSourceKind.bible, 'Genesis 1:1', '0|01|001|001'),
  created: fixtureEarlier,
  modified: fixtureLater,
);

Map<String, String> _markdown(List<BackupNote> notes) => buildMarkdownExport(
  NotesCollection('edge cases', notes),
  const MarkdownOptions(includeUntagged: true, russian: false),
);

Map<String, Object?> _frontMatter(String markdown) {
  final lines = markdown.split('\n');
  expect(lines.first, '---');
  final end = lines.indexOf('---', 1);
  expect(end, greaterThan(1));
  final fields = <String, Object?>{};
  final field = RegExp(r'^([a-z_]+): (.+)$');
  for (final line in lines.getRange(1, end)) {
    final match = field.firstMatch(line);
    expect(match, isNotNull, reason: line);
    final key = match!.group(1)!;
    expect(fields, isNot(contains(key)));
    final value = jsonDecode(match.group(2)!);
    expect(value, anyOf(isA<String>(), isA<List<Object?>>()));
    if (value is List<Object?>) expect(value, everyElement(isA<String>()));
    fields[key] = value;
  }
  return fields;
}

void main() {
  group('Markdown export', () {
    test('paths are portable and unique after sanitizing names', () {
      final stem = 'A' * 205;
      final names = [
        r'Forbidden\/:*?"<>|',
        'Trailing...   ',
        '${stem}x',
        '${stem}y',
        'Case only',
        'case only',
        'Emoji 📝',
        'שלום աշխարհ',
      ];
      final files = _markdown([
        for (var i = 0; i < names.length; i++)
          _note('note-$i', names[i], tags: [names[i]]),
      ]);
      expect(
        files.keys.where((path) => path.startsWith('Notes/')),
        hasLength(names.length),
      );
      expect(
        files.keys.where((path) => path.startsWith('Tags/')),
        hasLength(names.length),
      );
      expect(
        files.keys.map((path) => path.toLowerCase()).toSet(),
        hasLength(files.length),
      );
      for (final path in files.keys) {
        expect(path, isNot(matches(RegExp(r'[\\:*?"<>|]'))));
        expect(path, matches(RegExp(r'^(?:(?:Notes|Tags)/[^/]+|Index)\.md$')));
        for (final segment in path.split('/')) {
          expect(segment.length, lessThanOrEqualTo(120), reason: path);
          final name = segment.replaceFirst(RegExp(r'\.md$'), '');
          expect(name, isNot(matches(RegExp(r'[. ]$'))), reason: path);
        }
      }
      expect(files, contains('Tags/Emoji 📝.md'));
      expect(files, contains('Tags/שלום աշխարհ.md'));
    });

    test('paths avoid Windows device names', () {
      const devices = ['CON', 'NUL', 'COM1', 'LPT1'];
      final files = _markdown([
        for (final device in devices) _note(device, device, tags: [device]),
      ]);
      final reservedPaths = files.keys.where((path) {
        final name = path.split('/').last.split('.').first.toUpperCase();
        return devices.contains(name);
      });
      expect(reservedPaths, isEmpty);
    });

    test('truncation preserves well-formed Unicode in paths', () {
      final files = _markdown([
        _note('emoji-edge', 'Emoji', tags: ['${'A' * 99}📝 tail']),
      ]);
      for (final path in files.keys) {
        expect(utf8.decode(utf8.encode(path)), path);
      }
    });

    test('all generated wikilinks resolve to exported files', () {
      final files = _markdown([
        _note('first', 'First [title]|\nsecond line', tags: ['Study', 'study']),
        _note('second', 'first [TITLE]|\nsecond line', tags: ['x/y [tag]|']),
        _note('untagged', 'Untagged note', tags: []),
      ]);
      final wikilink = RegExp(r'\[\[([^\]|\n]+)\|[^\[\]|\n]*\]\]');
      var links = 0;
      for (final entry in files.entries) {
        final matches = wikilink.allMatches(entry.value).toList();
        expect(
          matches,
          hasLength('[['.allMatches(entry.value).length),
          reason: entry.key,
        );
        for (final match in matches) {
          expect(files, contains('${match.group(1)}.md'), reason: entry.key);
        }
        links += matches.length;
      }
      // Four tag links in the index, four in notes, and four in tag pages.
      expect(links, 12);
    });

    test('note front matter round-trips JSON-style YAML scalars', () {
      final notes = [
        _note('quotes', 'She said "yes": #1'),
        _note('multiline', 'First line\n---\nSecond line'),
        _note('backslashes', r'Path: C:\notes\"draft" #2'),
      ];
      final files = _markdown(notes);
      final metadata = [
        for (final entry in files.entries)
          if (entry.key.startsWith('Notes/')) _frontMatter(entry.value),
      ];
      expect(
        metadata,
        unorderedEquals([
          for (final note in notes)
            {
              'title': note.title,
              'source': note.source.label,
              'tags': ['jw/Study'],
              'jw_tags': note.tags,
              'created': note.created,
              'modified': note.modified,
              'jw_guid': note.guid,
            },
        ]),
      );
    });
  });

  group('Bible references', () {
    for (final (book, chapter, verse, ru, en) in [
      (1, 1, 1, 'Бытие 1:1', 'Genesis 1:1'),
      (1, 1, null, 'Бытие 1', 'Genesis 1'),
      (1, null, 1, 'Бытие', 'Genesis'),
      (19, 23, 1, 'Псалом 23:1', 'Psalm 23:1'),
      (19, 23, null, 'Псалом 23', 'Psalm 23'),
      (19, null, null, 'Псалмы', 'Psalms'),
      (19, 0, null, 'Псалмы', 'Psalms'),
      (66, 22, 21, 'Откровение 22:21', 'Revelation 22:21'),
      (0, null, null, 'Книга 0', 'Book 0'),
      (67, 1, 2, 'Книга 67', 'Book 67'),
    ]) {
      test('book $book, chapter $chapter, verse $verse in both languages', () {
        expect(bibleReference(book, chapter, verse, russian: true), ru);
        expect(bibleReference(book, chapter, verse, russian: false), en);
      });
    }
  });

  group('Publication citations', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      addTearDown(db.close);
      for (final schema in ['shared.sql', 'v14.sql']) {
        db.execute(File('test/fixtures/$schema').readAsStringSync());
      }
    });

    for (final (description, symbol, issue, title, block, ru, en) in [
      (
        'dated issue',
        'w',
        19910215,
        'Article',
        3,
        'w91 15/2 «Article», абз. 3',
        'w91 15/2 «Article», par. 3',
      ),
      ('monthly issue', 'w', 20160100, null, null, 'w16.01', 'w16.01'),
      ('paragraph only', null, 0, null, 3, 'абз. 3', 'par. 3'),
    ]) {
      test('$description in both languages', () {
        db.execute(
          '''
          INSERT INTO Location
            (LocationId, DocumentId, KeySymbol, IssueTagNumber, Title,
             MepsLanguage, Type)
          VALUES (1, 100, ?, ?, ?, 0, 0)
        ''',
          [symbol, issue, title],
        );
        db.execute(
          '''
          INSERT INTO Note (Guid, LocationId, Content, BlockType, BlockIdentifier)
          VALUES ('publication', 1, 'Note body', ?, ?)
        ''',
          [block == null ? 0 : 1, block],
        );
        for (final (russian, label) in [(true, ru), (false, en)]) {
          final notes = extractNotes(
            db,
            backupName: 'citation',
            russian: russian,
          );
          expect(notes.notes.single.source.kind, NoteSourceKind.publication);
          expect(notes.notes.single.source.label, label);
        }
      });
    }
  });

  group('PDF export', () {
    late PdfFonts fonts;
    setUpAll(() => fonts = bundledPdfFonts());

    Future<void> expectPdf(List<BackupNote> notes, PdfOptions options) async {
      final bytes = await buildNotesPdf(
        NotesCollection('edge cases', notes),
        fonts,
        options,
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    }

    test('zero notes', () => expectPdf([], const PdfOptions()));

    test('one note with 3000 lines', () async {
      final content = List.generate(3000, (i) => 'Line ${i + 1}').join('\n');
      await expectPdf([
        _note('long', 'Long note', content: content),
      ], const PdfOptions());
    });

    test(
      'only untagged notes with untagged notes excluded',
      () => expectPdf([
        _note('loose', 'Untagged note', tags: []),
      ], const PdfOptions(includeUntagged: false)),
    );

    test(
      'English export',
      () => expectPdf([
        _note('english', 'English note'),
      ], const PdfOptions(russian: false)),
    );

    test(
      'one tag with a 200-character name',
      () => expectPdf([
        _note('tag', 'Long tag', tags: ['A' * 200]),
      ], const PdfOptions()),
    );
  });
}
