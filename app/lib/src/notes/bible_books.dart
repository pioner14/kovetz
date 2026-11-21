/// Bible book names in the order of JW Library book numbers 1–66.
const bibleBooksRu = <String>[
  'Бытие', 'Исход', 'Левит', 'Числа', 'Второзаконие', 'Иисус Навин', //
  'Судьи', 'Руфь', '1 Самуила', '2 Самуила', '1 Царей', '2 Царей', //
  '1 Летопись', '2 Летопись', 'Ездра', 'Неемия', 'Эсфирь', 'Иов', //
  'Псалмы', 'Притчи', 'Экклезиаст', 'Песнь песней', 'Исаия', 'Иеремия', //
  'Плач Иеремии', 'Иезекииль', 'Даниил', 'Осия', 'Иоиль', 'Амос', //
  'Авдий', 'Иона', 'Михей', 'Наум', 'Аввакум', 'Софония', 'Аггей', //
  'Захария', 'Малахия', 'Матфея', 'Марка', 'Луки', 'Иоанна', 'Деяния', //
  'Римлянам', '1 Коринфянам', '2 Коринфянам', 'Галатам', 'Эфесянам', //
  'Филиппийцам', 'Колоссянам', '1 Фессалоникийцам', '2 Фессалоникийцам', //
  '1 Тимофею', '2 Тимофею', 'Титу', 'Филимону', 'Евреям', 'Иакова', //
  '1 Петра', '2 Петра', '1 Иоанна', '2 Иоанна', '3 Иоанна', 'Иуды', //
  'Откровение',
];

const bibleBooksEn = <String>[
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', //
  'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', //
  '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job', //
  'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah', //
  'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', //
  'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', //
  'Haggai', 'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John', //
  'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', //
  'Ephesians', 'Philippians', 'Colossians', '1 Thessalonians', //
  '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon', //
  'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John', //
  'Jude', 'Revelation',
];

/// Reference such as "Римлянам 15:13", "Псалом 23:1" or "Иуды 3".
String bibleReference(
  int book,
  int? chapter,
  int? verse, {
  required bool russian,
}) {
  final names = russian ? bibleBooksRu : bibleBooksEn;
  if (book < 1 || book > names.length) {
    return russian ? 'Книга $book' : 'Book $book';
  }
  // A single Psalm is named in the singular in references.
  var name = names[book - 1];
  if (book == 19 && chapter != null && chapter > 0) {
    name = russian ? 'Псалом' : 'Psalm';
  }
  if (chapter == null || chapter == 0) return name;
  return verse == null ? '$name $chapter' : '$name $chapter:$verse';
}
