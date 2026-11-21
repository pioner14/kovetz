import 'dart:convert';
import 'dart:io';

import 'package:backup_merge/app_info.dart';

const guideLanguages = {'ru': 'Русский', 'en': 'English'};
const guideReleasesUrl = '$appRepository/releases';

Directory get guideDocs =>
    Directory.fromUri(Platform.script.resolve('../../docs/'));

typedef GuideData = Map<String, dynamic>;

GuideData readGuide(Directory source, String language) =>
    jsonDecode(File('${source.path}/guide.$language.json').readAsStringSync())
        as GuideData;

List<GuideData> guideEntries(GuideData parent, String key) =>
    (parent[key] as List<dynamic>).cast<GuideData>();

String guideImagePath(String language, String image) =>
    'images/$language/$image.png';
