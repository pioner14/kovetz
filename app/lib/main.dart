import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'cleanup.dart';
import 'ui/home_screen.dart';
import 'ui/l10n.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';
import 'ui/update_controller.dart';

export 'ui/home_screen.dart' show HomeScreen;
export 'ui/merge_screen.dart' show MergeScreen;
export 'ui/settings.dart' show AppSettings;
export 'ui/update_controller.dart' show UpdateController;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_removeLeftovers());
  runApp(const BackupMergeApp());
}

/// Clears copies of backups left by an interrupted run or the Android picker.
Future<void> _removeLeftovers() async {
  try {
    await removeStaleTemporaryFiles(
      temporary: Directory.systemTemp,
      pickerCache: Platform.isAndroid ? await getTemporaryDirectory() : null,
    );
  } on Object {
    // Clean-up is best effort; the app works without it.
  }
}

class BackupMergeApp extends StatefulWidget {
  const BackupMergeApp({super.key, this.settings, this.updates});

  /// Injected by tests; the app creates its own otherwise.
  final AppSettings? settings;
  final UpdateController? updates;

  @override
  State<BackupMergeApp> createState() => _BackupMergeAppState();
}

class _BackupMergeAppState extends State<BackupMergeApp> {
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final UpdateController _updates =
      widget.updates ?? UpdateController(_settings);

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load().then((_) => _updates.checkAutomatically()));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.tr('Kovetz', 'Kovetz'),
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _settings.themeMode,
      locale: _settings.locale,
      supportedLocales: const [Locale('en'), Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: HomeScreen(settings: _settings, updates: _updates),
    ),
  );
}
