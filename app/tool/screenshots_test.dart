// Developer tool: flutter test --no-pub --update-goldens tool/screenshots_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:backup_merge/main.dart';
import 'package:backup_merge/ui/home_screen.dart' show LanguageChip;
import 'package:backup_merge/ui/theme.dart' show interfaceFont;
import 'package:backup_merge/ui/widgets.dart';
import 'package:backup_merge/updates.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/merge_fixtures.dart';

class _GuideFile extends XFile {
  _GuideFile(super.path, String date)
    : _modified = DateTime.parse(date),
      _size = File(path).lengthSync();

  final DateTime _modified;
  final int _size;

  @override
  Future<DateTime> lastModified() async => _modified;

  @override
  Future<int> length() async => _size;
}

class _Picker extends FileSelectorPlatform {
  _Picker(this.files);
  final List<XFile> files;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => files.first;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => files;
}

Future<void> _loadFont(String family, String path) {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  return loader.load();
}

const _frame = ValueKey('guide-screenshot');
const _phone = Size(390, 844);
const _pixelRatio = 2.0;

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  final deadline = Stopwatch()..start();
  while (target.evaluate().isEmpty &&
      deadline.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _loadFont(interfaceFont, 'assets/fonts/Manrope.ttf');
    await _loadFont(
      'MaterialIcons',
      '../.work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  for (final lang in ['ru', 'en']) {
    testWidgets('User guide screenshots ($lang)', (tester) async {
      final root = Directory('../.work/test-runs')..createSync(recursive: true);
      final scratch = root.createTempSync('guide-shots-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final russian = lang == 'ru';

      Finder label(String ru, String en) => find.text(russian ? ru : en);
      Finder tile(String ru, String en) =>
          find.widgetWithText(ListTile, russian ? ru : en);
      Finder dialogTile(String ru, String en) => find.descendant(
        of: find.byType(SimpleDialog),
        matching: tile(ru, en),
      );
      Finder filled(String ru, String en) => find.ancestor(
        of: label(ru, en),
        matching: find.bySubtype<FilledButton>(),
      );
      Finder textButton(String ru, String en) =>
          find.widgetWithText(TextButton, russian ? ru : en);
      Finder choice(String ru, String en) =>
          find.widgetWithText(ChoiceTile, russian ? ru : en);
      Finder iconButton(IconData icon) => find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(IconButton),
      );
      Finder feature(String ru, String en) =>
          find.ancestor(of: label(ru, en), matching: find.byType(InkWell));

      tester.view.physicalSize = _phone * _pixelRatio;
      tester.view.devicePixelRatio = _pixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> shot(String id, List<Finder> targets) async {
        final ratio = tester.view.devicePixelRatio;
        final annotations = [
          for (final (index, target) in targets.indexed)
            {
              'n': index + 1,
              'rect': [
                for (final value in _targetRect(tester, id, target))
                  (value * ratio).round(),
              ],
            },
        ];
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_frame),
        );
        final image = boundary.toImageSync(pixelRatio: ratio);
        try {
          await expectLater(image, matchesGoldenFile('shots/$lang/$id.png'));
        } finally {
          image.dispose();
        }
        if (autoUpdateGoldenFiles) {
          File('tool/shots/$lang/$id.json').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(annotations)}\n',
          );
        }
      }

      Future<void> tap(Finder target) async {
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      final originalPicker = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = originalPicker);
      const phoneDate = '2026-11-20T10:00:00Z';
      const tabletDate = '2026-11-18T10:00:00Z';
      final phone = writeGuideBackup(
        scratch,
        name: russian ? 'Телефон_2026-11-20' : 'Phone_2026-11-20',
        languageCode: lang,
        date: phoneDate,
      );
      final tablet = writeGuideBackup(
        scratch,
        name: russian ? 'Планшет_2026-11-18' : 'Tablet_2026-11-18',
        languageCode: lang,
        date: tabletDate,
        firstNote: 6,
      );
      FileSelectorPlatform.instance = _Picker([
        _GuideFile(phone, phoneDate),
        _GuideFile(tablet, tabletDate),
      ]);

      final settings = AppSettings(directory: () async => scratch);
      final updates = UpdateController(
        settings,
        checker: UpdateChecker(fetch: (_) async => '[]'),
      );
      await tester.runAsync(() async {
        await settings.setLocale(Locale(lang));
        await settings.setThemeMode(ThemeMode.light);
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: BackupMergeApp(settings: settings, updates: updates),
        ),
      );
      await tester.pumpAndSettle();
      final homeContext = tester.element(find.byType(HomeScreen));
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/app_icon.png'),
          homeContext,
        );
        await precacheImage(
          const AssetImage('assets/images/success.png'),
          homeContext,
        );
      });
      await tester.pump();

      final merge = feature('Объединить бэкапы', 'Merge backups');
      final export = feature('Экспорт заметок', 'Export notes');
      final menu = iconButton(Icons.menu);
      final languageChip = find.descendant(
        of: find.byType(LanguageChip),
        matching: find.byType(ActionChip),
      );
      await shot('home', [merge, export, menu, languageChip]);
      await tap(languageChip);
      await shot('language_dialog', [
        dialogTile('Как в системе', 'System default'),
        dialogTile('Русский', 'Русский'),
        dialogTile('English', 'English'),
      ]);
      Future<void> back() async {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }

      await back();
      await tap(menu);
      final updatesItem = tile('Обновления', 'Updates');
      await shot('drawer', [
        tile('Объединить бэкапы', 'Merge backups'),
        tile('Экспорт заметок', 'Export notes'),
        tile('Язык', 'Language'),
        updatesItem,
        tile('Как пользоваться', 'How to use'),
      ]);
      await tap(tile('Тема', 'Theme'));
      await shot('theme_dialog', [
        dialogTile('Системная', 'System'),
        dialogTile('Светлая', 'Light'),
        dialogTile('Тёмная', 'Dark'),
      ]);
      await back();
      await tap(updatesItem);
      await shot('updates', [
        filled('Проверить обновления', 'Check for updates'),
        find.byType(Switch),
      ]);
      await back();
      await tap(menu);
      await tap(tile('О приложении', 'About'));
      await shot('about', [
        tile('Разработчик', 'Developer'),
        tile('Исходный код — GitHub', 'Source code — GitHub'),
      ]);
      await back();

      await tap(merge);
      final chooseFiles = filled('Выбрать файлы', 'Choose files');
      await shot('merge_files_empty', [
        chooseFiles,
        iconButton(Icons.arrow_back_rounded),
      ]);
      await tap(chooseFiles);
      final primary = find.byType(FilterChip).first;
      await tap(primary);
      final next = filled('Далее', 'Next');
      await shot('merge_files_two', [
        primary,
        iconButton(Icons.close_rounded).first,
        next,
      ]);
      await tap(next);
      final mergeButton = filled('Объединить', 'Merge');
      await shot('merge_rules', [
        choice('Самая свежая версия', 'Newest version'),
        choice('Из основного бэкапа', 'From the primary backup').last,
        mergeButton,
      ]);
      await tester.tap(mergeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await shot('merge_progress', [
        textButton('Отменить', 'Cancel'),
        find.byType(CircularProgressIndicator).first,
      ]);
      await _waitFor(tester, label('Готово', 'Done'));
      await shot('merge_done', [
        find.byType(GridView),
        filled('Сохранить бэкап и отчёт', 'Save backup and report'),
        filled(
          'Экспортировать заметки из результата',
          'Export notes from the result',
        ),
        textButton('Объединить заново', 'Merge again'),
      ]);
      await back();

      await tap(export);
      await tester.tap(filled('Выбрать бэкап', 'Choose a backup'));
      await _waitFor(tester, find.byType(TextField));
      final exportButton = filled('Экспортировать', 'Export');
      await shot('export_overview', [
        find.byType(TextField),
        find.byType(FilterChip).first,
        find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Card),
            )
            .first,
        exportButton,
      ]);
      await tap(exportButton);
      final pdf = choice('PDF', 'PDF');
      final create = filled('Создать', 'Create');
      await shot('export_format', [
        choice('Markdown для Obsidian', 'Markdown for Obsidian'),
        pdf,
        find.byType(Switch),
        create,
      ]);
      await tap(pdf);
      await shot('export_pdf_options', [
        choice('По Библии и публикациям', 'By Bible and publication'),
        choice('По дате', 'By date'),
        create,
      ]);
    });
  }
}

List<double> _targetRect(WidgetTester tester, String id, Finder target) {
  expect(target, findsOneWidget, reason: id);
  final rect = tester.getRect(target);
  expect(
    rect.size.isEmpty ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > _phone.width ||
        rect.bottom > _phone.height,
    isFalse,
    reason: '$id: $target is outside the viewport ($rect)',
  );
  return [rect.left, rect.top, rect.width, rect.height];
}
