import 'package:material_ui/material_ui.dart';

import 'app_drawer.dart';
import 'export_notes_screen.dart';
import 'info_screens.dart';
import 'l10n.dart';
import 'merge_screen.dart';
import 'settings.dart';
import 'theme.dart';
import 'update_controller.dart';
import 'updates_screen.dart';
import 'widgets.dart';

/// Start page: the two things the app does.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.settings, required this.updates});

  final AppSettings settings;
  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: AppDrawer(settings: settings, updates: updates),
      appBar: AppBar(
        title: const Text('Kovetz'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: context.tr('Как пользоваться', 'How to use'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HowToScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: Gap.md),
            child: LanguageChip(settings: settings),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final merge = _FeatureCard(
              icon: Icons.merge_rounded,
              title: context.tr('Объединить бэкапы', 'Merge backups'),
              text: context.tr(
                'Соберите заметки, выделения и закладки с разных устройств в один бэкап',
                'Bring notes, highlights and bookmarks from different devices into one backup',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MergeScreen()),
              ),
            );
            final export = _FeatureCard(
              icon: Icons.note_alt_outlined,
              title: context.tr('Экспорт заметок', 'Export notes'),
              text: context.tr(
                'Сохраните заметки с тегами в Markdown для Obsidian или в красивый PDF',
                'Save notes with tags as Markdown for Obsidian or as a typeset PDF',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ExportNotesScreen(),
                ),
              ),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Gap.pageMargin,
                Gap.sm,
                Gap.pageMargin,
                Gap.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListenableBuilder(
                        listenable: updates,
                        builder: (context, _) => updates.showBanner
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: Gap.lg),
                                child: _UpdateBanner(
                                  version: updates.release!.version,
                                  onOpen: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => UpdatesScreen(
                                        settings: settings,
                                        updates: updates,
                                      ),
                                    ),
                                  ),
                                  onDismiss: updates.dismissBanner,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Text(
                        context.tr(
                          'Что сделаем сегодня?',
                          'What shall we do today?',
                        ),
                        style: wide
                            ? theme.textTheme.displayLarge
                            : theme.textTheme.displayMedium,
                      ),
                      const SizedBox(height: Gap.xl),
                      if (wide)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: merge),
                              const SizedBox(width: Gap.lg),
                              Expanded(child: export),
                            ],
                          ),
                        )
                      else ...[
                        merge,
                        const SizedBox(height: Gap.lg),
                        export,
                      ],
                      const SizedBox(height: Gap.section),
                      const Center(child: PrivacyBadge()),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      enabled: enabled,
      child: Material(
        color: colors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: enabled
                            ? colors.primaryContainer
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      child: Icon(
                        icon,
                        size: 30,
                        color: enabled
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 22,
                      color: colors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "RU" / "EN" chip that opens the language choice.
class LanguageChip extends StatelessWidget {
  const LanguageChip({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(Localizations.localeOf(context).languageCode.toUpperCase()),
    tooltip: context.tr('Сменить язык', 'Change language'),
    onPressed: () => showLanguageDialog(context, settings),
  );
}

Future<void> showLanguageDialog(BuildContext context, AppSettings settings) =>
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('Язык интерфейса', 'App language')),
        children: [
          for (final (code, label) in [
            (null, context.tr('Как в системе', 'System default')),
            ('ru', 'Русский'),
            ('en', 'English'),
          ])
            ListTile(
              title: Text(label),
              trailing: (settings.locale?.languageCode == code)
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                settings.setLocale(code == null ? null : Locale(code));
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );

Future<void> showThemeDialog(BuildContext context, AppSettings settings) =>
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('Тема', 'Theme')),
        children: [
          for (final (mode, label) in [
            (ThemeMode.system, context.tr('Системная', 'System')),
            (ThemeMode.light, context.tr('Светлая', 'Light')),
            (ThemeMode.dark, context.tr('Тёмная', 'Dark')),
          ])
            ListTile(
              title: Text(label),
              trailing: settings.themeMode == mode
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                settings.setThemeMode(mode);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.version,
    required this.onOpen,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
          child: Row(
            children: [
              Icon(
                Icons.new_releases_outlined,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  context.tr(
                    'Доступна версия $version',
                    'Version $version is available',
                  ),
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
              ),
              IconButton(
                tooltip: context.tr('Скрыть', 'Dismiss'),
                icon: const Icon(Icons.close_rounded),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
