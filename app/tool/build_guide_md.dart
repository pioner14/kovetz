import 'dart:io';

import 'guide_data.dart';

void main() {
  final source = Directory('${guideDocs.path}user-guide');
  for (final language in guideLanguages.keys) {
    final guide = readGuide(source, language);
    File('${source.path}/$language.md')
        .writeAsStringSync(_markdown(guide, language));
  }
  final links = guideLanguages.entries.map(
    (language) => '- [${language.value}](${language.key}.md)',
  );
  File('${source.path}/README.md').writeAsStringSync(
    '# Kovetz\n\n${links.join('\n')}\n\n'
    '[Сайт руководства](../site/index.html) · '
    '[Guide website](../site/index.html)\n',
  );
}

String _markdown(GuideData guide, String language) {
  final out = StringBuffer()
    ..writeln('# ${guide['title']}\n')
    ..writeln("${guide['intro']}\n");

  for (final chapter in guideEntries(guide, 'chapters')) {
    out
      ..writeln('## ${chapter['title']}\n')
      ..writeln("${chapter['summary']}\n");
    for (final block in guideEntries(chapter, 'blocks')) {
      switch (block['type']) {
        case 'p':
          out.writeln(block['text']);
        case 'step':
          final title = block['title'] as String;
          final text = block['text'] as String;
          final body = chapter['id'] == 'install'
              ? text.replaceFirst('GitHub', '[GitHub]($guideReleasesUrl)')
              : text;
          out
            ..writeln('### ${block['number']}. $title\n')
            ..writeln(body);
          if (block['image'] case final String image) {
            final alt = title.replaceAll('[', r'\[').replaceAll(']', r'\]');
            out
              ..writeln()
              ..writeln('![$alt](${guideImagePath(language, image)})');
          }
          if (block['note'] case final String note) {
            out
              ..writeln()
              ..writeln(note);
          }
        case 'tip':
          final label = language == 'ru' ? 'Совет' : 'Tip';
          out.writeln("> **$label.** ${block['text']}");
        case 'warning':
          final label = language == 'ru' ? 'Важно' : 'Important';
          out.writeln("> **$label.** ${block['text']}");
        case 'list':
          for (final item in block['items'] as List<dynamic>) {
            out.writeln('- $item');
          }
        default:
          throw FormatException('Unknown guide block type: ${block['type']}');
      }
      out.writeln();
    }
  }
  return '${out.toString().trimRight()}\n';
}
