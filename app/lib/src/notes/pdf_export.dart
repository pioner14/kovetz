import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'notes_model.dart';

/// How notes are ordered inside one tag.
enum NoteOrder { source, date }

class PdfOptions {
  const PdfOptions({
    this.includeUntagged = false,
    this.order = NoteOrder.source,
    this.russian = true,
  });

  final bool includeUntagged;
  final NoteOrder order;
  final bool russian;
}

/// TrueType files embedded in the PDF. The font must cover Cyrillic.
class PdfFonts {
  const PdfFonts({
    required this.serif,
    required this.serifBold,
    required this.serifItalic,
    required this.sans,
    required this.sansBold,
    this.fallbacks = const [],
  });

  final Uint8List serif;
  final Uint8List serifBold;
  final Uint8List serifItalic;
  final Uint8List sans;
  final Uint8List sansBold;

  /// Fonts for scripts the main fonts lack (Armenian, Hebrew…): notes may be
  /// written in any language, and a missing glyph would print as an empty box.
  final List<Uint8List> fallbacks;
}

const _green = PdfColor.fromInt(0xFF376754);
const _grey = PdfColor.fromInt(0xFF666B68);
const _light = PdfColor.fromInt(0xFFC8D0CA);

/// Builds the PDF in a background isolate so the interface stays responsive.
Future<Uint8List> buildNotesPdfInBackground(
  NotesCollection collection,
  PdfFonts fonts,
  PdfOptions options,
) => Isolate.run(() => buildNotesPdf(collection, fonts, options));

