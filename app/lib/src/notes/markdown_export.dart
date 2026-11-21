import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'notes_model.dart';

/// Options of a Markdown export.
class MarkdownOptions {
  const MarkdownOptions({
    this.includeUntagged = false,
    this.russian = true,
    this.exportedAt,
  });

  /// Also export notes without user tags, listed under a "no tag" index.
  final bool includeUntagged;
  final bool russian;

  /// Date shown in the index; defaults to today.
  final DateTime? exportedAt;
}

/// Builds an Obsidian-friendly folder: one file per note with YAML
/// frontmatter, one index per tag and a main index. Returns relative paths
/// (always with `/`) and file contents, so it can be written to a folder or
/// packed into an archive.
///
/// A note with several tags is stored once and listed in every tag index.
Map<String, String> buildMarkdownExport(
  NotesCollection collection, [
  MarkdownOptions options = const MarkdownOptions(),
]) {
  final ru = options.russian;
  String tr(String a, String b) => ru ? a : b;
  final notesDir = tr('Заметки', 'Notes');
  final tagsDir = tr('Теги', 'Tags');
  final untagged = tr('Без тега', 'Untagged');
  final selected = collection.notes
      .where((note) => note.tags.isNotEmpty || options.includeUntagged)
      .toList();

  final files = <String, String>{};
  final usedNames = <String>{};
  final noteLinks = <BackupNote, String>{};
  for (final note in selected) {
    final base = _fileName(_noteName(note));
    var name = base;
    for (var n = 2; !usedNames.add(name.toLowerCase()); n++) {
      name = '$base ($n)';
    }
    noteLinks[note] = '$notesDir/$name';
  }

  final byTag = <String, List<BackupNote>>{};
  for (final note in selected) {
    for (final tag in note.tags.isEmpty ? [untagged] : note.tags) {
      (byTag[tag] ??= []).add(note);
    }
  }
  final tagNames = byTag.keys.toList()
    ..sort((a, b) {
      final byCount = byTag[b]!.length.compareTo(byTag[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  // Tags differing only in case ("english", "English") need distinct files:
  // Windows, Android and Obsidian treat such names as the same file.
  final tagFiles = <String, String>{};
  final usedTagNames = <String>{};
  for (final tag in tagNames) {
    final base = _fileName(tag);
    var name = base;
    for (var n = 2; !usedTagNames.add(name.toLowerCase()); n++) {
      name = '$base ($n)';
    }
    tagFiles[tag] = '$tagsDir/$name';
  }
  for (final tag in tagNames) {
    final file = tagFiles[tag]!;
    final lines = [
      '---',
      'tags: [${_yaml('jw/${tr('тег', 'tag')}')}]',
      '---',
      '# $tag',
      '',
      tr('Заметок: ${byTag[tag]!.length}.', 'Notes: ${byTag[tag]!.length}.'),
      '',
    ];
    NoteSourceKind? section;
    for (final note in byTag[tag]!) {
      if (note.source.kind != section) {
        section = note.source.kind;
        lines
          ..add('')
          ..add('## ${_sectionTitle(section, ru)}')
          ..add('');
      }
      final title = note.title.isEmpty ? '' : ' — ${note.title}';
      lines.add(
        '- [[${noteLinks[note]}|${_escapeLink('${note.source.label}$title')}]]',
      );
    }
    files['$file.md'] = '${lines.join('\n')}\n';
  }

  for (final note in selected) {
    files['${noteLinks[note]}.md'] = _noteFile(note, ru, tagFiles, untagged);
  }

  final date = (options.exportedAt ?? DateTime.now()).toIso8601String();
  final index = [
    '# ${tr('Заметки из JW Library', 'Notes from JW Library')}',
    '',
    tr('Бэкап: ${collection.backupName}', 'Backup: ${collection.backupName}'),
    tr(
      'Экспорт: ${date.substring(0, 10)}',
      'Exported: ${date.substring(0, 10)}',
    ),
    tr('Заметок: ${selected.length}', 'Notes: ${selected.length}'),
    '',
    '## ${tr('Теги', 'Tags')}',
    '',
    for (final tag in tagNames)
      '- [[${tagFiles[tag]}|${_escapeLink(tag)}]] — ${byTag[tag]!.length}',
  ];
  files['${tr('Указатель', 'Index')}.md'] = '${index.join('\n')}\n';
  return files;
}

/// Writes [files] under [root], creating folders. Existing files with the same
/// names are replaced; other files in [root] are left alone.
Future<void> writeMarkdownExport(
  Map<String, String> files,
  Directory root,
) async {
  for (final entry in files.entries) {
    final file = File(p.joinAll([root.path, ...entry.key.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
}

String _sectionTitle(NoteSourceKind kind, bool ru) => switch (kind) {
  NoteSourceKind.bible => ru ? 'Библия' : 'Bible',
  NoteSourceKind.publication => ru ? 'Публикации' : 'Publications',
  NoteSourceKind.none => ru ? 'Без привязки' : 'Not linked',
};

String _noteName(BackupNote note) {
  final title = note.title.isNotEmpty
      ? note.title
      : note.content.split('\n').first;
  return '${note.source.label} — $title';
}

String _noteFile(
  BackupNote note,
  bool ru,
  Map<String, String> tagFiles,
  String untagged,
) {
  final tags = note.tags.isEmpty ? [untagged] : note.tags;
  final front = [
    '---',
    if (note.title.isNotEmpty) 'title: ${_yaml(note.title)}',
    'source: ${_yaml(note.source.label)}',
    'tags: [${tags.map((t) => _yaml(_obsidianTag(t))).join(', ')}]',
    'jw_tags: [${tags.map(_yaml).join(', ')}]',
    if (note.created != null) 'created: ${_yaml(note.created!)}',
    if (note.modified != null) 'modified: ${_yaml(note.modified!)}',
    'jw_guid: ${_yaml(note.guid)}',
    '---',
  ];
  final heading = note.title.isNotEmpty ? note.title : note.source.label;
  final body = [
    '# $heading',
    '',
    '> ${note.source.label}',
    '',
    if (note.content.isNotEmpty) note.content,
    '',
    '${ru ? 'Теги' : 'Tags'}: '
        '${tags.map((t) => '[[${tagFiles[t]}|${_escapeLink(t)}]]').join(', ')}',
  ];
  return '${[...front, ...body].join('\n')}\n';
}

/// A double-quoted YAML scalar; JSON string syntax is valid YAML.
String _yaml(String value) => jsonEncode(value);

/// Obsidian tags cannot contain spaces or most punctuation.
String _obsidianTag(String tag) =>
    'jw/${tag.trim().replaceAll(RegExp(r'[\s#,.:;!?"\x27()\[\]{}<>|\\/]+'), '_')}';

/// Link text must not close the wikilink or start an alias.
String _escapeLink(String text) => text
    .replaceAll(RegExp(r'[\[\]|]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A file name valid on Windows, Android and Linux and in Obsidian links.
String _fileName(String text) {
  var name = text
      .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final deviceName = RegExp(
    r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?: *\.|$)',
    caseSensitive: false,
  );
  if (deviceName.hasMatch(name)) name = '_$name';
  if (name.length > 100) name = String.fromCharCodes(name.runes.take(100));
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  return name.isEmpty ? '_' : name;
}

/// The export as one ZIP file, for devices where a folder cannot be written
/// directly (Android). Paths inside use `/` and UTF-8 names.
List<int> markdownExportZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
