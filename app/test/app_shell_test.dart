import 'dart:io';

import 'package:backup_merge/app_info.dart';
import 'package:backup_merge/main.dart';
import 'package:backup_merge/ui/info_screens.dart';
import 'package:backup_merge/ui/open_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('shell-');
  });
  tearDown(() => deleteScratch(scratch));

  Future<AppSettings> pumpApp(
    WidgetTester tester, {
    double width = 390,
    String language = 'ru',
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(directory: () async => scratch);
    // Real file I/O does not complete inside the test's fake clock.
    await tester.runAsync(() => settings.setLocale(Locale(language)));
    await tester.pumpWidget(BackupMergeApp(settings: settings));
    await tester.pumpAndSettle();
    return settings;
  }

  test('displayed version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version: (\S+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(match.group(1), appVersion);
    expect(int.parse(match.group(2)!), appBuild);
  });

  for (final (language, title, merge, about) in [
    ('ru', 'Что сделаем сегодня?', 'Объединить бэкапы', 'О приложении'),
    ('en', 'What shall we do today?', 'Merge backups', 'About'),
  ]) {
    testWidgets('home, menu and About in $language', (tester) async {
      await pumpApp(tester, language: language);
      expect(find.text(title), findsOneWidget);
      expect(find.text(merge), findsOneWidget);

      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(find.byType(Scaffold)))
              .openAppDrawerTooltip,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(appVersion), findsOneWidget);
      await tester.tap(find.text(about));
      await tester.pumpAndSettle();
      expect(find.text(appDeveloper), findsOneWidget);
      expect(find.textContaining('$appVersion ($appBuild)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (language, help, fullGuide, userGuide) in [
    (
      'ru',
      'Как пользоваться',
      'Открыть полное руководство',
      'Руководство пользователя',
    ),
    ('en', 'How to use', 'Open the full guide', 'User guide'),
  ]) {
    testWidgets('guide links open in $language', (tester) async {
      final originalLauncher = linkLauncher;
      addTearDown(() => linkLauncher = originalLauncher);
      final opened = <Uri>[];
      linkLauncher = (uri) async {
        opened.add(uri);
        return true;
      };
      final guide = Uri.parse('$appGuideUrl$language/');
      await pumpApp(tester, language: language);

      final helpButton = find.byTooltip(help);
      expect(
        find.descendant(
          of: helpButton,
          matching: find.byIcon(Icons.help_outline_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(helpButton);
      await tester.pumpAndSettle();
      expect(find.byType(HowToScreen), findsOneWidget);
      expect(find.text(fullGuide), findsOneWidget);
      await tester.tap(find.text(fullGuide));
      await tester.pumpAndSettle();
      expect(opened, [guide]);

      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(find.byType(Scaffold).first))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(tester.element(find.byType(Scaffold)))
              .openAppDrawerTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(language == 'ru' ? 'О приложении' : 'About'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(userGuide));
      await tester.pumpAndSettle();
      expect(opened, [guide, guide]);
    });
  }

  for (final launchThrows in [false, true]) {
    testWidgets(
      'guide copies its link when the launcher ${launchThrows ? 'throws' : 'fails'}',
      (tester) async {
        final originalLauncher = linkLauncher;
        addTearDown(() => linkLauncher = originalLauncher);
        linkLauncher = (_) async {
          if (launchThrows) throw StateError('No browser');
          return false;
        };
        String? copied;
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await pumpApp(tester);
        await tester.tap(find.byTooltip('Как пользоваться'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть полное руководство'));
        await tester.pumpAndSettle();

        const guide = '${appGuideUrl}ru/';
        expect(copied, guide);
        expect(
          find.text('Не удалось открыть браузер. Ссылка скопирована: $guide'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('home opens the merge screen and goes back', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Объединить бэкапы'));
    await tester.pumpAndSettle();
    expect(
      find.text('Добавьте как минимум два файла .jwlibrary.'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Что сделаем сегодня?'), findsOneWidget);
  });

  testWidgets('language and theme are applied and remembered', (tester) async {
    final settings = await pumpApp(tester);
    await tester.tap(find.text('RU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('What shall we do today?'), findsOneWidget);
    // Saving needs the real clock, so it is checked through runAsync.
    await tester.runAsync(() => settings.setLocale(const Locale('en')));
    expect(File('${scratch.path}/language').readAsStringSync(), 'en');

    await tester.runAsync(() => settings.setThemeMode(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    final restored = AppSettings(directory: () async => scratch);
    await tester.runAsync(restored.load);
    expect(restored.locale, const Locale('en'));
    expect(restored.themeMode, ThemeMode.dark);
  });

  testWidgets('wide window shows the two cards side by side', (tester) async {
    await pumpApp(tester, width: 1100);
    final merge = tester.getTopLeft(find.text('Объединить бэкапы'));
    final export = tester.getTopLeft(find.text('Экспорт заметок'));
    expect(merge.dy, export.dy);
    expect(tester.takeException(), isNull);
  });
}
