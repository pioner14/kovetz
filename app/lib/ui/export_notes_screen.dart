import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

import '../export_save.dart';
import '../notes_export.dart';
import 'l10n.dart';
import 'messages.dart';
import 'theme.dart';
import 'widgets.dart';

/// Overview of the tagged notes of one backup, with search and tag filter.
class ExportNotesScreen extends StatefulWidget {
  const ExportNotesScreen({super.key, this.initialBackup});

  /// A backup to open at once, for example the result of a merge.
  final String? initialBackup;

  @override
  State<ExportNotesScreen> createState() => _ExportNotesScreenState();
}

class _ExportNotesScreenState extends State<ExportNotesScreen> {
  final _search = TextEditingController();
  String? _path;
  NotesCollection? _notes;
  bool _loading = false;
  MergeFailure? _failure;
  String? _tag;
  String? _languageLoaded;

  String _t(String ru, String en) => localText(context, ru, en);

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (_path == null && widget.initialBackup != null && !_loading) {
      _path = widget.initialBackup;
      unawaited(_load(_path!, language));
    } else if (_languageLoaded != null &&
        _languageLoaded != language &&
        _path != null &&
        !_loading) {
      // Source labels ("Римлянам 15:13" / "Romans 15:13") follow the language.
      unawaited(_load(_path!, language));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: Platform.isAndroid
            ? []
            : const [
                XTypeGroup(label: 'JW Library', extensions: ['jwlibrary']),
              ],
      );
      if (file == null || !mounted) return;
      _path = file.path;
      await _load(file.path, Localizations.localeOf(context).languageCode);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Не удалось открыть файл.', 'Could not open the file.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _load(String file, String language) async {
    setState(() {
      _loading = true;
      _failure = null;
      _tag = null;
    });
    try {
      final notes = await readBackupNotes(file, languageCode: language);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _languageLoaded = language;
      });
    } on MergeFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } on Object {
      if (mounted) {
        setState(() => _failure = const MergeFailure.internal('notes'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<BackupNote> _visible(NotesCollection notes) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final note in notes.notes)
        if (note.tags.isNotEmpty &&
            (_tag == null || note.tags.contains(_tag)) &&
            (query.isEmpty ||
                note.title.toLowerCase().contains(query) ||
                note.content.toLowerCase().contains(query) ||
                note.source.label.toLowerCase().contains(query) ||
                note.tags.any((t) => t.toLowerCase().contains(query))))
          note,
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('Экспорт заметок', 'Export notes'))),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _body(Theme.of(context)),
        ),
      ),
    ),
  );

  Widget _body(ThemeData theme) {
    final colors = theme.colorScheme;
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Gap.lg),
            Text(_t('Читаем заметки…', 'Reading notes…')),
          ],
        ),
      );
    }
    final notes = _notes;
    if (_failure != null || notes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.pageMargin),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.note_alt_outlined, size: 56, color: colors.primary),
              const SizedBox(height: Gap.lg),
              Text(
                _failure == null
                    ? _t(
                        'Выберите бэкап, из которого нужно извлечь заметки.',
                        'Choose the backup to take the notes from.',
                      )
                    : mergeErrorMessage(_failure!, _t),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: Gap.xl),
              FilledButton.icon(
                onPressed: _choose,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(_t('Выбрать бэкап', 'Choose a backup')),
              ),
              const SizedBox(height: Gap.xl),
              const PrivacyBadge(),
            ],
          ),
        ),
      );
    }
    final visible = _visible(notes);
    final tagged = notes.notes.where((n) => n.tags.isNotEmpty).length;
    final counts = notes.tagCounts;
    final format = MaterialLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.pageMargin,
            0,
            Gap.pageMargin,
            Gap.sm,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: colors.primary),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          notes.backupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (widget.initialBackup == null)
                        TextButton(
                          onPressed: _choose,
                          child: Text(_t('Изменить', 'Change')),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    _t(
                      '${format.formatDecimal(tagged)} заметок с тегами · ${format.formatDecimal(counts.length)} тегов',
                      '${format.formatDecimal(tagged)} tagged notes · ${format.formatDecimal(counts.length)} tags',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.pageMargin),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: _t('Поиск по заметкам', 'Search notes'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _t('Очистить', 'Clear'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _search.clear,
                    ),
              filled: true,
              fillColor: colors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.full),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.full),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.pageMargin,
              vertical: Gap.sm,
            ),
            children: [
              for (final entry in counts.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Gap.sm),
                  child: FilterChip(
                    label: Text('${entry.key} ${entry.value}'),
                    selected: _tag == entry.key,
                    showCheckmark: false,
                    onSelected: (selected) =>
                        setState(() => _tag = selected ? entry.key : null),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    _t('Ничего не найдено', 'Nothing found'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.pageMargin,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
                  itemBuilder: (context, index) => _NoteCard(visible[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.pageMargin,
            Gap.md,
            Gap.pageMargin,
            Gap.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: tagged == 0
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExportFormatScreen(notes: notes),
                      ),
                    ),
              child: Text(_t('Экспортировать', 'Export')),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard(this.note);

  final BackupNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = note.title.isNotEmpty
        ? note.title
        : note.content.split('\n').first;
    final preview = note.title.isEmpty ? '' : note.content;
    final date = note.modified ?? note.created;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.source.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in note.tags.take(3))
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(Radii.full),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            child: Text(
                              tag,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      if (note.tags.length > 3)
                        Text(
                          '+${note.tags.length - 3}',
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
                if (date != null && date.length >= 10)
                  Text(
                    '${date.substring(8, 10)}.${date.substring(5, 7)}.${date.substring(0, 4)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Format { markdown, pdf }

/// Format, options and the actual export.
class ExportFormatScreen extends StatefulWidget {
  const ExportFormatScreen({super.key, required this.notes});

  final NotesCollection notes;

  @override
  State<ExportFormatScreen> createState() => _ExportFormatScreenState();
}

class _ExportFormatScreenState extends State<ExportFormatScreen> {
  _Format _format = _Format.markdown;
  bool _includeUntagged = false;
  NoteOrder _order = NoteOrder.source;
  bool _working = false;
  String? _error;

  String _t(String ru, String en) => localText(context, ru, en);

  Future<PdfFonts> _fonts() async {
    Future<Uint8List> load(String name) async =>
        (await rootBundle.load('assets/fonts/$name')).buffer.asUint8List();
    return PdfFonts(
      serif: await load('NotoSerif-Regular.ttf'),
      serifBold: await load('NotoSerif-Bold.ttf'),
      serifItalic: await load('NotoSerif-Italic.ttf'),
      sans: await load('NotoSans-Regular.ttf'),
      sansBold: await load('NotoSans-Bold.ttf'),
      fallbacks: [
        await load('NotoSansArmenian-Regular.ttf'),
        await load('NotoSansHebrew-Regular.ttf'),
      ],
    );
  }

  Future<void> _create() async {
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    setState(() {
      _working = true;
      _error = null;
    });
    String? saved;
    try {
      if (_format == _Format.pdf) {
        final bytes = await buildNotesPdfInBackground(
          widget.notes,
          await _fonts(),
          PdfOptions(
            includeUntagged: _includeUntagged,
            order: _order,
            russian: russian,
          ),
        );
        saved = await saveBytesWithDialog(
          bytes: bytes,
          fileName: russian ? 'Заметки JW Library.pdf' : 'JW Library notes.pdf',
          label: 'PDF',
          extension: 'pdf',
        );
      } else {
        final files = buildMarkdownExport(
          widget.notes,
          MarkdownOptions(includeUntagged: _includeUntagged, russian: russian),
        );
        final folder = russian ? 'JW Library — заметки' : 'JW Library notes';
        saved = Platform.isAndroid
            ? await saveBytesWithDialog(
                bytes: Uint8List.fromList(markdownExportZip(files)),
                fileName: '$folder.zip',
                label: 'ZIP',
                extension: 'zip',
              )
            : await saveMarkdownFolder(files, folder);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = _t(
            'Не удалось создать или сохранить файл. Проверьте доступ и свободное место.',
            'Could not create or save the file. Check permissions and free space.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.isEmpty
                ? _t('Заметки сохранены.', 'Notes saved.')
                : _t(
                    'Заметки сохранены: ${path.basename(saved)}',
                    'Notes saved: ${path.basename(saved)}',
                  ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = widget.notes.notes
        .where((n) => _includeUntagged || n.tags.isNotEmpty)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Экспорт заметок', 'Export notes'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.pageMargin,
                    ),
                    children: [
                      ChoiceTile(
                        icon: Icons.tag_rounded,
                        title: _t(
                          'Markdown для Obsidian',
                          'Markdown for Obsidian',
                        ),
                        subtitle: Platform.isAndroid
                            ? _t(
                                'ZIP: файл на каждую заметку и оглавление по тегам',
                                'ZIP: a file per note and an index per tag',
                              )
                            : _t(
                                'Папка: файл на каждую заметку и оглавление по тегам',
                                'Folder: a file per note and an index per tag',
                              ),
                        selected: _format == _Format.markdown,
                        onTap: _working
                            ? null
                            : () => setState(() => _format = _Format.markdown),
                      ),
                      const SizedBox(height: Gap.md),
                      ChoiceTile(
                        icon: Icons.menu_book_rounded,
                        title: 'PDF',
                        subtitle: _t(
                          'Книга по тегам с оглавлением',
                          'A book by tag with a table of contents',
                        ),
                        selected: _format == _Format.pdf,
                        onTap: _working
                            ? null
                            : () => setState(() => _format = _Format.pdf),
                      ),
                      const SizedBox(height: Gap.xl),
                      Card(
                        child: SwitchListTile(
                          title: Text(
                            _t(
                              'Добавить заметки без тегов',
                              'Include notes without tags',
                            ),
                          ),
                          subtitle: Text(
                            _t(
                              'Они будут в разделе «Без тега»',
                              'They go into a “No tag” section',
                            ),
                          ),
                          value: _includeUntagged,
                          onChanged: _working
                              ? null
                              : (value) =>
                                    setState(() => _includeUntagged = value),
                        ),
                      ),
                      if (_format == _Format.pdf) ...[
                        const SizedBox(height: Gap.xl),
                        Text(
                          _t('Порядок внутри тега', 'Order inside a tag'),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: Gap.sm),
                        ChoiceTile(
                          title: _t(
                            'По Библии и публикациям',
                            'By Bible and publication',
                          ),
                          selected: _order == NoteOrder.source,
                          onTap: _working
                              ? null
                              : () => setState(() => _order = NoteOrder.source),
                        ),
                        const SizedBox(height: Gap.sm),
                        ChoiceTile(
                          title: _t('По дате', 'By date'),
                          selected: _order == NoteOrder.date,
                          onTap: _working
                              ? null
                              : () => setState(() => _order = NoteOrder.date),
                        ),
                      ],
                      const SizedBox(height: Gap.lg),
                      Text(
                        _t(
                          'Будет экспортировано заметок: ${MaterialLocalizations.of(context).formatDecimal(total)}',
                          'Notes to export: ${MaterialLocalizations.of(context).formatDecimal(total)}',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: Gap.md),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.pageMargin,
                    Gap.md,
                    Gap.pageMargin,
                    Gap.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: PrivacyBadge()),
                      const SizedBox(height: Gap.md),
                      FilledButton(
                        onPressed: _working || total == 0 ? null : _create,
                        child: _working
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  const SizedBox(width: Gap.md),
                                  Text(_t('Создаём…', 'Creating…')),
                                ],
                              )
                            : Text(_t('Создать', 'Create')),
                      ),
                    ],
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
