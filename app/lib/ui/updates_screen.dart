import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../updates.dart';
import 'info_screens.dart';
import 'l10n.dart';
import 'settings.dart';
import 'theme.dart';
import 'update_controller.dart';

String _platform() => Platform.isAndroid
    ? 'android'
    : Platform.isWindows
    ? 'windows'
    : 'linux';

/// Manual check, the automatic-check switch and the result.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({
    super.key,
    required this.settings,
    required this.updates,
  });

  final AppSettings settings;
  final UpdateController updates;

  String _date(BuildContext context, DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _download(BuildContext context, ReleaseInfo release) async {
    final target = release.assetFor(_platform()) ?? release.page;
    final messenger = ScaffoldMessenger.of(context);
    final text = context.tr(
      'Не удалось открыть браузер. Ссылка скопирована: $target',
      'Could not open the browser. Link copied: $target',
    );
    if (!await updates.open(target)) {
      await Clipboard.setData(ClipboardData(text: target.toString()));
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = theme.extension<StatusColors>()!;
    return InfoPage(
      title: context.tr('Обновления', 'Updates'),
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([updates, settings]),
          builder: (context, _) {
            final release = updates.release;
            final checking = updates.status == UpdateStatus.checking;
            final last = settings.lastUpdateCheck;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.system_update_alt_rounded,
                      color: colors.primary,
                    ),
                    title: Text(
                      context.tr(
                        'Установлена версия $appVersion ($appBuild)',
                        'Installed version $appVersion ($appBuild)',
                      ),
                    ),
                    subtitle: last == null
                        ? null
                        : Text(
                            context.tr(
                              'Проверено: ${_date(context, last)}',
                              'Checked: ${_date(context, last)}',
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                switch (updates.status) {
                  UpdateStatus.upToDate => _Notice(
                    icon: Icons.check_circle_outline_rounded,
                    background: status.successContainer,
                    foreground: status.onSuccessContainer,
                    text: release == null
                        ? context.tr(
                            'Опубликованных версий пока нет.',
                            'No versions have been published yet.',
                          )
                        : context.tr(
                            'У вас последняя версия.',
                            'You have the latest version.',
                          ),
                  ),
                  UpdateStatus.failed => _Notice(
                    icon: Icons.cloud_off_rounded,
                    background: colors.errorContainer,
                    foreground: colors.onErrorContainer,
                    text: switch (updates.failure?.kind) {
                      UpdateErrorKind.server => context.tr(
                        'GitHub не ответил как ожидалось (${updates.failure?.detail ?? ''}). Попробуйте позже.',
                        'GitHub did not answer as expected (${updates.failure?.detail ?? ''}). Try again later.',
                      ),
                      UpdateErrorKind.format => context.tr(
                        'Не удалось разобрать ответ GitHub.',
                        'Could not read the GitHub answer.',
                      ),
                      _ => context.tr(
                        'Нет связи с GitHub. Проверьте интернет и повторите.',
                        'Cannot reach GitHub. Check the internet and try again.',
                      ),
                    },
                  ),
                  UpdateStatus.available when release != null => _Available(
                    release: release,
                    onDownload: () => _download(context, release),
                    onPage: () async {
                      if (!await updates.open(release.page) &&
                          context.mounted) {
                        await Clipboard.setData(
                          ClipboardData(text: release.page.toString()),
                        );
                      }
                    },
                  ),
                  _ => const SizedBox.shrink(),
                },
                const SizedBox(height: Gap.lg),
                FilledButton.icon(
                  onPressed: checking ? null : updates.check,
                  icon: checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    checking
                        ? context.tr('Проверяем…', 'Checking…')
                        : context.tr(
                            'Проверить обновления',
                            'Check for updates',
                          ),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                Card(
                  child: SwitchListTile(
                    title: Text(
                      context.tr(
                        'Проверять автоматически',
                        'Check automatically',
                      ),
                    ),
                    subtitle: Text(
                      context.tr(
                        'Раз в сутки при запуске. Если выключено, приложение выходит в интернет только по вашей кнопке.',
                        'Once a day at start-up. When off, the app uses the internet only when you press the button.',
                      ),
                    ),
                    value: settings.autoUpdateCheck,
                    onChanged: settings.setAutoUpdateCheck,
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  context.tr(
                    'Проверка запрашивает у GitHub только список опубликованных версий. Ваши файлы, заметки и сведения об устройстве не отправляются. Установка обновления выполняется вами: файл скачивается из браузера.',
                    'The check asks GitHub only for the list of published versions. Your files, notes and device details are not sent. You install the update yourself: the file is downloaded in the browser.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.text,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Available extends StatelessWidget {
  const _Available({
    required this.release,
    required this.onDownload,
    required this.onPage,
  });

  final ReleaseInfo release;
  final VoidCallback onDownload;
  final VoidCallback onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final notes = release.notes.length > 700
        ? '${release.notes.substring(0, 700)}…'
        : release.notes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.new_releases_outlined, color: colors.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(
                        'Доступна версия ${release.version}',
                        'Version ${release.version} is available',
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            if (release.prerelease) ...[
              const SizedBox(height: Gap.xs),
              Text(
                context.tr('Бета-версия', 'Beta version'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              Text(notes, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton(
              onPressed: onDownload,
              child: Text(context.tr('Скачать', 'Download')),
            ),
            TextButton(
              onPressed: onPage,
              child: Text(context.tr('Страница релиза', 'Release page')),
            ),
          ],
        ),
      ),
    );
  }
}
