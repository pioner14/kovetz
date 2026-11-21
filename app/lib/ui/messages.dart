import 'package:path/path.dart' as path;

import '../merge.dart';

/// Picks the Russian or English text for the current locale.
typedef Translate = String Function(String ru, String en);

/// User-facing explanation of why a merge stopped.
String mergeErrorMessage(MergeFailure error, Translate t) {
  final message = switch (error.kind) {
    MergeErrorCode.invalidArchive => t(
      'Файл не удалось прочитать как бэкап JW Library.',
      'Could not read the file as a JW Library backup.',
    ),
    MergeErrorCode.unsupportedSchema =>
      error.schemaTable == 'user_version'
          ? t(
              'Версия базы данных не совпадает с версией в описании бэкапа.',
              'The database version disagrees with the backup manifest.',
            )
          : error.schemaTable != null
          ? t(
              'Неизвестная структура таблицы «${error.schemaTable}» в схеме ${error.schemaVersion}. Нужна поддержка этого варианта формата.',
              'Unrecognized structure of table “${error.schemaTable}” in schema ${error.schemaVersion}. This format variant needs support.',
            )
          : t(
              'Версия схемы бэкапа ${error.schemaVersion ?? "неизвестна"} пока не поддерживается.',
              'Backup schema version ${error.schemaVersion ?? "unknown"} is currently unsupported.',
            ),
    MergeErrorCode.brokenReferences => t(
      'В базе бэкапа есть ссылки на отсутствующие записи (${error.brokenReferences}). Объединение остановлено. Для восстановления связей нужен исправный исходный бэкап.',
      'The backup database references missing records (${error.brokenReferences}). Merge stopped. A healthy source backup is needed to restore the links.',
    ),
    MergeErrorCode.invalidDatabase => t(
      'Не удалось проверить целостность базы данных.',
      'The database failed its integrity check.',
    ),
    MergeErrorCode.badHash => t(
      'Содержимое бэкапа не совпадает с его контрольной суммой.',
      'The backup contents do not match its checksum.',
    ),
    MergeErrorCode.tooLarge => t(
      'Бэкап слишком большой или содержит слишком много файлов для безопасной обработки.',
      'The backup is too large or contains too many files to process safely.',
    ),
    MergeErrorCode.invalidReport => t(
      'Отчёт о восстановлении внутри этого результата прошлого объединения повреждён. Выберите исходные бэкапы вместо него.',
      'The recovery report inside this earlier merge result is damaged. Choose the original backups instead.',
    ),
    MergeErrorCode.missingMedia => t(
      'В бэкапе отсутствует медиафайл, на который ссылается плейлист.',
      'A media file referenced by a playlist is missing.',
    ),
    MergeErrorCode.io => t(
      'Не удалось прочитать или записать файл. Проверьте доступ и свободное место.',
      'Could not read or write a file. Check permissions and available storage.',
    ),
    MergeErrorCode.cancelled => t(
      'Объединение отменено. Исходные файлы не изменены.',
      'Merge cancelled. Source files were not changed.',
    ),
    MergeErrorCode.internal => t(
      'Внутренняя ошибка программы: ${error.detail}. Исходные файлы не изменены. Сообщите этот текст разработчику.',
      'Internal error: ${error.detail}. Source files were not changed. Please report this text to the developer.',
    ),
    MergeErrorCode.tooFew => t(
      'Добавьте как минимум два разных бэкапа.',
      'Add at least two different backups.',
    ),
    MergeErrorCode.invalidPrimary => t(
      'Не удалось объединить бэкапы.',
      'Could not merge the backups.',
    ),
  };
  final fileName = error.fileName;
  return fileName == null ? message : '${path.basename(fileName)}\n$message';
}

/// Progress text for a merge stage reported by the worker isolate.
String stageLabel(String stage, Translate t) => switch (stage) {
  'reading' => t('Читаем бэкапы…', 'Reading backups…'),
  'merging' => t('Объединяем данные…', 'Merging data…'),
  'checking' => t('Проверяем целостность…', 'Checking data integrity…'),
  'packing' => t('Создаём архив…', 'Creating the archive…'),
  _ => t('Обрабатываем бэкапы…', 'Processing backups…'),
};
