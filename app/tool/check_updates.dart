import 'dart:io';

import 'package:backup_merge/updates.dart';

/// Developer tool: asks GitHub for the newest release, like the app does.
Future<void> main() async {
  final result = await UpdateChecker().check();
  final latest = result.latest;
  stdout.writeln(
    latest == null
        ? 'no app release published'
        : 'latest ${latest.version} (${latest.assets.keys.join(', ')}), '
              'update available: ${result.available}',
  );
}
