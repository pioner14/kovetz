import 'dart:io';

import 'package:kovetz/export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late File archive;
  late File report;
  late File archiveOut;
  late File reportOut;
  setUp(() async {
    final root = Directory('../.work/test-runs')..createSync(recursive: true);
    scratch = await root.createTemp('export-');
    archive = await File('${scratch.path}/source.jwlibrary')
        .writeAsString('new archive');
    report = await File('${scratch.path}/source.report.txt')
        .writeAsString('Отчёт: заметки сохранены.');
    archiveOut = File('${scratch.path}/saved.jwlibrary');
    reportOut = File('${scratch.path}/saved.report.txt');
  });
  tearDown(() => scratch.delete(recursive: true));

  Future<void> save({String? reportSource}) => saveBackupPair(
    archiveSource: archive.path,
    reportSource: reportSource ?? report.path,
    archiveDestination: archiveOut.path,
    reportDestination: reportOut.path,
  );

  Future<void> expectNoStaging() async => expect(
    await scratch
        .list()
        .where(
          (entity) => entity is Directory && entity.path.contains('.kovetz-'),
        )
        .toList(),
    isEmpty,
  );

  test(
    'saves the archive and adjacent UTF-8 report without changing sources',
    () async {
      await save();
      expect(await archiveOut.readAsBytes(), await archive.readAsBytes());
      expect(await reportOut.readAsString(), 'Отчёт: заметки сохранены.');
      expect(await archive.readAsString(), 'new archive');
      expect(await report.readAsString(), 'Отчёт: заметки сохранены.');
      await expectNoStaging();
    },
  );

  test('replaces an existing complete pair', () async {
    await archiveOut.writeAsString('old archive');
    await reportOut.writeAsString('old report');
    await save();
    expect(await archiveOut.readAsString(), 'new archive');
    expect(await reportOut.readAsString(), await report.readAsString());
    await expectNoStaging();
  });

  test(
    'missing source report leaves both existing destinations intact',
    () async {
      await archiveOut.writeAsString('old archive');
      await reportOut.writeAsString('old report');
      await expectLater(
        save(reportSource: '${scratch.path}/missing.txt'),
        throwsA(isA<ExportFailure>()),
      );
      expect(await archiveOut.readAsString(), 'old archive');
      expect(await reportOut.readAsString(), 'old report');
      await expectNoStaging();
    },
  );

  test('failure writing the second file restores the old archive', () async {
    await archiveOut.writeAsString('old archive');
    final blocker = await Directory(reportOut.path).create();
    final sentinel = await File('${blocker.path}/keep.txt')
        .writeAsString('keep existing data');
    await expectLater(save(), throwsA(isA<ExportFailure>()));
    expect(await archiveOut.readAsString(), 'old archive');
    expect(await sentinel.readAsString(), 'keep existing data');
    await expectNoStaging();
  });

  test(
    'failure writing the second file removes a newly installed archive',
    () async {
      await Directory(reportOut.path).create();
      await expectLater(save(), throwsA(isA<ExportFailure>()));
      expect(await archiveOut.exists(), isFalse);
      expect(await Directory(reportOut.path).exists(), isTrue);
      await expectNoStaging();
    },
  );

  test('export can be retried after rollback', () async {
    final blocker = await Directory(reportOut.path).create();
    await expectLater(save(), throwsA(isA<ExportFailure>()));
    await blocker.delete();
    await save();
    expect(await archiveOut.readAsString(), 'new archive');
    expect(await reportOut.readAsString(), await report.readAsString());
    await expectNoStaging();
  });

  test('detects a destination that would replace a source backup', () async {
    final other = File('${scratch.path}/other.jwlibrary');
    expect(
      await wouldReplaceSource(archive.path, true, [archive.path]),
      isTrue,
    );
    expect(
      await wouldReplaceSource('${scratch.path}/./source.jwlibrary', true, [
        archive.path,
      ]),
      isTrue,
    );
    expect(
      await wouldReplaceSource(other.path, false, [archive.path]),
      isFalse,
    );
    // Creating symbolic links on Windows needs extra privileges.
    if (!Platform.isWindows) {
      // Saving over a symbolic link to a source backup is refused and rolled
      // back; the backup it points to keeps its contents.
      final source = await File('${scratch.path}/kept.jwlibrary')
          .writeAsString('original backup');
      final link = await Link('${scratch.path}/alias.jwlibrary')
          .create(source.path);
      await expectLater(
        saveBackupPair(
          archiveSource: archive.path,
          reportSource: report.path,
          archiveDestination: link.path,
          reportDestination: '${scratch.path}/alias.report.txt',
        ),
        throwsA(isA<ExportFailure>()),
      );
      expect(await source.readAsString(), 'original backup');
      expect(await link.target(), source.path);
    }
  });
}
