import 'dart:io';
import 'dart:math';

import 'package:backup_merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

/// Randomised checks of merge invariants on generated backups. Each seed is
/// reproducible; a failure names the seed to replay.
void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('property-');
  });
  tearDown(() => scratch.delete(recursive: true));

  const guids = 12;
  const versions = [8, 14, 16];

  for (var seed = 0; seed < 8; seed++) {
    test(
      'seed $seed: no note is lost and the policy picks its version',
      () async {
        final random = Random(seed);
        final usedMinutes = <int>{};
        // backup path -> guid -> (content, date)
        final inputs = <String, Map<String, (String, DateTime)>>{};
        final count = 2 + random.nextInt(3);
        for (var b = 0; b < count; b++) {
          final notes = <String, (String, DateTime)>{};
          for (var g = 0; g < guids; g++) {
            if (!random.nextBool()) continue;
            int minute;
            do {
              minute = random.nextInt(100000);
            } while (!usedMinutes.add(minute));
            notes['note-$g'] = (
              'text $g from $b #${random.nextInt(1000)}',
              DateTime.utc(2025).add(Duration(minutes: minute)),
            );
          }
          final path = writeBackup(
            scratch,
            'input-$b',
            version: versions[random.nextInt(versions.length)],
            date: DateTime.utc(2025, 6, 1 + b).toIso8601String(),
            prepare: (db) {
              for (var doc = 1; doc <= 3; doc++) {
                addDocument(db, doc, 100 + doc);
              }
              var id = 0;
              for (final MapEntry(key: guid, value: (body, date))
                  in notes.entries) {
                note(
                  db,
                  id: ++id,
                  guid: guid,
                  location: 1 + random.nextInt(3),
                  body: body,
                  date: date.toIso8601String(),
                );
              }
            },
          );
          inputs[path] = notes;
        }
        final paths = inputs.keys.toList();
        final union = {for (final notes in inputs.values) ...notes.keys};

        Map<String, String> contents(String archive, String name) {
          final dir = Directory('${scratch.path}/$name')..createSync();
          final output = readOutput(dir, archive, version: 16);
          return {
            for (final row in output.db.select(
              'SELECT Guid, Content FROM Note',
            ))
              row['Guid'] as String: row['Content'] as String,
          };
        }

        // Newest LastModified wins for every GUID.
        final newest = await mergeArchives(paths, (_) {});
        final merged = contents(newest.archivePath, 'newest');
        expect(merged.keys.toSet(), union, reason: 'seed $seed');
        for (final guid in union) {
          final latest = inputs.values
              .map((notes) => notes[guid])
              .nonNulls
              .reduce((a, b) => a.$2.isAfter(b.$2) ? a : b);
          expect(merged[guid], latest.$1, reason: 'seed $seed, $guid');
        }

        // The primary backup wins for every GUID it contains.
        final primaryPath = paths[random.nextInt(paths.length)];
        final primary = await mergeArchives(
          paths,
          (_) {},
          options: MergeOptions(
            primaryPath: primaryPath,
            notePolicy: NoteConflictPolicy.primary,
          ),
        );
        final chosen = contents(primary.archivePath, 'primary');
        expect(chosen.keys.toSet(), union, reason: 'seed $seed');
        for (final MapEntry(key: guid, value: (body, _))
            in inputs[primaryPath]!.entries) {
          expect(chosen[guid], body, reason: 'seed $seed, $guid');
        }

        // Merging the result again with an input changes nothing.
        final again = await mergeArchives([
          newest.archivePath,
          paths.first,
        ], (_) {});
        expect(
          contents(again.archivePath, 'again'),
          merged,
          reason: 'seed $seed',
        );
      },
    );
  }
}