/// A book of notes: cover with a table of contents by tag, then one section
/// per tag. A note with several tags is printed in each of its sections.
Future<Uint8List> buildNotesPdf(
  NotesCollection collection,
  PdfFonts fonts,
  PdfOptions options,
) async {
  final selected = collection.notes
      .where((note) => note.tags.isNotEmpty || options.includeUntagged)
      .toList();
  final untagged = options.russian ? 'Без тега' : 'Untagged';
  final byTag = <String, List<BackupNote>>{};
  for (final note in selected) {
    for (final tag in note.tags.isEmpty ? [untagged] : note.tags) {
      (byTag[tag] ??= []).add(note);
    }
  }
  if (options.order == NoteOrder.date) {
    for (final notes in byTag.values) {
      notes.sort((a, b) => (a.created ?? '').compareTo(b.created ?? ''));
    }
  }
  final tags = byTag.keys.toList()
    ..sort((a, b) {
      final byCount = byTag[b]!.length.compareTo(byTag[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  // The first pass learns on which page every section starts; the table of
  // contents of the second pass prints those numbers. Page numbers do not
  // change line counts, so both passes lay out identically.
  final pages = <String, int>{};
  await _build(selected, tags, byTag, fonts, options, pages, collect: true);
  return _build(selected, tags, byTag, fonts, options, pages, collect: false);
}

Future<Uint8List> _build(
  List<BackupNote> selected,
  List<String> tags,
  Map<String, List<BackupNote>> byTag,
  PdfFonts fonts,
  PdfOptions options,
  Map<String, int> pages, {
  required bool collect,
}) async {
  final ru = options.russian;
  String tr(String a, String b) => ru ? a : b;
  final fallbacks = [
    for (final bytes in fonts.fallbacks)
      pw.Font.ttf(ByteData.sublistView(bytes)),
  ];
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(ByteData.sublistView(fonts.serif)),
    bold: pw.Font.ttf(ByteData.sublistView(fonts.serifBold)),
    italic: pw.Font.ttf(ByteData.sublistView(fonts.serifItalic)),
    boldItalic: pw.Font.ttf(ByteData.sublistView(fonts.serifBold)),
  );
  final themed = theme.copyWith(
    defaultTextStyle: theme.defaultTextStyle.copyWith(fontFallback: fallbacks),
  );
  final sans = pw.Font.ttf(ByteData.sublistView(fonts.sans));
  final sansBold = pw.Font.ttf(ByteData.sublistView(fonts.sansBold));
  final document = pw.Document(
    title: tr('Мои заметки из JW Library', 'My notes from JW Library'),
    author: 'Kovetz',
    theme: themed,
  );
  const margin = pw.EdgeInsets.fromLTRB(56, 56, 56, 64);
  const maxPages = 100000;

  pw.Widget footer(pw.Context context) => pw.Align(
    alignment: pw.Alignment.center,
    child: pw.Text(
      '${context.pageNumber}',
      style: pw.TextStyle(font: sans, fontSize: 9, color: _grey),
    ),
  );

  final dates = [for (final note in selected) ?note.created]..sort();
  final range = dates.isEmpty
      ? ''
      : '${_month(dates.first, ru)} — ${_month(dates.last, ru)} · ';

  // Cover and table of contents.
  document.addPage(
    pw.MultiPage(
      maxPages: maxPages,
      pageFormat: PdfPageFormat.a4,
      margin: margin,
      footer: footer,
      build: (context) => [
        pw.SizedBox(height: 40),
        pw.Text(
          tr('Личный сборник', 'Personal collection').toUpperCase(),
          style: pw.TextStyle(
            font: sansBold,
            fontSize: 10,
            letterSpacing: 2,
            color: _green,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          tr('Мои заметки из JW Library', 'My notes from JW Library'),
          style: pw.TextStyle(
            font: pw.Font.ttf(ByteData.sublistView(fonts.serifBold)),
            fontSize: 30,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          '$range${selected.length} ${tr('заметок', 'notes')}',
          style: pw.TextStyle(font: sans, fontSize: 11, color: _grey),
        ),
        pw.SizedBox(height: 36),
        pw.Text(
          tr('Оглавление по тегам', 'Contents by tag'),
          style: pw.TextStyle(font: sansBold, fontSize: 13),
        ),
        pw.SizedBox(height: 8),
        for (var i = 0; i < tags.length; i++)
          pw.Link(
            destination: 'tag-$i',
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Flexible(
                    child: pw.Text(
                      tags[i],
                      maxLines: 1,
                      style: pw.TextStyle(
                        font: sans,
                        fontSize: 11,
                        fontFallback: fallbacks,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                      child: pw.Divider(
                        height: 1,
                        thickness: 0.6,
                        color: _light,
                        borderStyle: pw.BorderStyle.dotted,
                      ),
                    ),
                  ),
                  pw.Text(
                    '${pages[tags[i]] ?? 0}',
                    style: pw.TextStyle(font: sans, fontSize: 11, color: _grey),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  // One section per tag.
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    final notes = byTag[tag]!;
    document.addPage(
      pw.MultiPage(
        maxPages: maxPages,
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        footer: footer,
        build: (context) => [
          pw.Anchor(
            name: 'tag-$i',
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (collect) _PageProbe((page) => pages[tag] = page),
                pw.Text(
                  tag,
                  style: pw.TextStyle(
                    font: pw.Font.ttf(ByteData.sublistView(fonts.serifBold)),
                    fontSize: 22,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  ru
                      ? '${notes.length} ${_plural(notes.length)}'
                      : '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
                  style: pw.TextStyle(font: sans, fontSize: 10, color: _grey),
                ),
                pw.SizedBox(height: 18),
              ],
            ),
          ),
          for (final note in notes) ..._entry(note, tag, sans, sansBold, ru),
        ],
      ),
    );
  }
  return document.save();
}

List<pw.Widget> _entry(
  BackupNote note,
  String tag,
  pw.Font sans,
  pw.Font sansBold,
  bool ru,
) {
  final others = note.tags.where((t) => t != tag).toList();
  final date = _date(note.modified ?? note.created);
  // Plain Text widgets, not Padding around them: only Text can continue on
  // the next page, and a long note must be able to.
  final parts = <pw.Widget>[
    pw.Text(
      note.source.label,
      style: pw.TextStyle(font: sansBold, fontSize: 8.5, color: _green),
    ),
    if (note.title.isNotEmpty) ...[
      pw.SizedBox(height: 3),
      pw.Text(
        note.title,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12.5),
      ),
    ],
    if (note.content.isNotEmpty) ...[
      pw.SizedBox(height: 4),
      pw.Text(
        note.content,
        style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
        // Only a spanning Text may continue on the next page.
        overflow: pw.TextOverflow.span,
      ),
    ],
    pw.SizedBox(height: 5),
    pw.Text(
      [
        if (others.isNotEmpty) '${ru ? 'Теги' : 'Tags'}: ${others.join(', ')}',
        ?date,
      ].join('  ·  '),
      style: pw.TextStyle(font: sans, fontSize: 8, color: _grey),
    ),
    pw.SizedBox(height: 14),
  ];
  // Short notes stay together on one page; a note taller than a page is laid
  // out as separate pieces so it can continue. Lines are estimated from the
  // text: a Cyrillic line holds about 60 characters at this size and is about
  // 17 pt tall, so 26 lines is well within a page of about 720 pt.
  final lines = note.content
      .split('\n')
      .fold<int>(0, (sum, line) => sum + (line.length ~/ 60) + 1);
  if (lines > 26) return parts;
  return [
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: parts),
  ];
}

/// Zero-size widget that records the page it is drawn on.
class _PageProbe extends pw.Widget {
  _PageProbe(this.onPage);

  final void Function(int page) onPage;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    box = PdfRect.fromPoints(PdfPoint.zero, PdfPoint.zero);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    onPage(context.pageNumber);
  }
}

String _plural(int n) {
  final last = n % 10, lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 14) return 'заметок';
  if (last == 1) return 'заметка';
  if (last >= 2 && last <= 4) return 'заметки';
  return 'заметок';
}

const _monthsRu = [
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];
const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "ноябрь 2026" from an ISO timestamp.
String _month(String iso, bool ru) {
  final month = int.tryParse(iso.substring(5, 7));
  if (month == null || month < 1 || month > 12) return iso.substring(0, 4);
  final name = (ru ? _monthsRu : _monthsEn)[month - 1];
  return '${ru ? name : name} ${iso.substring(0, 4)}';
}

/// "14.11.2026" from an ISO timestamp, or null.
String? _date(String? iso) {
  if (iso == null || iso.length < 10) return null;
  return '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}';
}
