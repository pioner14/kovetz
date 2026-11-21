import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import 'about_screen.dart';
import 'export_notes_screen.dart';
import 'home_screen.dart';
import 'info_screens.dart';
import 'l10n.dart';
import 'merge_screen.dart';
import 'settings.dart';
import 'update_controller.dart';
import 'updates_screen.dart';
import 'theme.dart';

/// Side menu: sections, language, theme and information pages.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.settings, required this.updates});

  final AppSettings settings;
  final UpdateController updates;

  void _open(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final language = switch (settings.locale?.languageCode) {
      'ru' => 'Русский',
      'en' => 'English',
      _ => context.tr('Как в системе', 'System default'),
    };
    final themeName = switch (settings.themeMode) {
      ThemeMode.light => context.tr('Светлая', 'Light'),
      ThemeMode.dark => context.tr('Тёмная', 'Dark'),
      ThemeMode.system => context.tr('Системная', 'System'),
    };
    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool selected = false,
      String? detail,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: colors.primaryContainer,
        selectedColor: colors.onPrimaryContainer,
        shape: const StadiumBorder(),
        leading: Icon(icon),
        title: Text(label),
        subtitle: detail == null ? null : Text(detail),
        onTap: onTap,
      ),
    );
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(Radii.xl)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.pageMargin),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 48,
                    height: 48,
                    semanticLabel: appName,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appName, style: theme.textTheme.titleMedium),
                      Text(
                        context.tr('Версия $appVersion', 'Version $appVersion'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: Gap.xl * 2),
            item(
              Icons.home_outlined,
              context.tr('Главная', 'Home'),
              () => Navigator.pop(context),
              selected: true,
            ),
            item(
              Icons.merge_rounded,
              context.tr('Объединить бэкапы', 'Merge backups'),
              () => _open(context, const MergeScreen()),
            ),
            item(
              Icons.note_alt_outlined,
              context.tr('Экспорт заметок', 'Export notes'),
              () => _open(context, const ExportNotesScreen()),
            ),
            const Divider(height: Gap.xl * 2),
            item(
              Icons.translate_rounded,
              context.tr('Язык', 'Language'),
              () => showLanguageDialog(context, settings),
              detail: language,
            ),
            item(
              Icons.contrast_rounded,
              context.tr('Тема', 'Theme'),
              () => showThemeDialog(context, settings),
              detail: themeName,
            ),
            const Divider(height: Gap.xl * 2),
            item(
              Icons.system_update_alt_rounded,
              context.tr('Обновления', 'Updates'),
              () => _open(
                context,
                UpdatesScreen(settings: settings, updates: updates),
              ),
              detail: updates.showBanner
                  ? context.tr(
                      'Доступна версия ${updates.release!.version}',
                      'Version ${updates.release!.version} is available',
                    )
                  : null,
            ),
            item(
              Icons.help_outline_rounded,
              context.tr('Как пользоваться', 'How to use'),
              () => _open(context, const HowToScreen()),
            ),
            item(
              Icons.info_outline_rounded,
              context.tr('О приложении', 'About'),
              () => _open(context, const AboutScreen()),
            ),
            item(
              Icons.shield_outlined,
              context.tr('Конфиденциальность', 'Privacy'),
              () => _open(context, const PrivacyScreen()),
            ),
            const SizedBox(height: Gap.xl),
            Text(
              context.tr(
                'Не является официальным приложением JW Library',
                'Not an official JW Library app',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
