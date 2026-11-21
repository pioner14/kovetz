import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:backup_merge/merge.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('report-history-');
  });
  tearDown(() => scratch.delete(recursive: true));

  // These tests cover importing history from results of versions up to
  // 0.4.2, which kept the machine report inside the archive. A fresh result
  // must be clean; it is then rewritten in that older layout.
  MergeResult keep(MergeResult result) {
    addTearDown(() => File(result.archivePath).parent.delete(recursive: true));
    expectOnlyJwLibraryEntries(
      ZipDecoder().decodeBytes(File(result.archivePath).readAsBytesSync()),
    );
    embedReportLikeOldVersions(result);
    return result;
  }

  Map<String, dynamic> report(MergeResult result) => recoveryReport(result)!;

  String source(String name, String text, String date) => writeBackup(
    scratch,
    name,
    version: 16,
    date: date,
    prepare: (db) {
      addDocument(db, 1, 101);
      note(db, id: 1, guid: 'shared', location: 1, body: text, date: date);
    },
  );

  for (final policy in NoteConflictPolicy.values) {
    test(
      'JSON retains all three note versions and identifies the selected $policy version',
      () async {
        final old = source('old', 'old text', fixtureEarlier);
        final middle = source('middle', 'middle text', fixtureLater);
        final latest = source('latest', 'latest text', '2025-03-01T00:00:00Z');
        final result = keep(
          await mergeArchives(
            [latest, middle, old],
            (_) {},
            options: MergeOptions(primaryPath: old, notePolicy: policy),
          ),
        );
        final versions = (report(result)['conflictVersions'] as List)
            .cast<Map>();
        expect(versions, hasLength(3));
        expect(
          versions.map((v) => (v['record'] as Map)['Content']),
          unorderedEquals(['old text', 'middle text', 'latest text']),
        );
        final selected = versions.where((v) => v['selected'] == true).single;
        expect(
          (selected['record'] as Map)['Content'],
          policy == NoteConflictPolicy.primary ? 'old text' : 'latest text',
        );
        for (final version in versions) {
          expect(
            version['sourceFingerprint'],
            matches(RegExp(r'^[0-9a-f]{64}$')),
          );
          expect(version['versionId'], matches(RegExp(r'^[0-9a-f]{64}$')));
          expect(version['context'], isNotEmpty);
        }
      },
    );
  }

  test(
    'alternatives and selected-version provenance survive another merge',
    () async {
      final old = source('old', 'old text', fixtureEarlier);
      final middle = source('middle', 'middle text', fixtureLater);
      final first = keep(await mergeArchives([old, middle], (_) {}));
      final latest = source('latest', 'latest text', '2025-03-01T00:00:00Z');
      final result = keep(
        await mergeArchives([first.archivePath, latest], (_) {}),
      );
      final versions = (report(result)['conflictVersions'] as List).cast<Map>();
      expect(versions.map((v) => (v['record'] as Map)['Content']).toSet(), {
        'old text',
        'middle text',
        'latest text',
      });
      expect(
        versions.where((v) => v['selected'] == true).single['fileName'],
        'latest.jwlibrary',
      );
      final text = File(result.reportPath).readAsStringSync();
      for (final body in ['old text', 'middle text', 'latest text']) {
        expect(text, contains(body));
      }
    },
  );

  test(
    'a renamed identical input can be explicitly chosen as primary',
    () async {
      final original = source('original', 'kept', fixtureEarlier);
      final copy = File(original)
          .copySync('${scratch.path}/chosen-copy.jwlibrary');
      final result = keep(
        await mergeArchives(
          [original, copy.path],
          (_) {},
          options: MergeOptions(primaryPath: copy.path),
        ),
      );
      expect(result.primaryFileName, 'chosen-copy.jwlibrary');
      expect(result.counts['Note'], 1);
      expect(result.noteConflicts, 0);
      expect(result.warnings, isEmpty);
    },
  );

  test(
    'old aggregate-only reports deduplicate common recovery history',
    () async {
      final bad = writeBackup(
        scratch,
        'bad',
        version: 16,
        allowBrokenReferences: true,
        prepare: (db) {
          note(db, id: 1, guid: 'orphan', location: 999, body: 'keep orphan');
        },
      );
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      final first = keep(await mergeArchives([bad, clean], (_) {}));
      final zip = ZipDecoder().decodeBytes(
        File(first.archivePath).readAsBytesSync(),
      );
      final legacyReport = report(first)
        ..['formatVersion'] = 1
        ..remove('warningEvents')
        ..remove('conflictVersions');
      for (final record
          in (legacyReport['unresolvedRecords'] as List).cast<Map>()) {
        record.remove('recordId');
        record.remove('sourceFingerprint');
        record.remove('warningCode');
      }
      final bytes = utf8.encode(jsonEncode(legacyReport));
      zip.addFile(ArchiveFile('recovery-report.json', bytes.length, bytes));
      final legacy = File('${scratch.path}/legacy-result.jwlibrary')
        ..writeAsBytesSync(ZipEncoder().encode(zip));
      Future<MergeResult> branch(String name) async => keep(
        await mergeArchives([
          legacy.path,
          writeBackup(scratch, name, version: 16, prepare: (_) {}),
        ], (_) {}),
      );
      final left = await branch('left'), right = await branch('right');
      final result = keep(
        await mergeArchives([left.archivePath, right.archivePath], (_) {}),
      );
      expect(result.warnings.single.count, 1);
      expect(report(result)['unresolvedRecords'], hasLength(1));
    },
  );

  test(
    'non-record recovered-media events are not doubled across branches',
    () async {
      const bytes = [1, 2, 3, 4];
      // _playlist uses the same SHA for the missing file and its replacement.
      final missing = writeBackup(
        scratch,
        'missing',
        version: 16,
        prepare: (db) {
          playlist(
            db,
            document: 101,
            name: 'Clip',
            bytes: bytes,
            thumbnail: 'clip.mp4',
            verse: 1,
          );
        },
      );
      final donor = writeBackup(
        scratch,
        'donor',
        version: 16,
        media: {'other-name.mp4': bytes},
        prepare: (_) {},
      );
      final first = keep(await mergeArchives([missing, donor], (_) {}));
      expect(first.warnings.single.code, 'recoveredMedia');
      Future<MergeResult> branch(String name) async => keep(
        await mergeArchives([
          first.archivePath,
          writeBackup(scratch, name, version: 16, prepare: (_) {}),
        ], (_) {}),
      );
      final left = await branch('left'), right = await branch('right');
      final result = keep(
        await mergeArchives([left.archivePath, right.archivePath], (_) {}),
      );
      expect(result.warnings.single.code, 'recoveredMedia');
      expect(result.warnings.single.count, 1);
    },
  );
  test(
    'independent legacy sources with the same basename keep separate problems',
    () async {
      Future<MergeResult> oldResult(String device, String date) async {
        final folder = Directory('${scratch.path}/$device')..createSync();
        final bad = writeBackup(
          folder,
          'backup',
          version: 16,
          date: date,
          allowBrokenReferences: true,
          prepare: (db) {
            note(
              db,
              id: 1,
              guid: 'same-orphan',
              location: 999,
              body: 'same text',
            );
          },
        );
        final clean = writeBackup(
          folder,
          'clean',
          version: 16,
          prepare: (_) {},
        );
        final first = keep(await mergeArchives([bad, clean], (_) {}));
        // Format 1 identified a row's origin only through the embedded copy
        // of its source listed in sourceArchives.
        final badHash = sha256.convert(File(bad).readAsBytesSync()).toString();
        final oldReport = report(first)
          ..['formatVersion'] = 1
          ..['sourceArchives'] = [
            {
              'path': 'recovery-sources/$badHash.jwlibrary',
              'fileName': 'backup.jwlibrary',
              'sha256': badHash,
            },
          ]
          ..remove('warningEvents')
          ..remove('conflictVersions');
        for (final entry
            in (oldReport['unresolvedRecords'] as List).cast<Map>()) {
          entry.remove('sourceFingerprint');
          entry.remove('recordId');
          entry.remove('warningCode');
        }
        final zip = ZipDecoder().decodeBytes(
          File(first.archivePath).readAsBytesSync(),
        );
        final bytes = utf8.encode(jsonEncode(oldReport));
        zip.addFile(ArchiveFile('recovery-report.json', bytes.length, bytes));
        final path = File('${folder.path}/old-result.jwlibrary')
          ..writeAsBytesSync(ZipEncoder().encode(zip));
        return keep(await mergeArchives([path.path, clean], (_) {}));
      }

      final left = await oldResult('device-left', fixtureEarlier);
      final right = await oldResult('device-right', fixtureLater);
      final result = keep(
        await mergeArchives([left.archivePath, right.archivePath], (_) {}),
      );
      expect(result.warnings.single.count, 2);
      final records = (report(result)['unresolvedRecords'] as List).cast<Map>();
      expect(records, hasLength(2));
      expect(records.map((r) => r['sourceFingerprint']).toSet(), hasLength(2));
      // A single old report may contain both same-named origins without any
      // per-row fingerprint. Both ambiguous occurrences must be kept.
      final ambiguous = report(result)
        ..['formatVersion'] = 1
        ..remove('warningEvents')
        ..remove('conflictVersions');
      for (final entry
          in (ambiguous['unresolvedRecords'] as List).cast<Map>()) {
        entry.remove('sourceFingerprint');
        entry.remove('recordId');
        entry.remove('warningCode');
      }
      final zip = ZipDecoder().decodeBytes(
        File(result.archivePath).readAsBytesSync(),
      );
      final bytes = utf8.encode(jsonEncode(ambiguous));
      zip.addFile(ArchiveFile('recovery-report.json', bytes.length, bytes));
      final old = File('${scratch.path}/ambiguous-old.jwlibrary')
        ..writeAsBytesSync(ZipEncoder().encode(zip));
      final clean = writeBackup(
        scratch,
        'extra-clean',
        version: 16,
        prepare: (_) {},
      );
      final recovered = keep(await mergeArchives([old.path, clean], (_) {}));
      expect(recovered.warnings.single.count, 2);
      final retained = (report(recovered)['unresolvedRecords'] as List)
          .cast<Map>();
      expect(retained, hasLength(2));
      expect(retained.map((r) => r['recordId']).toSet(), hasLength(2));
    },
  );
}
