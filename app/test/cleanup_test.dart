import 'dart:io';

import 'package:backup_merge/cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('cleanup-');
  });
  tearDown(() => scratch.delete(recursive: true));

  test('removes only old merge folders and picker copies', () async {
    final temporary = await Directory('${scratch.path}/tmp').create();
    final cache = await Directory('${scratch.path}/cache').create();
    final oldWork = await Directory('${temporary.path}/kovetz-work-old')
        .create();
    final running = await Directory('${temporary.path}/kovetz-result-running')
        .create();
    final unrelated = await Directory('${temporary.path}/other-app').create();
    final picked = await Directory(
      '${cache.path}/0f8fad5b-d9cb-469f-a165-70867728950e',
    ).create();
    await File('${picked.path}/backup.jwlibrary').writeAsString('personal');
    final otherCache = await Directory('${cache.path}/flutter_assets').create();

    final removed = await removeStaleTemporaryFiles(
      temporary: temporary,
      pickerCache: cache,
      maxAge: const Duration(hours: 12),
      // Folders created now are 13 hours old at this time.
      now: DateTime.now().add(const Duration(hours: 13)),
    );
    expect(removed, 3);
    expect(oldWork.existsSync(), isFalse);
    expect(running.existsSync(), isFalse);
    expect(picked.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
    expect(otherCache.existsSync(), isTrue);
  });

  test('keeps a merge folder that may still be in use', () async {
    final temporary = await Directory('${scratch.path}/tmp').create();
    final running = await Directory('${temporary.path}/kovetz-work-running')
        .create();
    final removed = await removeStaleTemporaryFiles(temporary: temporary);
    expect(removed, 0);
    expect(running.existsSync(), isTrue);
  });
}
