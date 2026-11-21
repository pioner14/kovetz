// Provenance of retained records, differing versions and warnings.
part of '../../merge.dart';

class _RecoveryReport {
  _RecoveryReport(String path) : store = sqlite3.open(path) {
    store.execute('PRAGMA cache_size = -2048');
    store.execute('PRAGMA synchronous = OFF');
    store.execute('PRAGMA journal_mode = OFF');
    store.execute(
      'CREATE TABLE Records (id INTEGER PRIMARY KEY, recordId TEXT NOT NULL UNIQUE, data TEXT NOT NULL)',
    );
    store.execute(
      'CREATE TABLE WarningEvents (eventId TEXT PRIMARY KEY, code TEXT NOT NULL, fileName TEXT, count INTEGER NOT NULL CHECK(count > 0))',
    );
    store.execute(
      'CREATE TABLE Versions (id INTEGER PRIMARY KEY, versionId TEXT NOT NULL UNIQUE, entity TEXT NOT NULL, data TEXT NOT NULL)',
    );
    store.execute('CREATE INDEX IX_Versions_Entity ON Versions(entity)');
    store.execute('CREATE TABLE Conflicts (entity TEXT PRIMARY KEY)');
    store.execute(
      'CREATE TABLE Selections (entity TEXT PRIMARY KEY, versionId TEXT NOT NULL)',
    );
  }
  final Database store;
  late final _statements = StatementCache(store);

  /// Runs per-record SQL with a reused prepared statement.
  void run(String sql, List<Object?> parameters) =>
      _statements.execute(sql, parameters);
  late String primaryName;
  late List<String> sourceNames;
  late MergeOptions options;
  final archives = <Map<String, Object?>>[];
  void close() {
    _statements.dispose();
    store.close();
  }

  bool get hasDetails =>
      warnings.isNotEmpty ||
      store.select('SELECT 1 FROM Conflicts LIMIT 1').isNotEmpty;

  String addRecord(Map<String, Object?> record) {
    final id = _reportId([
      record['sourceFingerprint'] ??
          record['legacyIdentity'] ??
          record['fileName'],
      record['table'],
      record['reason'],
      record['record'],
    ]);
    run('INSERT OR IGNORE INTO Records(recordId, data) VALUES(?, ?)', [
      id,
      jsonEncode({...record, 'recordId': id}),
    ]);
    return id;
  }

  Iterable<Map<String, Object?>> get records sync* {
    for (final row in streamRows(
      store,
      'SELECT data FROM Records ORDER BY id',
    )) {
      yield Map<String, Object?>.from(jsonDecode(row['data'] as String) as Map);
    }
  }

  List<MergeWarning> get warnings => [
    for (final row in store.select(
      'SELECT code, fileName, SUM(count) AS count FROM WarningEvents GROUP BY code, fileName ORDER BY MIN(rowid)',
    ))
      MergeWarning(
        row['code'] as String,
        fileName: row['fileName'] as String?,
        count: row['count'] as int,
      ),
  ];

  void warn(
    String code,
    String? fileName, {
    required String eventId,
    int count = 1,
  }) {
    if (count < 1) return;
    run(
      'INSERT OR IGNORE INTO WarningEvents(eventId,code,fileName,count) VALUES(?,?,?,?)',
      [eventId, code, fileName, count],
    );
  }

  void retain(
    _Source source,
    String table,
    String reason,
    Map<String, Object?> record, {
    String code = 'unresolvedLinks',
    List<String>? missingReferences,
  }) {
    final id = addRecord({
      'fileName': source.name,
      'sourceFingerprint': source.fingerprint,
      'table': table,
      'reason': reason,
      'warningCode': code,
      'record': record,
      'context': _context(source, record),
      'missingReferences': ?missingReferences,
    });
    warn(code, source.name, eventId: 'record:$id');
  }

  String stageVersion(
    _Source source,
    String table,
    String entity,
    Map<String, Object?> record,
  ) {
    return _addVersion({
      'entity': entity,
      'table': table,
      'record': record,
      'fileName': source.name,
      'sourceFingerprint': source.fingerprint,
      'backupDate': source.modified.toIso8601String(),
      'context': _context(source, record),
    });
  }

  String _addVersion(Map<String, Object?> entry) {
    final id = _reportId([
      entry['sourceFingerprint'] ?? entry['fileName'],
      entry['table'],
      entry['entity'],
      entry['record'],
    ]);
    final data = Map<String, Object?>.of(entry)..remove('selected');
    data['versionId'] = id;
    run('INSERT OR IGNORE INTO Versions(versionId,entity,data) VALUES(?,?,?)', [
      id,
      entry['entity'],
      jsonEncode(data),
    ]);
    return id;
  }

  void markConflict(String entity) =>
      run('INSERT OR IGNORE INTO Conflicts VALUES(?)', [entity]);
  void selectVersion(String entity, String versionId) =>
      run('INSERT OR REPLACE INTO Selections VALUES(?,?)', [entity, versionId]);

