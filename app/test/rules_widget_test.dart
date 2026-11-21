import 'dart:typed_data';

import 'package:kovetz/main.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A picked file that never touches the disk: real file I/O does not finish
/// inside a widget test's fake clock.
class FakeFile extends XFile {
  FakeFile(String path, int byte)
    : super.fromData(Uint8List.fromList([byte]), path: path, length: 1);

  @override
  Future<DateTime> lastModified() async => DateTime.utc(2026, 11, 20);

  @override
  Future<int> length() async => 1;
}

class Picker extends FileSelectorPlatform {
  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => [
    FakeFile('/source-a.jwlibrary', 1),
    FakeFile('/source-b.jwlibrary', 2),
  ];
}

void main() {
  for (final locale in ['ru', 'en']) {
    for (final width in [390.0, 1100.0]) {
      testWidgets('merge steps $locale at $width', (tester) async {
        final oldPicker = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = Picker();
        addTearDown(() => FileSelectorPlatform.instance = oldPicker);
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ru = locale == 'ru';
        String t(String a, String b) => ru ? a : b;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const MergeScreen(),
          ),
        );

        // Step 1: the next button waits for two files.
        final next = find.widgetWithText(FilledButton, t('Далее', 'Next'));
        expect(tester.widget<FilledButton>(next).onPressed, isNull);
        await tester.tap(find.text(t('Выбрать файлы', 'Choose files')));
        await tester.pumpAndSettle();
        expect(find.text('source-a.jwlibrary'), findsOneWidget);
        expect(find.text('source-b.jwlibrary'), findsOneWidget);
        expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

        // The star makes a backup primary and a second tap clears it.
        final star = find.byType(FilterChip).last;
        await tester.tap(star);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(star).selected, isTrue);
        await tester.tap(star);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(star).selected, isFalse);

        // Removing a file disables "next" again.
        await tester.tap(find.byTooltip(t('Убрать файл', 'Remove file')).last);
        await tester.pumpAndSettle();
        expect(find.text('source-b.jwlibrary'), findsNothing);
        expect(tester.widget<FilledButton>(next).onPressed, isNull);
        await tester.tap(find.text(t('Выбрать файлы', 'Choose files')));
        await tester.pumpAndSettle();

        // Step 2: rules; the first choice of each rule is selected.
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.text(t('Заметки с одинаковым ID', 'Notes with the same ID')),
          findsOneWidget,
        );
        await tester.tap(
          find.text(t('Из основного бэкапа', 'From the primary backup')).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, t('Объединить', 'Merge')),
          findsOneWidget,
        );

        // The back arrow returns to the previous step.
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(
          find.text(t('Добавьте файлы .jwlibrary', 'Add .jwlibrary files')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
