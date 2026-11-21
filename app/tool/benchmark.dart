import 'dart:convert';
import 'dart:io';

import 'package:kovetz/merge.dart';

/// Developer benchmark: merges real backups from a local folder that is never
/// committed. Usage: `dart run tool/benchmark.dart <folder> [all|pair] [label]`
/// `pair` uses the oldest and the newest backup; `all` uses every backup.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: benchmark.dart <folder> [all|pair] [label]');
    exitCode = 64;
    return;
  }
  final dir = Directory(args[0]);
  final mode = args.length > 1 ? args[1] : 'pair';
  final label = args.length > 2 ? args[2] : 'run';
  final all =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jwlibrary'))
          .map((f) => f.path)
          .toList()
        ..sort();
  final files = mode == 'all' ? all : [all.first, all.last];
  final watch = Stopwatch()..start();
  final stages = <String, double>{};
  final result = await mergeArchives(files, (stage) {
    stages[stage] = watch.elapsedMilliseconds / 1000;
  });
  watch.stop();
  final row = {
    'label': label,
    'scenario': mode,
    'inputs': files.length,
    'seconds': watch.elapsedMilliseconds / 1000,
    'peakRssMiB': (ProcessInfo.maxRss / 1024 / 1024).round(),
    'archiveMiB': (File(result.archivePath).lengthSync() / 1024 / 1024)
        .toStringAsFixed(2),
    'stageStarts': stages,
    'counts': result.counts,
  };
  stdout.writeln(jsonEncode(row));
  final keep = Platform.environment['BENCH_KEEP'];
  if (keep != null) {
    File(result.archivePath).copySync(keep);
  }
  File(result.archivePath).parent.deleteSync(recursive: true);
}
