import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

import '../export.dart';
import '../merge.dart';
import 'l10n.dart';
import 'export_notes_screen.dart';
import 'messages.dart';
import 'theme.dart';
import 'widgets.dart';

class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key});

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _Backup {
  const _Backup(this.filePath, this.size, this.modified);

  final String filePath;
  final int size;
  final DateTime? modified;
  String get name => path.basename(filePath);
}

class _MergeScreenState extends State<MergeScreen> {
  final List<_Backup> _inputs = [];
  MergeResult? _result;
  List<String> _resultSources = const [];
  String? _stage;
  Completer<void>? _cancel;
  bool _picking = false;
  bool _exporting = false;
  bool _dragging = false;
  bool _selectionChanged = false;

  /// 0 files, 1 rules, 2 result (progress or done).
  int _step = 0;
  String? _primaryPath;
  NoteConflictPolicy _notePolicy = NoteConflictPolicy.newest;
  FieldConflictPolicy _fieldPolicy = FieldConflictPolicy.primary;
  String? _exportError;
  bool get _mobile => Platform.isAndroid;
  bool get _busy => _stage != null || _picking || _exporting;

  String _t(String ru, String en) => localText(context, ru, en);

  String? _languageSeen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The TXT report is written in the language chosen when merging, so a
    // result made in another language is stale.
    final language = Localizations.localeOf(context).languageCode;
    if (_languageSeen != null && _languageSeen != language && _result != null) {
      _selectionChanged = true;
    }
    _languageSeen = language;
  }

  Future<void> _cleanup(MergeResult? result) async {
    if (result == null) return;
    try {
      await File(result.archivePath).parent.delete(recursive: true);
    } on FileSystemException {
      // The operating system can reclaim the private temporary directory.
    }
  }

  @override
  void dispose() {
    if (_cancel?.isCompleted == false) _cancel!.complete();
    unawaited(_cleanup(_result));
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _picking = true);
    try {
      // The extension has no system document type on mobile.
      const group = XTypeGroup(label: 'JW Library', extensions: ['jwlibrary']);
      final files = await openFiles(acceptedTypeGroups: _mobile ? [] : [group]);
      if (mounted) await _add(files);
    } catch (_) {
      if (mounted) {
        _notice(_t('Не удалось открыть файлы.', 'Could not open files.'));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _add(List<XFile> files) async {
    final added = <_Backup>[];
    var invalid = false;
    for (final file in files) {
      final extension = path.extension(file.name).toLowerCase();
      // Some Android providers assign generic archive MIME types. The native
      // picker can replace the source extension with the MIME-derived one.
      final allowed =
          extension == '.jwlibrary' ||
          (Platform.isAndroid && (extension == '.zip' || extension == '.bin'));
      if (!allowed) {
        invalid = true;
        continue;
      }
      try {
        DateTime? modified;
        try {
          modified = await file.lastModified();
        } on Object {
          // Some providers cannot tell; the date is only informational.
        }
        added.add(_Backup(file.path, await file.length(), modified));
      } catch (_) {
        invalid = true;
      }
    }
    if (!mounted) return;
    setState(() {
      for (final file in added) {
        if (_inputs.every(
          (input) => !path.equals(input.filePath, file.filePath),
        )) {
          _inputs.add(file);
          _selectionChanged = true;
        }
      }
    });
    if (invalid) {
      _notice(
        _t(
          'Можно добавить только доступные файлы .jwlibrary.',
          'Choose readable .jwlibrary files.',
        ),
      );
    }
  }

  Future<void> _merge() async {
    if (_busy || _inputs.length < 2) return;
    final previousResult = _result;
    final sources = _inputs
        .map((input) => input.filePath)
        .toList(growable: false);
    final options = MergeOptions(
      primaryPath: _primaryPath,
      notePolicy: _notePolicy,
      fieldPolicy: _fieldPolicy,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    final cancel = Completer<void>();
    setState(() {
      _stage = 'reading';
      _cancel = cancel;
      _step = 2;
    });
    try {
      final result = await mergeArchives(
        sources,
        (stage) {
          if (mounted) setState(() => _stage = stage);
        },
        options: options,
        cancel: cancel.future,
      );
      if (!mounted) {
        await _cleanup(result);
        return;
      }
      setState(() {
        _result = result;
        _resultSources = sources;
        _selectionChanged = false;
        _exportError = null;
      });
      await _cleanup(previousResult);
    } on MergeFailure catch (error) {
      if (mounted) {
        setState(() => _step = previousResult == null ? 1 : 2);
        _notice(mergeErrorMessage(error, _t));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _step = previousResult == null ? 1 : 2);
        _notice(
          _t(
            'Не удалось создать объединённый бэкап.',
            'Could not create the merged backup.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _stage = null;
          _cancel = null;
        });
      }
    }
  }

  Future<void> _export() async {
    final result = _result;
    if (result == null || _busy || _selectionChanged) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final filename = path.basename(result.archivePath);
      if (Platform.isAndroid) {
        const channel = MethodChannel('dev.backupmerge/export');
        final saved = await channel.invokeMethod<Object?>('savePair', {
          'path': result.archivePath,
          'reportPath': result.reportPath,
        });
        if (saved is Map && saved['saved'] == true && mounted) {
          _notice(
            _t('Бэкап и TXT-отчёт сохранены.', 'Backup and TXT report saved.'),
          );
        }
      } else {
        final location = await getSaveLocation(
          suggestedName: filename,
          confirmButtonText: _t('Сохранить', 'Save'),
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JW Library', extensions: ['jwlibrary']),
          ],
        );
        if (location == null) return;
        final destination =
            path.extension(location.path).toLowerCase() == '.jwlibrary'
            ? location.path
            : '${location.path}.jwlibrary';
        final reportDestination = path.setExtension(destination, '.report.txt');
        final destinations = [destination, reportDestination];
        final existing = <String>[];
        for (final output in destinations) {
          final exists =
              await FileSystemEntity.type(output, followLinks: false) !=
              FileSystemEntityType.notFound;
          if (await wouldReplaceSource(output, exists, {
            ..._resultSources,
            ..._inputs.map((input) => input.filePath),
          })) {
            if (mounted) {
              setState(
                () => _exportError = _t(
                  'Выберите другое имя для результата: этот путь совпадает с исходным бэкапом.',
                  'Choose a different name: this destination is a source backup.',
                ),
              );
            }
            return;
          }
          if (exists) existing.add(output);
        }
        if (existing.isNotEmpty) {
          if (!mounted || !await _confirmOverwrite(existing)) return;
        }
        await saveBackupPair(
          archiveSource: result.archivePath,
          reportSource: result.reportPath,
          archiveDestination: destination,
          reportDestination: reportDestination,
        );
        if (mounted) {
          _notice(
            _t('Бэкап и TXT-отчёт сохранены.', 'Backup and TXT report saved.'),
          );
        }
      }
    } on PlatformException catch (error) {
      if (mounted) {
        final details = error.details;
        final cleanupIncomplete =
            details is Map && details['cleanupIncomplete'] == true;
        setState(
          () => _exportError = cleanupIncomplete
              ? _t(
                  'Сохранение прервано. В выбранной папке могли остаться неполные файлы — удалите их перед повторным сохранением или выберите другую папку. Результат доступен в приложении.',
                  'Saving was interrupted. Incomplete files may remain in the selected folder. Remove them before trying again or choose another folder. The result remains available in the app.',
                )
              : _t(
                  'Не удалось сохранить оба файла. Проверьте доступ и свободное место и повторите сохранение.',
                  'Could not save both files. Check permissions and storage, then try saving again.',
                ),
        );
      }
    } on ExportFailure catch (error) {
      if (mounted) {
        setState(
          () => _exportError = error.recoveryDirectory == null
              ? _t(
                  'Оба файла сохранить не удалось. Проверьте доступ и свободное место и повторите сохранение.',
                  'Could not save both files. Check permissions and storage, then try saving again.',
                )
              : _t(
                  'Сохранение прервано. Файлы для восстановления находятся в папке \n${error.recoveryDirectory}\nРезультат доступен для повторного сохранения.',
                  'Saving was interrupted. Recovery files are in \n${error.recoveryDirectory}\nThe result can be saved again.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _exportError = _t(
            'Не удалось подтвердить сохранение обоих файлов. Проверьте выбранную папку и повторите сохранение. Результат доступен в приложении.',
            'Could not confirm that both files were saved. Check the selected folder and try again; the result remains available in the app.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool> _confirmOverwrite(List<String> destinations) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _t('Заменить существующие файлы?', 'Replace existing files?'),
          ),
          content: Text(destinations.map(path.basename).join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Отмена', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Заменить', 'Replace')),
            ),
          ],
        ),
      ) ??
      false;

  String _size(int bytes) {
    final format = MaterialLocalizations.of(context);
    if (bytes < 1024) return '${format.formatDecimal(bytes)} ${_t('Б', 'B')}';
    if (bytes < 1024 * 1024) {
      return '${format.formatDecimal((bytes / 1024).round())} ${_t('КБ', 'KB')}';
    }
    return '${format.formatDecimal((bytes / (1024 * 1024)).round())} ${_t('МБ', 'MB')}';
  }

  // ----------------------------------------------------------------- UI --

  static const _stages = ['reading', 'merging', 'checking', 'packing'];

  String _date(DateTime? value) {
    if (value == null) return '';
    const ru = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', //
      'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    const en = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', //
      'Oct', 'Nov', 'Dec',
    ];
    final local = value.toLocal();
    return _t(
      '${local.day} ${ru[local.month - 1]} ${local.year}',
      '${en[local.month - 1]} ${local.day}, ${local.year}',
    );
  }

  String _notePolicyLabel(NoteConflictPolicy policy) => switch (policy) {
    NoteConflictPolicy.newest => _t('Самая свежая версия', 'Newest version'),
    NoteConflictPolicy.primary => _t(
      'Из основного бэкапа',
      'From the primary backup',
    ),
  };

  String _fieldPolicyLabel(FieldConflictPolicy policy) => switch (policy) {
    FieldConflictPolicy.primary => _t(
      'Из основного бэкапа',
      'From the primary backup',
    ),
    FieldConflictPolicy.newestBackup => _t(
      'Из самого нового бэкапа',
      'From the newest backup',
    ),
  };

  bool _needsReview(MergeResult result) =>
      result.skippedBookmarks > 0 ||
      result.warnings.any(
        (warning) =>
            warning.count > 0 &&
            (warning.code == 'unresolvedLinks' ||
                warning.code == 'missingMedia'),
      );

  int _reviewCount(MergeResult result) =>
      result.skippedBookmarks +
      result.warnings
          .where((w) => w.code == 'unresolvedLinks' || w.code == 'missingMedia')
          .fold(0, (sum, w) => sum + w.count);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        setState(() => _step = _step == 2 ? 1 : 0);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _busy ? null : () => Navigator.maybePop(context),
          ),
          title: Text(_t('Объединить бэкапы', 'Merge backups')),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.pageMargin,
                      0,
                      Gap.pageMargin,
                      Gap.md,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _buildStepper(theme),
                    ),
                  ),
                  Expanded(
                    child: switch (_step) {
                      0 => _buildFiles(theme),
                      1 => _buildRules(theme),
                      _ =>
                        _stage != null || _result == null
                            ? _buildProgress(theme)
                            : _buildDone(theme),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepper(ThemeData theme) {
    final colors = theme.colorScheme;
    final names = [
      _t('Файлы', 'Files'),
      _t('Правила', 'Rules'),
      _t('Результат', 'Result'),
    ];
    return Semantics(
      label: _t(
        'Шаг ${_step + 1} из 3: ${names[_step]}',
        'Step ${_step + 1} of 3: ${names[_step]}',
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ),
            Text(
              names[i],
              style: theme.textTheme.labelMedium?.copyWith(
                color: i == _step ? colors.primary : colors.onSurfaceVariant,
                fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Scrolling content with a pinned action area under it.
  Widget _page({required List<Widget> children, required Widget action}) =>
      Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.pageMargin),
              children: children,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.pageMargin,
              Gap.md,
              Gap.pageMargin,
              Gap.lg,
            ),
            child: SizedBox(width: double.infinity, child: action),
          ),
        ],
      );

  // ---- step 1: files

  Widget _buildFiles(ThemeData theme) {
    final colors = theme.colorScheme;
    final zone = DashedBox(
      highlighted: _dragging,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.upload_file_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(
            _t('Добавьте файлы .jwlibrary', 'Add .jwlibrary files'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (!_mobile) ...[
            const SizedBox(height: 2),
            Text(
              _t('или перетащите их сюда', 'or drop them here'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(_t('Выбрать файлы', 'Choose files')),
          ),
        ],
      ),
    );
    final target = _mobile
        ? zone
        : DropTarget(
            onDragEntered: (_) {
              if (!_busy) setState(() => _dragging = true);
            },
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) async {
              if (_busy) return;
              setState(() {
                _dragging = false;
                _picking = true;
              });
              try {
                await _add(details.files);
              } finally {
                if (mounted) setState(() => _picking = false);
              }
            },
            child: zone,
          );
    return _page(
      children: [
        target,
        const SizedBox(height: Gap.lg),
        for (final backup in _inputs) ...[
          _buildBackupCard(theme, backup),
          const SizedBox(height: Gap.md),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  _inputs.length < 2
                      ? _t(
                          'Добавьте как минимум два файла .jwlibrary.',
                          'Add at least two .jwlibrary files.',
                        )
                      : _t(
                          'Основной бэкап задаёт порядок закладок и избранного. Если он не выбран, берётся самый свежий.',
                          'The primary backup sets the order of bookmarks and favourites. If none is chosen, the newest is used.',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      action: FilledButton(
        onPressed: _busy || _inputs.length < 2
            ? null
            : () => setState(() => _step = 1),
        child: Text(_t('Далее', 'Next')),
      ),
    );
  }

  Widget _buildBackupCard(ThemeData theme, _Backup backup) {
    final colors = theme.colorScheme;
    final primary = _primaryPath == backup.filePath;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: primary
              ? colors.primary
              : colors.outlineVariant.withValues(alpha: 0.4),
          width: primary ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smartphone_rounded, color: colors.onSurfaceVariant),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backup.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      [
                        _date(backup.modified),
                        _size(backup.size),
                      ].where((part) => part.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t('Убрать файл', 'Remove file'),
                icon: const Icon(Icons.close_rounded),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _inputs.remove(backup);
                        if (primary) _primaryPath = null;
                        _selectionChanged = true;
                      }),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Gap.sm),
            child: FilterChip(
              avatar: Icon(
                primary ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
              ),
              label: Text(_t('Основной', 'Primary')),
              selected: primary,
              showCheckmark: false,
              onSelected: _busy
                  ? null
                  : (value) => setState(() {
                      _primaryPath = value ? backup.filePath : null;
                      _selectionChanged = true;
                    }),
            ),
          ),
        ],
      ),
    );
  }

  // ---- step 2: rules

  Widget _buildRules(ThemeData theme) {
    final colors = theme.colorScheme;
    Widget section(String title, List<Widget> tiles) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.sm),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        for (final tile in tiles) ...[tile, const SizedBox(height: Gap.sm)],
      ],
    );
    return _page(
      children: [
        section(_t('Заметки с одинаковым ID', 'Notes with the same ID'), [
          for (final policy in NoteConflictPolicy.values)
            ChoiceTile(
              title: _notePolicyLabel(policy),
              selected: _notePolicy == policy,
              onTap: () => setState(() {
                _notePolicy = policy;
                _selectionChanged = true;
              }),
            ),
        ]),
        const SizedBox(height: Gap.sm),
        section(_t('Ответы в публикациях', 'Publication answers'), [
          for (final policy in FieldConflictPolicy.values)
            ChoiceTile(
              title: _fieldPolicyLabel(policy),
              selected: _fieldPolicy == policy,
              onTap: () => setState(() {
                _fieldPolicy = policy;
                _selectionChanged = true;
              }),
            ),
        ]),
        const SizedBox(height: Gap.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    _t(
                      'Отличающиеся версии не теряются — они будут перечислены в отчёте.',
                      'Differing versions are not lost — they will be listed in the report.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: PrivacyBadge()),
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: _busy || _inputs.length < 2 ? null : _merge,
            child: Text(_t('Объединить', 'Merge')),
          ),
        ],
      ),
    );
  }

  // ---- step 3: progress and result

  Widget _buildProgress(ThemeData theme) {
    final colors = theme.colorScheme;
    final current = _stages.indexOf(_stage ?? 'reading');
    final names = [
      _t('Чтение', 'Reading'),
      _t('Объединение', 'Merging'),
      _t('Проверка', 'Checking'),
      _t('Упаковка', 'Packing'),
    ];
    return _page(
      children: [
        const SizedBox(height: Gap.xl),
        Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: colors.surfaceContainerHigh,
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Semantics(
          liveRegion: true,
          child: Text(
            stageLabel(_stage ?? 'reading', _t),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: Gap.xl),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              children: [
                for (var i = 0; i < names.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        if (i < current)
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: colors.primary,
                          )
                        else if (i == current)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: colors.outline,
                          ),
                        const SizedBox(width: Gap.md),
                        Text(
                          names[i],
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: i == current
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i > current
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      action: TextButton(
        onPressed: _cancel == null || _cancel!.isCompleted
            ? null
            : () => setState(() => _cancel!.complete()),
        child: Text(_t('Отменить', 'Cancel')),
      ),
    );
  }

  Widget _buildDone(ThemeData theme) {
    final colors = theme.colorScheme;
    final status = theme.extension<StatusColors>()!;
    final result = _result!;
    final format = MaterialLocalizations.of(context);
    String count(String key) => format.formatDecimal(result.counts[key] ?? 0);
    final review = _needsReview(result);
    return _page(
      children: [
        const SizedBox(height: Gap.sm),
        Center(
          child: Image.asset(
            'assets/images/success.png',
            width: 140,
            height: 140,
            excludeFromSemantics: true,
          ),
        ),
        Text(
          _t('Готово', 'Done'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge,
        ),
        const SizedBox(height: Gap.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Gap.sm,
          crossAxisSpacing: Gap.sm,
          childAspectRatio: 3.6,
          children: [
            StatChip(label: _t('Заметки', 'Notes'), value: count('Note')),
            StatChip(
              label: _t('Выделения', 'Highlights'),
              value: count('UserMark'),
            ),
            StatChip(
              label: _t('Закладки', 'Bookmarks'),
              value: count('Bookmark'),
            ),
            StatChip(label: _t('Теги', 'Tags'), value: count('Tag')),
          ],
        ),
        const SizedBox(height: Gap.lg),
        if (review)
          DecoratedBox(
            decoration: BoxDecoration(
              color: status.warningContainer,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: status.onWarningContainer,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      _t(
                        'Проверьте записи: ${format.formatDecimal(_reviewCount(result))} — подробности в отчёте',
                        'Review ${format.formatDecimal(_reviewCount(result))} records — details are in the report',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: status.onWarningContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (result.noteConflicts + result.fieldConflicts > 0)
          Text(
            _t(
              'Различающиеся версии сохранены в отчёте: ${result.noteConflicts + result.fieldConflicts}.',
              'Differing versions are kept in the report: ${result.noteConflicts + result.fieldConflicts}.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        if (_selectionChanged) ...[
          const SizedBox(height: Gap.md),
          Text(
            _t(
              'Язык или правила изменились. Это предыдущий результат — его сохранение отключено. Нажмите «Объединить заново».',
              'The language or rules changed. This is the previous result, so saving it is disabled. Choose “Merge again”.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
        ],
        if (_exportError != null) ...[
          const SizedBox(height: Gap.md),
          Semantics(
            liveRegion: true,
            child: SelectableText(
              _exportError!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        Text(
          _mobile
              ? _t(
                  'Выберите папку: в неё сохранятся бэкап и TXT-отчёт.',
                  'Choose a folder for the backup and TXT report.',
                )
              : _t(
                  'Бэкап и TXT-отчёт сохранятся рядом.',
                  'The backup and TXT report are saved together.',
                ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _busy || _selectionChanged ? null : _export,
            child: Text(
              _t('Сохранить бэкап и отчёт', 'Save backup and report'),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FilledButton.tonal(
            onPressed: _busy || _selectionChanged
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ExportNotesScreen(initialBackup: result.archivePath),
                    ),
                  ),
            child: Text(
              _t(
                'Экспортировать заметки из результата',
                'Export notes from the result',
              ),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    final old = _result;
                    _result = null;
                    _selectionChanged = false;
                    _exportError = null;
                    _step = 0;
                    unawaited(_cleanup(old));
                  }),
            child: Text(_t('Объединить заново', 'Merge again')),
          ),
        ],
      ),
    );
  }
}