  Iterable<Map<String, Object?>> get conflictVersions sync* {
    for (final row in streamRows(
      store,
      'SELECT v.data, v.versionId = s.versionId AS selected FROM Versions v JOIN Conflicts c ON c.entity = v.entity LEFT JOIN Selections s ON s.entity = v.entity ORDER BY v.entity, v.id',
    )) {
      yield {
        ...Map<String, Object?>.from(jsonDecode(row['data'] as String) as Map),
        'selected': row['selected'] == 1,
      };
    }
  }

  void inherit(_Source source) {
    final prior = source.previousReport;
    if (prior == null) return;
    // Legacy reports lack row-level provenance. Recover it from the embedded
    // source archive when its name identifies one distinct fingerprint.
    final legacyOrigins = <String?, Set<String>>{};
    for (final raw in (prior['sourceArchives'] as List? ?? [])) {
      final archive = raw as Map;
      final hash = archive['sha256'];
      if (hash is String) {
        (legacyOrigins[archive['fileName'] as String?] ??= {}).add(hash);
      }
    }
    final legacyOccurrences = <String, int>{};
    final represented = <(String, String?), int>{};
    for (final raw in (prior['unresolvedRecords'] as List? ?? [])) {
      final entry = Map<String, Object?>.from(raw as Map);
      final origins = legacyOrigins[entry['fileName']];
      if (entry['sourceFingerprint'] == null &&
          entry['legacyIdentity'] == null) {
        if (origins?.length == 1) {
          entry['sourceFingerprint'] = origins!.single;
        } else {
          // Old reports cannot identify which same-named archive owned a row.
          // Preserve ambiguous occurrences instead of silently collapsing them.
          final candidates = origins?.toList() ?? [source.fingerprint];
          candidates.sort();
          final base = _reportId([
            candidates,
            entry['fileName'],
            entry['table'],
            entry['reason'],
            entry['record'],
          ]);
          final occurrence = legacyOccurrences.update(
            base,
            (n) => n + 1,
            ifAbsent: () => 0,
          );
          entry['legacyIdentity'] = '$base:$occurrence';
        }
      }
      final code =
          entry['warningCode'] as String? ??
          (entry['reason'] == 'missingMedia'
              ? 'missingMedia'
              : 'unresolvedLinks');
      final fileName = entry['fileName'] as String?;
      final id = addRecord(entry);
      warn(code, fileName, eventId: 'record:$id');
      represented.update((code, fileName), (n) => n + 1, ifAbsent: () => 1);
    }
    final events = prior['warningEvents'];
    if (events is List) {
      for (final raw in events) {
        final event = raw as Map;
        warn(
          event['code'] as String,
          event['fileName'] as String?,
          eventId: event['eventId'] as String,
          count: event['count'] as int,
        );
      }
    } else {
      // Reports from 0.3.0 have aggregate counters only. Reconstruct record
      // events, and retain non-record counters once for a common history.
      for (final raw in (prior['warnings'] as List? ?? [])) {
        final warning = raw as Map;
        final code = warning['code'] as String;
        final fileName = warning['fileName'] as String?;
        final remainder =
            (warning['count'] as int) - (represented[(code, fileName)] ?? 0);
        warn(
          code,
          fileName,
          count: remainder,
          eventId:
              'legacy:${_reportId([
                code,
                fileName,
                (legacyOrigins[fileName]?.toList() ?? [source.fingerprint])..sort(),
                remainder,
              ])}',
        );
      }
    }
    for (final raw in (prior['conflictVersions'] as List? ?? [])) {
      final entry = Map<String, Object?>.from(raw as Map);
      _addVersion(entry);
      markConflict(entry['entity'] as String);
    }
    for (final archive in (prior['sourceArchives'] as List? ?? [])) {
      if (archives.every((entry) => entry['path'] != archive['path'])) {
        archives.add(Map<String, Object?>.from(archive as Map));
      }
    }
  }

  Map<String, Object?> _context(_Source source, Map<String, Object?> record) {
    final context = <String, Object?>{};
    for (final key in ['PublicationLocationId', 'LocationId']) {
      final id = record[key];
      if (id == null) continue;
      final location = source.locations[id];
      if (location != null) context[key] = Map<String, Object?>.of(location);
    }
    return context;
  }

  void writeJson(File file) {
    final sink = file.openSync(mode: FileMode.write);
    void write(String value) => sink.writeStringSync(value);
    try {
      write(
        '{"formatVersion":2,"outputSchemaVersion":$currentSchemaVersion,"warnings":',
      );
      write(jsonEncode(warnings.map((w) => w.toJson()).toList()));
      write(',"unresolvedRecords":[');
      var first = true;
      for (final record in records) {
        if (!first) write(',');
        first = false;
        write(jsonEncode(record));
      }
      write('],"conflictVersions":[');
      first = true;
      for (final version in conflictVersions) {
        if (!first) write(',');
        first = false;
        write(jsonEncode(version));
      }
      write('],"warningEvents":[');
      first = true;
      for (final event in streamRows(
        store,
        'SELECT eventId,code,fileName,count FROM WarningEvents ORDER BY rowid',
      )) {
        if (!first) write(',');
        first = false;
        write(jsonEncode(event));
      }
      write('],"sourceArchives":${jsonEncode(archives)}}');
    } finally {
      sink.closeSync();
    }
  }
}
