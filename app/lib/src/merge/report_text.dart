// Human-readable TXT report, localized for the person restoring the backup.
part of '../../merge.dart';

extension _ReportText on _RecoveryReport {
  void writeText(File file, Map<String, int> counts, _Merger merger) {
    final sink = file.openSync(mode: FileMode.write);
    final ru = options.languageCode == 'ru';
    void line(String value) => sink.writeStringSync('$value\n');
    String tr(String a, String b) => ru ? a : b;
    final names = {
      'Note': tr('Заметки', 'Notes'),
      'UserMark': tr('Выделения', 'Highlights'),
      'Bookmark': tr('Закладки', 'Bookmarks'),
      'Favorite': tr('Избранное', 'Favorites'),
      'Tag': tr('Теги', 'Tags'),
      'InputField': tr('Ответы в публикациях', 'Publication answers'),
      'Playlist': tr('Плейлисты', 'Playlists'),
      'PlaylistItem': tr('Элементы плейлистов', 'Playlist items'),
      'IndependentMedia': tr('Медиафайлы', 'Media files'),
    };
    try {
      line(tr('ОТЧЁТ ОБ ОБЪЕДИНЕНИИ JW LIBRARY', 'JW LIBRARY MERGE REPORT'));
      line('${tr('Основной бэкап', 'Primary backup')}: $primaryName');
      line(
        '${tr('Версия схемы результата', 'Output schema version')}: $currentSchemaVersion',
      );
      for (final name in sourceNames) {
        line('${tr('Источник', 'Source')}: $name');
      }
      line(tr('Исходные файлы не изменены.', 'Source files were not changed.'));
      line('');
      line(tr('Применённые правила:', 'Applied rules:'));
      line(
        tr(
          'Избранное: все уникальные публикации; сначала порядок основного бэкапа, затем остальные.',
          'Favorites: all unique publications; primary order first, then other entries.',
        ),
      );
      line(
        tr(
          'Закладки: позиции основного бэкапа, затем свободные позиции 0–9 в каждой публикации. Не поместившиеся записи перечислены ниже.',
          'Bookmarks: primary slots, then free slots 0–9 in each publication. Overflow entries are listed below.',
        ),
      );
      line(
        options.notePolicy == NoteConflictPolicy.newest
            ? tr(
                'Заметки: для одинакового GUID выбрана версия с более свежим LastModified.',
                'Notes: for the same GUID, the latest LastModified wins.',
              )
            : tr(
                'Заметки: для одинакового GUID приоритет у основного бэкапа, затем у остальных по дате бэкапа.',
                'Notes: for the same GUID, primary backup wins, then backup date.',
              ),
      );
      line(
        tr(
          'Разные GUID сохранены отдельно, даже у одного стиха. Тексты разных версий не склеиваются.',
          'Different GUIDs are kept separately, even at the same verse. Version texts are not concatenated.',
        ),
      );
      line(
        options.fieldPolicy == FieldConflictPolicy.primary
            ? tr(
                'Ответы: приоритет основного бэкапа.',
                'Answers: primary backup wins.',
              )
            : tr(
                'Ответы: приоритет более свежего бэкапа (дата изменения отдельного ответа отсутствует).',
                'Answers: newest backup wins (individual answer modification time is unavailable).',
              ),
      );
      line('');
      line(
        tr(
          'Выделения: целиком версия с большим Version; при равенстве приоритет у основного бэкапа. Диапазоны разных версий не смешиваются.',
          'Highlights: the complete version with the highest Version wins; ties favor the primary backup. Ranges from differing versions are not mixed.',
        ),
      );
      line(
        tr(
          'Плейлисты: объединение уникальных элементов с сохранением повторов; основной порядок, затем дополнительные элементы. Различающиеся маркеры сохраняются отдельными элементами.',
          'Playlists: union of distinct items, preserving intentional repeats; primary order then additional items. Differing markers are retained as separate items.',
        ),
      );
      line(tr('Сохранено в результате:', 'Saved in the result:'));
      for (final entry in counts.entries) {
        line('${names[entry.key] ?? entry.key}: ${entry.value}');
      }
      line(
        '${tr('Различающиеся версии заметок', 'Conflicting note versions')}: ${merger.noteConflicts}',
      );
      line(
        '${tr('Различающиеся ответы', 'Conflicting answers')}: ${merger.fieldConflicts}',
      );
      line(
        '${tr('Конфликты позиций закладок', 'Bookmark slot conflicts')}: ${merger.bookmarkConflicts}',
      );
      line(
        '${tr('Не поместилось закладок', 'Bookmark overflow')}: ${merger.skippedBookmarks}',
      );
      line('');
      if (warnings.isEmpty) {
        line(
          tr(
            'Невосстановленных записей и отсутствующих медиафайлов не обнаружено.',
            'No unresolved records or missing media files were found.',
          ),
        );
      }
      for (final warning in warnings) {
        line('${warning.fileName ?? ""}: ${warning.code} — ${warning.count}');
      }
      final versions = conflictVersions.iterator;
      if (versions.moveNext()) {
        line('');
        line(
          tr(
            'РАЗЛИЧАЮЩИЕСЯ ВЕРСИИ: данные сохранены ниже',
            'DIFFERING VERSIONS: data retained below',
          ),
        );
        do {
          final version = versions.current;
          line('');
          line('${version['table']} / ${version['fileName']}');
          line('${tr('Дата бэкапа', 'Backup date')}: ${version['backupDate']}');
          line(
            version['table'] == 'Playlist'
                ? (version['selected'] == true
                      ? tr(
                          'Порядок этой версии принят за основу; дополнительные элементы объединены.',
                          'This version supplies the base order; additional items are merged.',
                        )
                      : tr(
                          'Версия сохранена для сравнения; её дополнительные элементы учтены при объединении.',
                          'Version retained for comparison; its additional items contribute to the union.',
                        ))
                : version['selected'] == true
                ? tr(
                    'Выбрана для JW Library по указанному выше правилу.',
                    'Selected for JW Library using the rule stated above.',
                  )
                : tr(
                    'Альтернатива: сохранена в отчёте, не заменяет выбранную версию.',
                    'Alternative: retained in the report; does not replace the selected version.',
                  ),
          );
          final record = version['record'] as Map;
          for (final field in record.entries) {
            line('${field.key}: ${field.value ?? "—"}');
          }
          final context = version['context'];
          if (context is Map && context.isNotEmpty) {
            line(
              '${tr('Публикация/место', 'Publication/location')}: ${jsonEncode(context)}',
            );
          }
        } while (versions.moveNext());
      }
      line('');
      line(tr('Причины и затронутые записи:', 'Reasons and affected records:'));
      var index = 0;
      for (final entry in records) {
        line('');
        line('${++index}. ${entry['fileName']} / ${entry['table']}');
        final reason = entry['reason'];
        line(switch (reason) {
          'bookmarkSlotsFull' => tr(
            'Все 10 позиций закладок в этой публикации заняты. Запись не помещена в базу; её данные приведены ниже.',
            'All 10 bookmark slots in this publication are occupied. The entry is listed below instead of being inserted.',
          ),
          'missingMedia' => tr(
            'Файла с требуемым хешем нет ни в одном выбранном бэкапе. По одному имени/хешу восстановить содержимое файла невозможно.',
            'No selected backup contains a file with the required hash. File contents cannot be reconstructed from its name/hash.',
          ),
          'ambiguousLocation' => tr(
            'Место в публикации похоже сразу на два разных места из других бэкапов. Связанные заметки и выделения привязаны к одному из них; проверьте их в JW Library.',
            'This publication location resembles two different places from other backups. Linked notes and highlights were attached to one of them; check them in JW Library.',
          ),
          'missingReference' => tr(
            'Запись ссылается на отсутствующую запись в своём исходном бэкапе. Числовые ID других устройств не позволяют достоверно установить связь. Для заметки сохранён текст без отсутствующей связи; зависимая запись сохранена в отчёте.',
            'A referenced record is absent from this source backup. Numeric IDs on other devices cannot reliably identify it. Note text is retained without the missing link; dependent records are retained in this report.',
          ),
          _ => tr(
            'Структура записи не позволяет достоверно перенести её в текущую схему: $reason.',
            'The record cannot be mapped reliably to the current schema: $reason.',
          ),
        });
        if (entry['missingReferences'] is List) {
          line(
            '${tr('Отсутствующие связи', 'Missing references')}: ${(entry['missingReferences'] as List).join(', ')}',
          );
        }
        final context = entry['context'];
        if (context is Map && context.isNotEmpty) {
          for (final location in context.entries) {
            line(
              '${tr('Публикация/место', 'Publication/location')} (${location.key}): ${jsonEncode(location.value)}',
            );
          }
        }
        final record = entry['record'];
        if (record is Map) {
          for (final field in record.entries) {
            line('${field.key}: ${field.value ?? "—"}');
          }
        }
      }
      line('');
      if (hasDetails) {
        line(
          tr(
            'Исходные бэкапы не изменены — сохраните их. Записи, которые не удалось перенести, и альтернативные версии перечислены в этом отчёте; в архив для JW Library они не вкладываются.',
            'Source backups were not changed; keep them. Records that could not be transferred and alternative versions are listed in this report; they are not embedded in the JW Library archive.',
          ),
        );
      }
      if (warnings.any(
        (w) => w.code == 'missingMedia' || w.code == 'unresolvedLinks',
      )) {
        line(
          tr(
            'Если данных нет в выбранных бэкапах, нужен другой исходный бэкап, содержащий их.',
            'If the selected backups lack the data, another source backup containing it is needed.',
          ),
        );
      }
      line(
        tr(
          'Перед восстановлением сохраните отдельный бэкап из JW Library. Совместимость структуры проверена программой; фактическое восстановление проверьте в JW Library.',
          'Save a separate JW Library backup before restoring. The app validates database structure; verify actual restoration in JW Library.',
        ),
      );
    } finally {
      sink.closeSync();
    }
  }
}
