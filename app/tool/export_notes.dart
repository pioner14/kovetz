import 'dart:io';
import 'dart:typed_data';

import 'package:backup_merge/notes_export.dart';

/// Developer tool: `dart run tool/export_notes.dart BACKUP FOLDER [--all]
/// [--pdf FILE]` writes the Markdown export of a backup's tagged notes (all
/// notes with --all) and, with --pdf, a PDF book.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: export_notes.dart <backup.jwlibrary> <folder> [--all]',
    );
    exitCode = 64;
    return;
  }
  final notes = await readBackupNotes(args[0]);
  final files = buildMarkdownExport(
    notes,
    MarkdownOptions(includeUntagged: args.contains('--all')),
  );
  await writeMarkdownExport(files, Directory(args[1]));
  final pdf = args.indexOf('--pdf');
  if (pdf >= 0 && pdf + 1 < args.length) {
    Uint8List font(String name) => File('assets/fonts/$name').readAsBytesSync();
    final watch = Stopwatch()..start();
    final bytes = await buildNotesPdfInBackground(
      notes,
      PdfFonts(
        serif: font('NotoSerif-Regular.ttf'),
        serifBold: font('NotoSerif-Bold.ttf'),
        serifItalic: font('NotoSerif-Italic.ttf'),
        sans: font('NotoSans-Regular.ttf'),
        sansBold: font('NotoSans-Bold.ttf'),
        fallbacks: [
          font('NotoSansArmenian-Regular.ttf'),
          font('NotoSansHebrew-Regular.ttf'),
        ],
      ),
      PdfOptions(includeUntagged: args.contains('--all')),
    );
    File(args[pdf + 1]).writeAsBytesSync(bytes);
    stdout.writeln(
      'pdf ${bytes.length ~/ 1024} KiB in ${watch.elapsedMilliseconds / 1000} s',
    );
  }
  final tagged = notes.notes.where((n) => n.tags.isNotEmpty).length;
  stdout.writeln(
    'notes ${notes.notes.length}, tagged $tagged, '
    'tags ${notes.tagCounts.length}, files ${files.length}',
  );
}
