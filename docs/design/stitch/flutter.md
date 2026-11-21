# Backup Merge — Flutter Theme & Widget Guide

Готовая спецификация для переноса дизайн-системы и всех 9 экранов во Flutter (Material 3).

---

## 1. Зависимости (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1
  material_symbols_icons: ^4.2719.3 # или встроенные Icons.*_rounded
```

---

## 2. Тема приложения (`lib/theme/app_theme.dart`)

Все цвета, скругления и шрифты точно соответствуют дизайн-системе:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const brandGreen = Color(0xFF376754);
  static const success = Color(0xFF2E6F4E);
  static const successContainer = Color(0xFFD3EFE0);
  static const onSuccessContainer = Color(0xFF0E3B25);
  static const warningContainer = Color(0xFFF7E5CC);
  static const onWarningContainer = Color(0xFF472A06);
}

class AppTheme {
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF376754),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD3E7DC),
    onPrimaryContainer: Color(0xFF112E22),
    secondary: Color(0xFF506259),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE1F6EA),
    onSecondaryContainer: Color(0xFF1E332A),
    tertiary: Color(0xFF693837),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F3),
    onSurface: Color(0xFF191C1B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F2ED),
    surfaceContainer: Color(0xFFEBECE7),
    surfaceContainerHigh: Color(0xFFE4E6E0),
    surfaceContainerHighest: Color(0xFFDDDFD9),
    onSurfaceVariant: Color(0xFF454D48),
    outline: Color(0xFF717974),
    outlineVariant: Color(0xFFC8D0CA),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF9FD1BA),
    onPrimary: Color(0xFF003828),
    primaryContainer: Color(0xFF1E4F3D),
    onPrimaryContainer: Color(0xFFC8FCE3),
    secondary: Color(0xFFB7CBC0),
    onSecondary: Color(0xFF22342C),
    secondaryContainer: Color(0xFF384B42),
    onSecondaryContainer: Color(0xFFE1F6EA),
    tertiary: Color(0xFFFBB5B2),
    onTertiary: Color(0xFF4F2322),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    surface: Color(0xFF121513),
    onSurface: Color(0xFFE4E6E2),
    surfaceContainerLowest: Color(0xFF0C0F0D),
    surfaceContainerLow: Color(0xFF191D1A),
    surfaceContainer: Color(0xFF1F2421),
    surfaceContainerHigh: Color(0xFF292E2B),
    surfaceContainerHighest: Color(0xFF333835),
    onSurfaceVariant: Color(0xFFBFC8C2),
    outline: Color(0xFF8A938D),
    outlineVariant: Color(0xFF3D4640),
  );

  static ThemeData light() => _build(_lightScheme);
  static ThemeData dark() => _build(_darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    final baseText = GoogleFonts.manropeTextTheme(
      ThemeData(brightness: scheme.brightness).textTheme,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: baseText,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: const StadiumBorder(),
          textStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    );
  }
}
```

---

## 3. Маппинг экранов на Flutter-виджеты

1. **Главный (`HomeScreen`)**
   - `Scaffold` с `AppBar(title: Text('Backup Merge'), actions: [ActionChip(label: Text('RU'))])` и `Drawer`.
   - Две крупные `InkWell` / `Card` (`borderRadius: 24`) с иконками `Icons.merge_rounded` и `Icons.note_alt_rounded`.
   - Секция «Последние действия» — `Container` с `surfaceContainerLow` и `ListTile`.
   - Внизу — `Chip` с `Icons.lock_rounded` и подписью `Обработка только на вашем устройстве`.

2. **Боковое меню (`NavigationDrawer`)**
   - Стандартный Material 3 `NavigationDrawer` с `NavigationDrawerDestination` и `Divider`.
   - В шапке — иконка `assets/app_icon.jpg` (`ClipRRect(borderRadius: 16)`), заголовок и `Версия 0.5.0`.

3. **Объединение · шаг 1 «Файлы» (`MergeFilesScreen`)**
   - Верхний степпер `Файлы · Правила · Результат`.
   - Пунктирная зона (`dotted_border` или `CustomPaint`) с кнопкой `FilledButton.tonalIcon` «Выбрать файлы».
   - Список карточек бэкапов с переключателем `Основной` (`Icons.star_rounded`).

4. **Объединение · шаг 2 «Правила» (`MergeRulesScreen`)**
   - Два `SegmentedButton<T>` для выбора правил объединения.
   - Информационная карточка с `secondaryContainer`.
   - Одна главная кнопка `FilledButton` «Объединить».

5. **Объединение · шаг 3 «Результат» (`MergeResultScreen`)**
   - Состояние загрузки: `CircularProgressIndicator` + список этапов (`Чтение`, `Объединение`, `Проверка`, `Упаковка`).
   - Готово: иллюстрация `assets/success_merge.jpg`, сетка `GridView.count(crossAxisCount: 2)` со счётчиками, предупреждение в `AppColors.warningContainer`, кнопки `FilledButton`, `FilledButton.tonal` и `TextButton`.

6. **Экспорт заметок · обзор (`ExportBrowseScreen`)**
   - Карточка источника с кнопкой «Изменить», `SearchBar`, горизонтальный `ListView` с `FilterChip` и карточки заметок.

7. **Экспорт заметок · формат (`ExportFormatScreen`)**
   - Две выбираемые карточки (`Markdown для Obsidian` и `PDF`), два `SwitchListTile`, `SegmentedButton` порядка сортировки и кнопка «Создать».

8. **Страница PDF (`PdfPreviewScreen`)**
   - Белые карточки формата A4 (`Colors.white`) с текстом заметок через `GoogleFonts.playfairDisplay()`.

9. **О приложении (`AboutScreen`)**
   - Иконка, версия, `ListView.separated` со строками информации и дисклеймер внизу.
