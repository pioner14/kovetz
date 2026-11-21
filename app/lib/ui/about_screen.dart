import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import 'info_screens.dart';
import 'l10n.dart';
import 'open_link.dart';
import 'theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget row(
      IconData icon,
      String text, {
      String? trailing,
      IconData? action,
      VoidCallback? onTap,
    }) => ListTile(
      leading: Icon(icon, color: colors.onSurfaceVariant),
      title: Text(text),
      trailing: trailing != null
          ? Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : action == null
          ? null
          : Icon(action, color: colors.outline),
      onTap: onTap,
    );
    return InfoPage(
      title: context.tr('О приложении', 'About'),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: 96,
              height: 96,
              semanticLabel: appName,
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          appName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Версия $appVersion ($appBuild)',
            'Version $appVersion ($appBuild)',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          context.tr(
            'Офлайн-помощник для объединения бэкапов и экспорта заметок из JW Library',
            'An offline helper for merging backups and exporting notes from JW Library',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.xl),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              row(
                Icons.person_outline_rounded,
                context.tr('Разработчик', 'Developer'),
                trailing: appDeveloper,
              ),
              const Divider(),
              row(
                Icons.code_rounded,
                context.tr('Исходный код — GitHub', 'Source code — GitHub'),
                action: Icons.copy_rounded,
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: appRepository),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.tr(
                          'Ссылка скопирована: $appRepository',
                          'Link copied: $appRepository',
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              row(
                Icons.help_outline_rounded,
                context.tr('Руководство пользователя', 'User guide'),
                action: Icons.open_in_new_rounded,
                onTap: () => openGuide(context),
              ),
              const Divider(),
              row(
                Icons.coffee_rounded,
                context.tr('☕ Угостить кофе', '☕ Buy me a coffee'),
                action: Icons.open_in_new_rounded,
                onTap: () => openLink(context, Uri.parse(appDonateUrl)),
              ),
              const Divider(),
              row(
                Icons.balance_rounded,
                context.tr('Лицензия — $appLicense', 'License — $appLicense'),
              ),
              const Divider(),
              row(
                Icons.lock_outline_rounded,
                context.tr(
                  'Конфиденциальность: файлы обрабатываются только на устройстве',
                  'Privacy: files are processed only on the device',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        Text(
          context.tr(
            'Kovetz не связан с JW Library и её разработчиками',
            'Kovetz is not affiliated with JW Library or its developers',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
