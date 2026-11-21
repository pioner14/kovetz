import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:backup_merge/archive_limits.dart';
import 'package:backup_merge/merge.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/merge_fixtures.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('security-');
  });
  tearDown(() => scratch.delete(recursive: true));

  for (final entryName in [
    '../outside.txt',
    '/absolute.txt',
    r'C:\outside.txt',
    r'folder\..\outside.txt',
  ]) {
    test(
      'rejects unsafe ZIP entry $entryName without changing inputs',
      () async {
        final unsafe = writeBackup(
          scratch,
          'unsafe',
          version: 16,
          prepare: (_) {},
        );
        final clean = writeBackup(
          scratch,
          'clean',
          version: 16,
          prepare: (_) {},
        );
        final archive = ZipDecoder().decodeBytes(
          File(unsafe).readAsBytesSync(),
        );
        archive.addFile(ArchiveFile(entryName, 3, [1, 2, 3]));
        File(unsafe).writeAsBytesSync(ZipEncoder().encode(archive));
        final before = sha256.convert(File(unsafe).readAsBytesSync());
        await expectLater(
          mergeArchives([unsafe, clean], (_) {}),
          throwsA(
            isA<MergeFailure>().having((e) => e.code, 'code', 'invalidArchive'),
          ),
        );
        expect(sha256.convert(File(unsafe).readAsBytesSync()), before);
        expect(File('${scratch.path}/outside.txt').existsSync(), isFalse);
      },
    );
  }

  test('source UPDATE trigger cannot erase a valid note during link recovery', () async {
    final source = writeBackup(
      scratch,
      'untrusted-update',
      version: 16,
      allowBrokenReferences: true,
      prepare: (db) {
        addDocument(db, 1, 101);
        note(
          db,
          id: 1,
          guid: 'orphan',
          location: 999,
          body: 'Keep detached text',
        );
        note(db, id: 2, guid: 'victim', location: 1, body: 'Keep valid text');
        db.execute(
          "CREATE TRIGGER unexpected_update AFTER UPDATE ON Note BEGIN DELETE FROM Note WHERE Guid = 'victim'; END",
        );
      },
    );
    final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
    final before = sha256.convert(File(source).readAsBytesSync());
    final result = await mergeArchives([source, clean], (_) {});
    final output = readOutput(scratch, result.archivePath, version: 16);
    expect(sha256.convert(File(source).readAsBytesSync()), before);
    expect(
      output.db
          .select('SELECT Guid, Content FROM Note ORDER BY Guid')
          .map((r) => r.values.toList())
          .toList(),
      [
        ['orphan', 'Keep detached text'],
        ['victim', 'Keep valid text'],
      ],
      reason:
          'Input triggers must never control recovery of other source records.',
    );
  });

  test(
    'source DELETE trigger cannot erase a note when media is missing',
    () async {
      final source = writeBackup(
        scratch,
        'untrusted-delete',
        version: 16,
        prepare: (db) {
          addDocument(db, 1, 101);
          note(db, id: 1, guid: 'victim', location: 1, body: 'Keep valid text');
          db.execute('INSERT INTO IndependentMedia VALUES(1, ?, ?, ?, ?)', [
            'absent.jpg',
            'absent.jpg',
            'image/jpeg',
            sha256.convert([1, 2, 3]).toString(),
          ]);
          db.execute(
            "CREATE TRIGGER unexpected_delete AFTER DELETE ON IndependentMedia BEGIN DELETE FROM Note WHERE Guid = 'victim'; END",
          );
        },
      );
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      final before = sha256.convert(File(source).readAsBytesSync());
      final result = await mergeArchives([source, clean], (_) {});
      final output = readOutput(scratch, result.archivePath, version: 16);
      expect(sha256.convert(File(source).readAsBytesSync()), before);
      expect(
        output.db.select('SELECT Content FROM Note').map((r) => r['Content']),
        ['Keep valid text'],
        reason: 'Missing media must not affect unrelated notes.',
      );
    },
  );

  group('archive budget', () {
    String withEntries(String name, Map<String, List<int>> extra) {
      final path = writeBackup(scratch, name, version: 16, prepare: (_) {});
      final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
      for (final entry in extra.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      return path;
    }

    int declaredBytes(String path) => ZipDecoder()
        .decodeBytes(File(path).readAsBytesSync())
        .files
        .fold(0, (sum, file) => sum + file.size);

    Matcher failsWith(String code) =>
        throwsA(isA<MergeFailure>().having((e) => e.code, 'code', code));

    test('rejects an archive with too many entries', () async {
      final crowded = withEntries('crowded', {
        'a.bin': [1],
        'b.bin': [2],
      });
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      await expectLater(
        mergeArchives(
          [crowded, clean],
          (_) {},
          options: const MergeOptions(limits: ArchiveLimits(maxEntries: 3)),
        ),
        failsWith('tooLarge'),
      );
    });

    test('rejects an entry or archive above the declared budget', () async {
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      final base = declaredBytes(clean);
      final large = withEntries('large', {'big.bin': List.filled(4096, 7)});
      await expectLater(
        mergeArchives(
          [large, clean],
          (_) {},
          options: const MergeOptions(
            limits: ArchiveLimits(maxEntryBytes: 4095),
          ),
        ),
        failsWith('tooLarge'),
      );
      await expectLater(
        mergeArchives(
          [large, clean],
          (_) {},
          options: MergeOptions(limits: ArchiveLimits(maxTotalBytes: base)),
        ),
        failsWith('tooLarge'),
      );
    });

    test('stops extracting an entry that exceeds its declared size', () async {
      final bomb = withEntries('bomb', {
        'filler.bin': List.filled(1024 * 1024, 0),
      });
      File(bomb).writeAsBytesSync(
        _understate(File(bomb).readAsBytesSync(), 'filler.bin', 16),
      );
      final understated = ZipDecoder()
          .decodeBytes(File(bomb).readAsBytesSync())
          .findFile('filler.bin')!;
      final sink = OutputMemoryStream();
      expect(
        () => understated.writeContent(LimitedOutputStream(sink, 16)),
        // archive 4.7 also enforces the declared size; either guard may stop it.
        throwsA(anyOf(isA<ArchiveLimitExceeded>(), isA<FormatException>())),
      );
      expect(
        sink.length,
        lessThan(256 * 1024),
        reason: 'Inflation must stop near the limit, not after 1 MiB.',
      );
      final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
      await expectLater(
        mergeArchives([bomb, clean], (_) {}),
        failsWith('invalidArchive'),
      );
    });

    for (final (label, content) in [
      ('malformed JSON', '{'),
      (
        'unexpected field types',
        '{"formatVersion":2,"warningEvents":[{"code":5}]}',
      ),
    ]) {
      test('reports a previous recovery report with $label', () async {
        final previous = withEntries('previous', {
          'recovery-report.json': utf8.encode(content),
        });
        final clean = writeBackup(
          scratch,
          'clean',
          version: 16,
          prepare: (_) {},
        );
        await expectLater(
          mergeArchives([previous, clean], (_) {}),
          failsWith('invalidReport'),
        );
      });
    }
  });

  test('damaged inputs are reported as damaged, missing ones as I/O', () async {
    final clean = writeBackup(scratch, 'clean', version: 16, prepare: (_) {});
    final valid = File(
      writeBackup(scratch, 'valid', version: 16, prepare: (_) {}),
    ).readAsBytesSync();
    final damaged = {
      'empty': <int>[],
      'random': List.generate(4096, (i) => (i * 7919) % 251),
      'truncated': valid.sublist(0, valid.length ~/ 2),
      'no-manifest': ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('userData.db', 3, [1, 2, 3])),
      ),
      'bad-manifest': ZipEncoder().encode(
        Archive()..addFile(
          ArchiveFile('manifest.json', 11, utf8.encode('{"name": 5}')),
        ),
      ),
    };
    for (final MapEntry(key: label, value: bytes) in damaged.entries) {
      final path = '${scratch.path}/$label.jwlibrary';
      File(path).writeAsBytesSync(bytes);
      await expectLater(
        mergeArchives([path, clean], (_) {}),
        throwsA(
          isA<MergeFailure>().having((e) => e.code, 'code', 'invalidArchive'),
        ),
        reason: label,
      );
    }
    await expectLater(
      mergeArchives(['${scratch.path}/absent.jwlibrary', clean], (_) {}),
      throwsA(isA<MergeFailure>().having((e) => e.code, 'code', 'io')),
    );
  });

  test('a cancelled merge stops and reports cancellation', () async {
    final left = writeBackup(scratch, 'left', version: 16, prepare: (_) {});
    final right = writeBackup(scratch, 'right', version: 16, prepare: (_) {});
    final stages = <String>[];
    final watch = Stopwatch()..start();
    await expectLater(
      mergeArchives([left, right], stages.add, cancel: Future.value()),
      throwsA(isA<MergeFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(stages, isNot(contains('packing')));
  });
}

/// Rewrites the declared uncompressed size of [name] in both ZIP headers,
/// leaving the compressed data unchanged.
Uint8List _understate(Uint8List zip, String name, int size) {
  final data = ByteData.sublistView(zip);
  final encoded = utf8.encode(name);
  bool nameAt(int offset) {
    if (offset + encoded.length > zip.length) return false;
    for (var i = 0; i < encoded.length; i++) {
      if (zip[offset + i] != encoded[i]) return false;
    }
    return true;
  }

  for (var i = 0; i + 4 <= zip.length; i++) {
    final signature = data.getUint32(i, Endian.little);
    if (signature == 0x04034b50 && nameAt(i + 30)) {
      data.setUint32(i + 22, size, Endian.little);
    } else if (signature == 0x02014b50 && nameAt(i + 46)) {
      data.setUint32(i + 24, size, Endian.little);
    }
  }
  return zip;
}
