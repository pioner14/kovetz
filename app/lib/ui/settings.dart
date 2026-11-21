import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Language and theme chosen by the person, kept in two tiny files so a
/// preference survives restarts. A missing or unreadable file means
/// "follow the system".
class AppSettings extends ChangeNotifier {
  AppSettings({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;
  bool _autoUpdateCheck = false;
  DateTime? _lastUpdateCheck;

  /// null follows the system language.
  Locale? get locale => _locale;
  ThemeMode get themeMode => _themeMode;

  /// Look for a new version once a day when the app starts. Off by default:
  /// the app contacts the internet only when the person asks for it.
  bool get autoUpdateCheck => _autoUpdateCheck;
  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  Future<File> _file(String name) async =>
      File(path.join((await _directory()).path, name));

  Future<void> load() async {
    try {
      final language = (await (await _file('language')).readAsString()).trim();
      if (language == 'ru' || language == 'en') _locale = Locale(language);
    } on Object {
      // No saved language: the system language is used.
    }
    try {
      final theme = (await (await _file('theme')).readAsString()).trim();
      _themeMode = ThemeMode.values.asNameMap()[theme] ?? ThemeMode.system;
    } on Object {
      // No saved theme: the system theme is used.
    }
    try {
      _autoUpdateCheck =
          (await (await _file('update_auto')).readAsString()).trim() == '1';
    } on Object {
      // Not chosen yet: automatic checks stay off.
    }
    try {
      _lastUpdateCheck = DateTime.tryParse(
        (await (await _file('update_last')).readAsString()).trim(),
      );
    } on Object {
      // Never checked.
    }
    notifyListeners();
  }

  Future<void> setAutoUpdateCheck(bool value) async {
    _autoUpdateCheck = value;
    notifyListeners();
    await _save('update_auto', value ? '1' : '0');
  }

  Future<void> markUpdateChecked(DateTime time) async {
    _lastUpdateCheck = time;
    notifyListeners();
    await _save('update_last', time.toUtc().toIso8601String());
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    await _save('language', locale?.languageCode ?? 'system');
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save('theme', mode.name);
  }

  Future<void> _save(String name, String value) async {
    try {
      await (await _file(name)).writeAsString(value);
    } on Object {
      // The choice stays active for this session.
    }
  }
}
