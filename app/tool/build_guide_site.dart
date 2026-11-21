import 'dart:convert';
import 'dart:io';

import 'package:kovetz/app_info.dart';

import 'guide_data.dart';

const _escape = HtmlEscape();

void main() {
  final source = Directory('${guideDocs.path}user-guide');
  final site = Directory('${guideDocs.path}site')..createSync(recursive: true);

  for (final language in guideLanguages.keys) {
    final guide = readGuide(source, language);
    final chapters = guideEntries(guide, 'chapters');
    final paths = {
      for (final chapter in chapters)
        for (final block in guideEntries(chapter, 'blocks'))
          if (block['image'] case final String image)
            guideImagePath(language, image),
    };
    for (final image in paths) {
      final target = File('${site.path}/$image');
      target.parent.createSync(recursive: true);
      File('${source.path}/$image').copySync(target.path);
    }
    final page = File('${site.path}/$language/index.html')
      ..createSync(recursive: true);
    page.writeAsStringSync(_guidePage(guide, language));
  }

  File('${site.path}/index.html').writeAsStringSync(_chooser());
  File('${site.path}/guide.css').writeAsStringSync(_styles);
}

String _page({
  required String language,
  required String title,
  required String stylesheet,
  required String body,
}) =>
    '''
<!doctype html>
<html lang="$language">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_escape.convert(title)}</title>
  <link rel="stylesheet" href="$stylesheet">
</head>
<body>
$body
<footer>${_escape.convert(appName)} · ${_escape.convert(appVersion)}</footer>
</body>
</html>
''';

String _chooser() {
  final links = guideLanguages.entries
      .map(
        (entry) =>
            '<li><a class="tap" href="${entry.key}/index.html" '
            'lang="${entry.key}" hreflang="${entry.key}">${_escape.convert(entry.value)}</a></li>',
      )
      .join('\n    ');
  return _page(
    language: 'ru',
    title: 'Kovetz · Руководство',
    stylesheet: 'guide.css',
    body:
        '''
<main id="top">
  <header>
    <h1>Kovetz</h1>
    <p>Выберите язык руководства.</p>
    <p lang="en">Choose your guide language.</p>
  </header>
  <ul class="language-list">
    $links
  </ul>
</main>''',
  );
}

String _guidePage(GuideData guide, String language) {
  final ru = language == 'ru';
  final other = ru ? 'en' : 'ru';
  final title = guide['title'] as String;
  final chapters = guideEntries(guide, 'chapters');
  final tocTitle = ru ? 'Содержание' : 'Contents';
  final top = ru ? 'Наверх' : 'Back to top';
  final choose = ru ? 'Выбрать язык' : 'Choose a language';
  final toc = chapters
      .map(
        (chapter) =>
            '<li><a class="tap" href="#${_escape.convert(chapter['id'] as String)}">'
            '${_escape.convert(chapter['title'] as String)}</a></li>',
      )
      .join('\n      ');
  final sections = chapters
      .map((chapter) => _section(chapter, language))
      .join('\n');

  return _page(
    language: language,
    title: title,
    stylesheet: '../guide.css',
    body:
        '''
<main id="top">
  <header>
    <nav class="language-nav" aria-label="$choose">
      <a class="tap" href="../index.html">$choose</a>
      <a class="tap" href="../$other/index.html" lang="$other" hreflang="$other">${guideLanguages[other]}</a>
    </nav>
    <h1>${_escape.convert(title)}</h1>
    <p>${_escape.convert(guide['intro'] as String)}</p>
  </header>
  <nav class="contents" aria-labelledby="contents-title">
    <h2 id="contents-title">$tocTitle</h2>
    <ul>
      $toc
    </ul>
  </nav>
$sections
</main>
<div class="top-link"><a class="tap" href="#top">↑ $top</a></div>''',
  );
}

String _section(GuideData chapter, String language) {
  final id = _escape.convert(chapter['id'] as String);
  final title = _escape.convert(chapter['title'] as String);
  final summary = _escape.convert(chapter['summary'] as String);
  final blocks = guideEntries(
    chapter,
    'blocks',
  ).map((block) => _block(block, language, id == 'install')).join('\n');
  return '''
  <section id="$id" aria-labelledby="$id-title">
    <h2 id="$id-title">$title</h2>
    <p class="summary">$summary</p>
$blocks
  </section>''';
}

