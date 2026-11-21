// Developer tool, run via flutter test to reuse the synthetic test fixtures.
import 'dart:io';

import 'package:kovetz/notes_export.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/merge_fixtures.dart';

void main() {
  test('Generate the guide PDFs', () async {
    final output = Directory(Platform.environment['GUIDE_PDF_DIR']!);
    final scratch = output.createTempSync('backups-');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final fonts = bundledPdfFonts();
    for (final lang in ['ru', 'en']) {
      final backup = writeGuideBackup(
        scratch,
        name: 'guide-$lang',
        languageCode: lang,
      );
      final notes = await readBackupNotes(backup, languageCode: lang);
      final pdf = await buildNotesPdf(
        notes,
        fonts,
        PdfOptions(russian: lang == 'ru', includeUntagged: true),
      );
      await File('${output.path}/$lang.pdf').writeAsBytes(pdf);
    }
  });
}
