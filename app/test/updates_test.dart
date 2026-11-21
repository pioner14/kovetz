import 'dart:convert';
import 'dart:io';

import 'package:kovetz/main.dart';
import 'package:kovetz/ui/theme.dart';
import 'package:kovetz/ui/updates_screen.dart';
import 'package:kovetz/updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/merge_fixtures.dart';

String feed(List<Map<String, Object?>> releases) => jsonEncode(releases);

Map<String, Object?> release(
  String tag, {
  List<String> files = const [],
  bool draft = false,
  bool prerelease = false,
  String body = '',
}) => {
  'tag_name': tag,
  'html_url': 'https://example.test/releases/$tag',
  'draft': draft,
  'prerelease': prerelease,
  'body': body,
  'assets': [
    for (final file in files)
      {
        'name': file,
        'browser_download_url': 'https://example.test/download/$tag/$file',
      },
  ],
};

void main() {
  test('versions are parsed and compared by their numbers', () {
    expect(parseVersion('v0.5.1'), [0, 5, 1]);
    expect(parseVersion('1.2.3-beta+4'), [1, 2, 3]);
    expect(parseVersion('release'), isNull);
    expect(compareVersions([0, 5, 1], [0, 5, 0]), greaterThan(0));
    expect(compareVersions([0, 10, 0], [0, 9, 9]), greaterThan(0));
    expect(compareVersions([1, 0], [1, 0, 0]), 0);
    expect(compareVersions([0, 4, 3], [0, 5]), lessThan(0));
  });

  test(
    'picks the newest release of this app, ignoring drafts and old tools',
    () {
      final found = newestRelease(
        feed([
          // The old Python tool: newer number, but no app files.
          release('1.2.3'),
          release(
            'v0.9.0',
            files: ['kovetz-0.9.0-linux-x86_64.AppImage'],
            draft: true,
          ),
          release('v0.5.0', files: ['kovetz-0.5.0-android-arm64.apk']),
          release(
            'v0.6.0',
            files: [
              'kovetz-0.6.0-android-arm64.APK',
              'kovetz-0.6.0-linux-checksums.txt',
              'kovetz-0.6.0-LINUX-x86_64.AppImage',
              'kovetz-0.6.0-windows-checksums.txt',
              'kovetz-0.6.0-WINDOWS-x64-setup.EXE',
              'notes.txt',
            ],
            prerelease: true,
            body: 'Новое.',
          ),
        ]),
      )!;
      expect(found.version, '0.6.0');
      expect(found.prerelease, isTrue);
      expect(found.notes, 'Новое.');
      expect(found.assets.keys, isNot(contains('notes.txt')));
      expect(
        found.assetFor('android').toString(),
        endsWith('-android-arm64.APK'),
      );
      expect(
        found.assetFor('linux').toString(),
        endsWith('-LINUX-x86_64.AppImage'),
      );
      expect(
        found.assetFor('windows').toString(),
        endsWith('-WINDOWS-x64-setup.EXE'),
      );
      expect(newestRelease(feed([release('1.2.3')])), isNull);
      expect(() => newestRelease('not json'), throwsA(isA<UpdateFailure>()));
      expect(() => newestRelease('{}'), throwsA(isA<UpdateFailure>()));
    },
  );

  test('the checker reports newer, same and failed', () async {
    Future<UpdateResult> run(String current, String body) =>
        UpdateChecker(fetch: (_) async => body, current: current).check();
    final body = feed([
      release('v0.6.0', files: ['kovetz-0.6.0-android-arm64.apk']),
    ]);
    expect((await run('0.5.0', body)).available, isTrue);
    expect((await run('0.6.0', body)).available, isFalse);
    expect((await run('0.7.0', body)).available, isFalse);
    expect((await run('0.5.0', '[]')).latest, isNull);
    await expectLater(
      UpdateChecker(fetch: (_) async => throw const SocketException('x'))
          .check(),
      throwsA(
        isA<UpdateFailure>().having(
          (e) => e.kind,
          'kind',
          UpdateErrorKind.network,
        ),
      ),
    );
  });

  group('screen and controller', () {
    late Directory scratch;
    setUp(() async {
      final root = Directory('../.work/test-runs')..createSync(recursive: true);
      scratch = await root.createTemp('updates-');
    });
    tearDown(() => deleteScratch(scratch));

    Future<(AppSettings, UpdateController, List<Uri>)> pump(
      WidgetTester tester,
      Future<String> Function(Uri) fetch,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(directory: () async => scratch);
      final opened = <Uri>[];
      final updates = UpdateController(
        settings,
        checker: UpdateChecker(fetch: fetch, current: '0.5.0'),
        open: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: UpdatesScreen(settings: settings, updates: updates),
        ),
      );
      return (settings, updates, opened);
    }

    testWidgets('a new version can be found and downloaded', (tester) async {
      final (_, _, opened) = await pump(
        tester,
        (_) async => feed([
          release(
            'v0.6.0',
            files: [
              'kovetz-0.6.0-linux-x86_64.AppImage',
              'kovetz-0.6.0-windows-x64-setup.exe',
              'kovetz-0.6.0-macos-universal.zip',
              'kovetz-0.6.0-android-arm64.apk',
            ],
            body: 'Что нового',
          ),
        ]),
      );
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(find.text('Доступна версия 0.6.0'), findsOneWidget);
      expect(find.text('Что нового'), findsOneWidget);
      await tester.tap(find.text('Скачать'));
      await tester.pumpAndSettle();
      // The file of the platform the test runs on is opened.
      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'linux';
      expect(opened.single.toString(), contains('kovetz-0.6.0-$platform'));
    });

    testWidgets('up to date and failure are explained', (tester) async {
      var fail = false;
      await pump(tester, (_) async {
        if (fail) throw const SocketException('offline');
        return feed([
          release('v0.5.0', files: ['kovetz-0.5.0-android-arm64.apk']),
        ]);
      });
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(find.text('У вас последняя версия.'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет связи с GitHub'), findsOneWidget);
    });

    test('automatic check is off by default and runs once a day', () async {
      final settings = AppSettings(directory: () async => scratch);
      var requests = 0;
      var clock = DateTime.utc(2026, 11, 21, 10);
      final updates = UpdateController(
        settings,
        checker: UpdateChecker(
          current: '0.5.0',
          fetch: (_) async {
            requests++;
            return feed([
              release('v0.6.0', files: ['kovetz-0.6.0-android-arm64.apk']),
            ]);
          },
        ),
        now: () => clock,
      );
      await updates.checkAutomatically();
      expect(requests, 0, reason: 'The app never goes online unasked.');

      await settings.setAutoUpdateCheck(true);
      await updates.checkAutomatically();
      expect(requests, 1);
      expect(updates.showBanner, isTrue);
      updates.dismissBanner();
      expect(updates.showBanner, isFalse);

      clock = clock.add(const Duration(hours: 5));
      await updates.checkAutomatically();
      expect(requests, 1, reason: 'Checked less than a day ago.');
      clock = clock.add(const Duration(hours: 20));
      await updates.checkAutomatically();
      expect(requests, 2);

      final restored = AppSettings(directory: () async => scratch);
      await restored.load();
      expect(restored.autoUpdateCheck, isTrue);
      expect(restored.lastUpdateCheck, isNotNull);
    });
  });
}