String _block(GuideData block, String language, bool linkReleases) {
  final type = block['type'];
  final ru = language == 'ru';
  switch (type) {
    case 'list':
      final items = (block['items'] as List<dynamic>)
          .map((item) => '<li>${_escape.convert(item as String)}</li>')
          .join('\n      ');
      return '    <ul>\n      $items\n    </ul>';
    case 'step':
      final title = _escape.convert(block['title'] as String);
      final text = _escape.convert(block['text'] as String);
      final body = linkReleases
          ? text.replaceFirst(
              'GitHub',
              '<a href="${_escape.convert(guideReleasesUrl)}">GitHub</a>',
            )
          : text;
      final note = block['note'] as String?;
      final image = block['image'] as String?;
      final illustration = image == null
          ? note == null
                ? ''
                : '\n      <p>${_escape.convert(note)}</p>'
          : '''
 
      <figure>
        <img src="../${_escape.convert(guideImagePath(language, image))}" alt="$title" loading="lazy">
${note == null ? '' : '        <figcaption>${_escape.convert(note)}</figcaption>\n'}      </figure>''';
      return '''
    <article class="step">
      <h3><span class="step-number">${block['number']}.</span> $title</h3>
      <p>$body</p>$illustration
    </article>''';
    case 'p':
      return "    <p>${_escape.convert(block['text'] as String)}</p>";
    case 'tip':
    case 'warning':
      final label = type == 'tip'
          ? (ru ? 'Совет' : 'Tip')
          : (ru ? 'Важно' : 'Important');
      final text = _escape.convert(block['text'] as String);
      return '    <aside class="$type"><p><strong>$label.</strong> $text</p></aside>';
    default:
      throw FormatException('Unknown guide block type: $type');
  }
}

const _styles = '''
:root {
  font-family: system-ui, sans-serif;
  font-size: 20px;
  line-height: 1.6;
  color: #1b1f1d;
  background: #fbfbf8;
  --link: #1f5a44;
}
* { box-sizing: border-box; }
body { margin: 0; overflow-wrap: anywhere; }
main, footer { width: min(100% - 2rem, 48rem); margin: 0 auto; }
header { border-bottom: 3px solid var(--link); padding: 1rem 0; }
h1, h2, h3 { line-height: 1.25; }
h1 { font-size: clamp(1.7rem, 5vw, 2.6rem); margin: .5rem 0; }
h2 { font-size: 1.55rem; }
h3 { font-size: 1.12rem; }
a { color: var(--link); text-underline-offset: .16em; }
a:focus-visible { outline: 3px solid var(--link); outline-offset: 3px; }
.tap { display: inline-block; min-height: 44px; padding: .35rem .65rem; }
.language-nav, .language-list { display: flex; flex-wrap: wrap; gap: .5rem; }
.language-list, .contents ul { list-style: none; padding: 0; }
.language-nav a, .language-list a, .top-link a {
  background: #e9f3ed;
  border: 2px solid var(--link);
  border-radius: .5rem;
  font-weight: 650;
}
.contents { background: #eef3ef; border-radius: .65rem; padding: 1rem; margin-top: 1.5rem; }
.contents h2 { margin: 0 0 .5rem; }
.contents ul { display: grid; grid-template-columns: repeat(2, 1fr); gap: .2rem .6rem; margin: 0; }
section { margin-top: 2.4rem; scroll-margin-top: 1rem; }
.summary { font-weight: 600; }
.step, .tip, .warning { margin: .85rem 0; border-radius: .6rem; padding: .85rem 1rem; }
.step { background: #fff; border: 1px solid #a6b4ab; }
.step h3 { display: flex; gap: .65rem; align-items: baseline; margin: 0; }
.step-number {
  min-width: 2rem;
  padding: .2rem .3rem;
  text-align: center;
  border-radius: .35rem;
  color: #fff;
  background: var(--link);
}
.step p { margin: .65rem 0 0; }
figure { margin: .85rem 0 0; }
figure img {
  display: block;
  max-width: 100%;
  width: auto;
  height: auto;
  max-height: 32rem;
  object-fit: contain;
  border: 4px solid #40574b;
  border-radius: .55rem;
}
figcaption { margin-top: .55rem; }
.warning { background: #fff0dc; border: 2px solid #ac4e16; }
.tip { background: #e9f3ed; border: 2px solid var(--link); }
aside p { margin: 0; }
.top-link {
  position: sticky;
  bottom: .65rem;
  display: flex;
  justify-content: flex-end;
  width: min(100% - 2rem, 48rem);
  margin: 1.3rem auto .7rem;
  pointer-events: none;
}
.top-link a { pointer-events: auto; }
footer { border-top: 1px solid #a6b4ab; padding: .85rem 0 1rem; }
@media (max-width: 36rem) {
  main, footer, .top-link { width: calc(100% - 1.2rem); }
  .contents ul { grid-template-columns: 1fr; }
}
@media print {
  @page { margin: 16mm; }
  :root { font-size: 11pt; background: white; }
  main, footer { width: 100%; }
  .top-link, .language-nav { display: none; position: static; }
  section { break-before: page; margin-top: 0; }
  h2, h3 { break-after: avoid; }
  .step, figure, aside { break-inside: avoid; }
  figure img { max-height: 140mm; border-radius: 0; }
  .step-number { color: #1b1f1d; background: white; border: 1px solid #40574b; }
}
''';
