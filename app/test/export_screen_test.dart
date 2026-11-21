import 'dart:io';

import 'package:backup_merge/main.dart';
import 'package:backup_merge/ui/export_notes_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('export-screen-');
  });
  tearDown(() => deleteScratch(scratch));

  testWidgets('overview filters notes and opens the format step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backup = writeNotesBackup(scratch);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ExportNotesScreen(initialBackup: backup),
      ),
    );
    // Reading runs in a background isolate on the real clock.
    for (
      var i = 0;
      i < 100 && find.text('Читаем заметки…').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.textContaining('заметок с тегами'), findsOneWidget);
    expect(find.text('Римлянам 15:13'), findsOneWidget);
    expect(find.text('Псалом 23:1'), findsOneWidget);
    expect(
      find.textContaining('Свободная заметка'),
      findsNothing,
      reason: 'Untagged notes are not listed.',
    );

    // A tag filter keeps only its notes.
    await tester.tap(find.text('English 1'));
    await tester.pumpAndSettle();
    expect(find.text('Римлянам 15:13'), findsNothing);
    expect(find.textContaining('Соответствующий выкуп'), findsOneWidget);
    await tester.tap(find.text('English 1'));
    await tester.pumpAndSettle();

    // Search narrows the list and can come up empty.
    await tester.enterText(find.byType(TextField), 'надежд');
    await tester.pumpAndSettle();
    expect(find.text('Римлянам 15:13'), findsOneWidget);
    expect(find.text('Псалом 23:1'), findsNothing);
    await tester.enterText(find.byType(TextField), 'такого нет');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Экспортировать'));
    await tester.pumpAndSettle();
    expect(find.text('Markdown для Obsidian'), findsOneWidget);
    expect(find.text('Будет экспортировано заметок: 3'), findsOneWidget);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Порядок внутри тега'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Будет экспортировано заметок: 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home opens the export screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(directory: () async => scratch);
    await tester.runAsync(() => settings.setLocale(const Locale('ru')));
    await tester.pumpWidget(BackupMergeApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Экспорт заметок'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрать бэкап'), findsOneWidget);
  });
}
