import 'package:material_ui/material_ui.dart';

import 'l10n.dart';
import 'open_link.dart';
import 'theme.dart';

/// Scrollable page with a back arrow, used by the information screens.
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Gap.pageMargin,
              Gap.sm,
              Gap.pageMargin,
              Gap.xl,
            ),
            children: children,
          ),
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.text);

  final int number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.primaryContainer,
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) => InfoPage(
    title: context.tr('Как пользоваться', 'How to use'),
    children: [
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minTileHeight: 56,
          title: Text(
            context.tr('Открыть полное руководство', 'Open the full guide'),
          ),
          subtitle: Text(
            context.tr(
              'С картинками и стрелками, для любого возраста. Нужен интернет.',
              'With pictures and arrows, for any age. Needs the internet.',
            ),
          ),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => openGuide(context),
        ),
      ),
      const SizedBox(height: Gap.lg),
      _Step(
        1,
        context.tr('Сохраните бэкап телефона', 'Back up your phone first'),
        context.tr(
          'В JW Library: «Мои заметки» → значок облака со стрелкой. Не забудьте: восстановление заменяет все данные на устройстве.',
          'In JW Library: My Notes → the cloud icon with an arrow. Restoring replaces all data on the device.',
        ),
      ),
      _Step(
        2,
        context.tr('Добавьте бэкапы', 'Add backups'),
        context.tr(
          'Выберите файлы .jwlibrary с разных устройств. Основной бэкап задаёт порядок закладок и избранного.',
          'Choose .jwlibrary files from different devices. The primary backup sets the order of bookmarks and favourites.',
        ),
      ),
      _Step(
        3,
        context.tr('Объедините и сохраните', 'Merge and save'),
        context.tr(
          'Приложение сохранит бэкап и рядом TXT-отчёт: в нём правила, итоги и всё, что не удалось перенести.',
          'The app saves the backup and a TXT report beside it: the rules, totals and anything that could not be transferred.',
        ),
      ),
      _Step(
        4,
        context.tr('Восстановите в JW Library', 'Restore in JW Library'),
        context.tr(
          'Откройте сохранённый файл в JW Library и выберите «Восстановить». Исходные бэкапы приложение не меняет.',
          'Open the saved file in JW Library and choose Restore. The app never changes the source backups.',
        ),
      ),
    ],
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget paragraph(String ru, String en) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Text(context.tr(ru, en), style: theme.textTheme.bodyLarge),
    );
    return InfoPage(
      title: context.tr('Конфиденциальность', 'Privacy'),
      children: [
        paragraph(
          'Все файлы обрабатываются только на вашем устройстве. Ваши бэкапы, заметки и сведения об устройстве никуда не отправляются.',
          'All files are processed only on your device. Your backups, notes and device details are never sent anywhere.',
        ),
        paragraph(
          'Для проверки обновлений приложение запрашивает на GitHub список опубликованных версий. Проверка выполняется по кнопке «Проверить обновления» или раз в сутки, если вы включили автоматическую проверку (по умолчанию выключена). Полное руководство открывается в браузере.',
          'To check for updates, the app asks GitHub for the list of published versions. It runs when you press “Check for updates”, or once a day if you turned on the automatic check (off by default). The full guide opens in your browser.',
        ),
        paragraph(
          'Временные копии бэкапов хранятся во внутренней папке приложения и удаляются после работы; брошенные копии удаляются при следующем запуске.',
          'Temporary copies of backups live in the app’s private folder and are removed after use; leftovers are removed at the next start.',
        ),
        paragraph(
          'Ваши бэкапы содержат личные заметки. Результат и TXT-отчёт сохраняются только в ту папку, которую вы выберете.',
          'Your backups contain personal notes. The result and TXT report are saved only to the folder you choose.',
        ),
      ],
    );
  }
}
