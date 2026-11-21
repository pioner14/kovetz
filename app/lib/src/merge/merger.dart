// Merging normalized sources into the canonical output database.
part of '../../merge.dart';

class _Media {
  _Media(this._digests);

  /// SHA-256 by extracted file path, shared with media recovery so each file
  /// is hashed once.
  final Map<String, String> _digests;
  final files = <String, File>{};
  final _byOutputPath = <String, String>{
    'manifest.json': '',
    'recovery-report.json': '',
    'userdata.db': '',
    'user_data.db': '',
    'userdata.db-wal': '',
    'userdata.db-shm': '',
    'user_data.db-wal': '',
    'user_data.db-shm': '',
  };

  Future<Map<String, (String, String)>> add(_Source source) async {
    final paths = <String, (String, String)>{};
    for (final entry in source.media.entries) {
      final hash = _digests[entry.value.path] ??= await _digest(entry.value);
      var name = entry.key;
      final present = _byOutputPath[name.toLowerCase()];
      if (present != null && present != hash) {
        final extension = p.posix.extension(name);
        name = 'merged-$hash$extension';
        var suffix = 0;
        while (_byOutputPath.containsKey(name.toLowerCase()) &&
            _byOutputPath[name.toLowerCase()] != hash) {
          name = 'merged-$hash-${++suffix}$extension';
        }
      }
      final key = name.toLowerCase();
      if (_byOutputPath[key] == hash && !files.containsKey(name)) {
        name = files.keys.firstWhere((path) => path.toLowerCase() == key);
      }
      _byOutputPath[key] = hash;
      files.putIfAbsent(name, () => entry.value);
      paths[entry.key] = (name, hash);
    }
    return paths;
  }
}

/// Per-source state while one backup is merged: old-to-new ID maps, the
/// selected highlight versions and the output paths of its media files.
class _SourceScope {
  _SourceScope(this.source, this.media);

  final _Source source;
  final Map<String, (String, String)> media;
  final ids = <String, Map<int, int>>{};
  final markVersions = <int, int>{};
  final selectedMarks = <int>{};
  final playlistOccurrences = <String, int>{};

  Iterable<Map<String, Object?>> rows(String table, [String order = '']) =>
      streamRows(source.db, 'SELECT * FROM "$table" $order');

  void remember(String table, int old, int id) {
    (ids[table] ??= {})[old] = id;
  }

  int ref(String table, Object? id) {
    return ids[table]?[id] ??
        (throw MergeFailure(MergeErrorCode.invalidDatabase, source.name));
  }

  void remap(Map<String, Object?> row, String table, [String? column]) {
    final key = column ?? '${table}Id';
    if (row[key] != null) row[key] = ref(table, row[key]);
  }

  String? mediaPath(Object? path) {
    if (path == null) return null;
    final entry = media[path];
    if (entry == null) {
      throw MergeFailure(MergeErrorCode.missingMedia, source.name);
    }
    return entry.$1;
  }
}

class _Merger {
  _Merger(this.db, this.report, this.options) {
    report.store.execute(
      'CREATE TABLE Bookmarks (id INTEGER PRIMARY KEY, publication INTEGER, signature TEXT, source INTEGER, data TEXT, original TEXT, displaced INTEGER DEFAULT 0, UNIQUE(publication,signature))',
    );
  }
  final MergeOptions options;
  final _sources = <_Source>[];

  final Database db;
  final _RecoveryReport report;
  int bookmarkConflicts = 0;
  int skippedBookmarks = 0;
  final _noteConflicts = <String>{};
  final _fieldConflicts = <String>{};

  int get noteConflicts => _noteConflicts.length;
  int get fieldConflicts => _fieldConflicts.length;

  final _locations = <String, int>{};
  final _tags = <String, int>{};
  final _notes = <String, int>{};
  final _marks = <String, (int, int, String)>{};
  final _playlistSignatures = <String, String>{};
  final _playlistTargets = <String, int>{};
  final _playlistUsedTargets = <int, Set<int>>{};
  final _ranges = <String>{};
  final _fields = <String, DateTime>{};
  final _mediaIds = <String, int>{};
  final _accuracy = <String, int>{};
  final _items = <String, int>{};
  final _tagLinks = <String>{};
  final _tagPositions = <int, int>{};

  Map<String, int> get counts => {
    for (final table in [
      'Note',
      'UserMark',
      'Bookmark',
      'Tag',
      'InputField',
      'PlaylistItem',
      'IndependentMedia',
    ])
      table:
          db.select('SELECT count(*) AS value FROM "$table"').single['value']
              as int,
    'Favorite':
        db
                .select(
                  'SELECT count(*) AS value FROM TagMap JOIN Tag USING(TagId) WHERE Tag.Type = 0',
                )
                .single['value']
            as int,
    'Playlist':
        db
                .select('SELECT count(*) AS value FROM Tag WHERE Type = 2')
                .single['value']
            as int,
  };

  void readAccuracy() {
    for (final row in db.select('SELECT * FROM PlaylistItemAccuracy')) {
      _accuracy[row['Description'] as String] =
          row['PlaylistItemAccuracyId'] as int;
    }
  }

  void add(_Source source, Map<String, (String, String)> media) {
    final scope = _SourceScope(source, media);
    _addLocations(scope);
    _addTags(scope);
    _addUserMarks(scope);
    _addNotes(scope);
    _addBlockRanges(scope);
    _addInputFields(scope);
    _addBookmarks(scope);
    _addIndependentMedia(scope);
    _addAccuracy(scope);
    final itemSignatures = _addModernPlaylists(
      source,
      scope.ids,
      scope.mediaPath,
    );
    _comparePlaylists(scope, itemSignatures);
    _addTagMaps(scope, itemSignatures);
  }

  /// Locations are matched by publication identity and its aliases.
  void _addLocations(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remember = scope.remember;
    for (final row in rows('Location', 'ORDER BY LocationId')) {
      final original = Map<String, Object?>.of(row);
      final old = row.remove('LocationId') as int;
      final type = row['Type'];
      final document = row['DocumentId'];
      final book = row['BookNumber'];
      final chapter = row['ChapterNumber'];
      final publication = row['KeySymbol'];
      final issue = row['IssueTagNumber'];
      final lang = row['MepsLanguage'];
      final track = row['Track'];
      final specialty = row['Specialty'] ?? '';
      final edition = row['Edition'] ?? '';
      final key = _key([
        type,
        document,
        book,
        chapter,
        publication,
        issue,
        lang,
        track,
        specialty,
        edition,
      ]);
      final aliases = [
        key,
        if (book != null &&
            chapter != null &&
            publication != null &&
            lang != null)
          _key(['chapter', type, book, chapter, publication, lang]),
        if (document != null &&
            track != null &&
            publication != null &&
            lang != null)
          _key([
            'track',
            type,
            document,
            track,
            publication,
            issue,
            lang,
            specialty,
            edition,
          ]),
      ];
      final matches = aliases
          .map((alias) => _locations[alias])
          .nonNulls
          .toSet();
      final int id;
      if (matches.length > 1) {
        // The location resembles two different merged places. Keep the
        // merge going: prefer the exact identity, otherwise the earliest
        // place, and list the record for review instead of failing outright.
        id = _locations[key] ?? (matches.toList()..sort()).first;
        report.retain(source, 'Location', 'ambiguousLocation', original);
      } else {
        id = matches.firstOrNull ?? _insert('Location', row);
      }
      for (final alias in aliases) {
        _locations.putIfAbsent(alias, () => id);
      }
      remember('Location', old, id);
    }
  }

  /// Favourites share one tag; other tags are matched by type and name.
  void _addTags(_SourceScope scope) {
    final rows = scope.rows;
    final remember = scope.remember;
    for (final row in rows('Tag', 'ORDER BY TagId')) {
      final old = row.remove('TagId') as int;
      final key = _key([row['Type'], row['Type'] == 0 ? null : row['Name']]);
      remember('Tag', old, _tags.putIfAbsent(key, () => _insert('Tag', row)));
    }
  }

  /// Highlights: the whole graph with the highest Version wins.
  void _addUserMarks(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remember = scope.remember;
    final remap = scope.remap;
    final markVersions = scope.markVersions;
    final selectedMarks = scope.selectedMarks;
    final rangeCursor = streamRows(
      source.db,
      'SELECT * FROM BlockRange ORDER BY UserMarkId, BlockRangeId',
    ).iterator;
    var pendingRange = rangeCursor.moveNext() ? rangeCursor.current : null;
    for (final row in rows('UserMark', 'ORDER BY UserMarkId')) {
      final original = Map<String, Object?>.of(row);
      final old = row.remove('UserMarkId') as int;
      final guid = _guid(row, 'UserMarkGuid', source);
      final revision = row['Version'] as int;
      final ranges = <Map<String, Object?>>[];
      // Both cursors are ordered by UserMarkId: a merge join reads every
      // range once without a query per highlight or a table in memory.
      while (pendingRange != null &&
          (pendingRange['UserMarkId'] as int) <= old) {
        if (pendingRange['UserMarkId'] == old) ranges.add(pendingRange);
        pendingRange = rangeCursor.moveNext() ? rangeCursor.current : null;
      }
      final entity = 'UserMark:$guid';
      final versionId = report.stageVersion(source, 'UserMark', entity, {
        ...original,
        'BlockRanges': ranges,
      });
      remap(row, 'Location');
      // GUID spelling is normalized by _guid for identity, not a content change.
      final metadata = Map<String, Object?>.of(row)
        ..remove('Version')
        ..remove('UserMarkGuid');
      final rangeKeys =
          ranges
              .map(
                (r) => _stableJson(
                  Map<String, Object?>.of(r)
                    ..remove('BlockRangeId')
                    ..remove('UserMarkId'),
                ),
              )
              .toList()
            ..sort();
      final signature = _reportId([metadata, rangeKeys]);
      final match = _marks[guid];
      final id = match?.$1 ?? _insert('UserMark', row);
      if (match != null && signature != match.$3) report.markConflict(entity);
      if (match != null && revision > match.$2) {
        _update('UserMark', 'UserMarkId', id, row);
        _statements.execute('DELETE FROM BlockRange WHERE UserMarkId = ?', [
          id,
        ]);
      }
      if (match == null || revision > match.$2) {
        _marks[guid] = (id, revision, signature);
        selectedMarks.add(old);
        report.selectVersion(entity, versionId);
      }
      markVersions[old] = revision;
      remember('UserMark', old, id);
    }
    // Finish the cursor so its statement is released.
    while (rangeCursor.moveNext()) {}
  }

  /// Notes are matched by GUID and chosen by the configured policy.
  void _addNotes(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remember = scope.remember;
    final remap = scope.remap;
    for (final row in rows('Note', 'ORDER BY NoteId')) {
      final original = Map<String, Object?>.of(row);
      final old = row.remove('NoteId') as int;
      final guid = _guid(row, 'Guid', source);
      final entity = 'Note:$guid';
      final versionId = report.stageVersion(source, 'Note', entity, original);
      remap(row, 'Location');
      remap(row, 'UserMark');
      row['Created'] ??= row['LastModified'];
      final noteId = _notes[guid];
      final match = noteId == null
          ? null
          : db.select('SELECT * FROM Note WHERE NoteId = ?', [noteId]).single;
      if (match == null) {
        final id = _insert('Note', row);
        _notes[guid] = id;
        report.selectVersion(entity, versionId);
        remember('Note', old, id);
        continue;
      }
      final id = match['NoteId'] as int;
      final fields = [
        'Title',
        'Content',
        'LocationId',
        'UserMarkId',
        'BlockType',
        'BlockIdentifier',
      ];
      if (fields.any((field) => row[field] != match[field])) {
        _noteConflicts.add(guid);
        report.markConflict(entity);
      }
      final date = _timestamp(row['LastModified']);
      final previous = _timestamp(match['LastModified']);
      if (options.notePolicy == NoteConflictPolicy.newest &&
          date != null &&
          (previous == null || date.isAfter(previous))) {
        final created = _timestamp(row['Created']);
        final previousCreated = _timestamp(match['Created']);
        if (previousCreated != null &&
            (created == null || previousCreated.isBefore(created))) {
          row['Created'] = match['Created'];
        }
        _update('Note', 'NoteId', id, row);
        _notes[guid] = id;
        report.selectVersion(entity, versionId);
      } else {
        final created = _timestamp(row['Created']);
        final previousCreated = _timestamp(match['Created']);
        if (created != null &&
            (previousCreated == null || created.isBefore(previousCreated))) {
          db.execute('UPDATE Note SET Created = ? WHERE NoteId = ?', [
            row['Created'],
            id,
          ]);
        }
      }
      remember('Note', old, id);
    }
  }

  /// Ranges are copied only for the highlight version that was selected.
  void _addBlockRanges(_SourceScope scope) {
    final rows = scope.rows;
    final remap = scope.remap;
    final markVersions = scope.markVersions;
    final selectedMarks = scope.selectedMarks;
    for (final row in rows('BlockRange', 'ORDER BY BlockRangeId')) {
      row.remove('BlockRangeId');
      final oldMark = row['UserMarkId'] as int;
      if (!selectedMarks.contains(oldMark)) continue;
      final revision = markVersions[oldMark];
      remap(row, 'UserMark');
      final key = _key([revision, ...row.values]);
      if (_ranges.add(key)) _insert('BlockRange', row);
    }
  }

  /// Publication answers are matched by location and text tag.
  void _addInputFields(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remap = scope.remap;
    for (final row in rows('InputField')) {
      final original = Map<String, Object?>.of(row);
      remap(row, 'Location');
      final key = _key([row['LocationId'], row['TextTag']]);
      final location =
          Map<String, Object?>.of(
              db.select('SELECT * FROM Location WHERE LocationId = ?', [
                row['LocationId'],
              ]).single,
            )
            ..remove('LocationId')
            ..remove('Title');
      final entity = 'InputField:${_stableJson([location, row['TextTag']])}';
      final versionId = report.stageVersion(
        source,
        'InputField',
        entity,
        original,
      );
      final previousDate = _fields[key];
      if (previousDate == null) {
        _fields[key] = source.modified;
        _insert('InputField', row);
        report.selectVersion(entity, versionId);
      } else {
        final previous = db.select(
          'SELECT Value FROM InputField WHERE LocationId = ? AND TextTag = ?',
          [row['LocationId'], row['TextTag']],
        ).single['Value'];
        if (previous != row['Value']) {
          _fieldConflicts.add(key);
          report.markConflict(entity);
        }
        if (options.fieldPolicy == FieldConflictPolicy.newestBackup &&
            source.modified.isAfter(previousDate)) {
          db.execute(
            'UPDATE InputField SET Value = ? WHERE LocationId = ? AND TextTag = ?',
            [row['Value'], row['LocationId'], row['TextTag']],
          );
          _fields[key] = source.modified;
          report.selectVersion(entity, versionId);
        }
      }
    }
  }

  /// Bookmarks are staged; slots are assigned later in writeBookmarks.
  void _addBookmarks(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remap = scope.remap;
    final sourceIndex = _sources.length;
    _sources.add(source);
    for (final row in rows('Bookmark', 'ORDER BY BookmarkId')) {
      final original = Map<String, Object?>.of(row);
      row.remove('BookmarkId');
      remap(row, 'Location');
      remap(row, 'Location', 'PublicationLocationId');
      report.run(
        'INSERT OR IGNORE INTO Bookmarks(publication, signature, source, data, original) VALUES(?,?,?,?,?)',
        [
          row['PublicationLocationId'],
          _stableJson(Map<String, Object?>.of(row)..remove('Slot')),
          sourceIndex,
          jsonEncode(row),
          jsonEncode(original),
        ],
      );
    }
  }

  /// Media rows are matched by their stored file.
  void _addIndependentMedia(_SourceScope scope) {
    final source = scope.source;
    final rows = scope.rows;
    final remember = scope.remember;
    for (final row in rows('IndependentMedia', 'ORDER BY IndependentMediaId')) {
      final old = row.remove('IndependentMediaId') as int;
      final entry = scope.media[row['FilePath']];
      if (entry == null || entry.$2 != (row['Hash'] as String).toLowerCase()) {
        throw MergeFailure(MergeErrorCode.missingMedia, source.name);
      }
      row['FilePath'] = entry.$1;
      row['Hash'] = (row['Hash'] as String).toLowerCase();
      remember(
        'IndependentMedia',
        old,
        _mediaIds.putIfAbsent(entry.$1, () => _insert('IndependentMedia', row)),
      );
    }
  }

  /// Playlist accuracy values are matched by description.
  void _addAccuracy(_SourceScope scope) {
    final rows = scope.rows;
    final remember = scope.remember;
    for (final row in rows(
      'PlaylistItemAccuracy',
      'ORDER BY PlaylistItemAccuracyId',
    )) {
      final old = row.remove('PlaylistItemAccuracyId') as int;
      final description = row['Description'] as String;
      remember(
        'PlaylistItemAccuracy',
        old,
        _accuracy.putIfAbsent(
          description,
          () => _insert('PlaylistItemAccuracy', row),
        ),
      );
    }
  }

  /// Records which playlists differ between backups.
  void _comparePlaylists(_SourceScope scope, Map<int, String> itemSignatures) {
    final source = scope.source;
    final rows = scope.rows;
    for (final tag in rows('Tag', 'WHERE Type = 2 ORDER BY TagId')) {
      final entity = 'Playlist:${_stableJson(tag['Name'])}';
      final links = source.db.select(
        'SELECT * FROM TagMap WHERE TagId = ? AND PlaylistItemId IS NOT NULL ORDER BY Position, TagMapId',
        [tag['TagId']],
      );
      final sequence = [
        for (final link in links) itemSignatures[link['PlaylistItemId']],
      ];
      final signature = _reportId(sequence);
      final versionId = report.stageVersion(source, 'Playlist', entity, {
        ...tag,
        'Items': [
          for (final link in links)
            {
              'Position': link['Position'],
              ..._playlistGraph(source, link['PlaylistItemId'] as int),
            },
        ],
      });
      final previous = _playlistSignatures[entity];
      if (previous == null) {
        _playlistSignatures[entity] = signature;
        report.selectVersion(entity, versionId);
      } else if (previous != signature) {
        report.markConflict(entity);
      }
    }
  }

  /// Tag links are remapped and renumbered per tag.
  void _addTagMaps(_SourceScope scope, Map<int, String> itemSignatures) {
    final source = scope.source;
    final rows = scope.rows;
    final remap = scope.remap;
    final playlistOccurrences = scope.playlistOccurrences;
    for (final row in rows('TagMap', 'ORDER BY TagId, Position, TagMapId')) {
      final originalItem = row['PlaylistItemId'];
      row.remove('TagMapId');
      for (final entity in ['Tag', 'Note', 'Location', 'PlaylistItem']) {
        remap(row, entity);
      }
      final tag = row['TagId'] as int;
      if (originalItem is int) {
        final signature = itemSignatures[originalItem]!;
        final occurrence = playlistOccurrences.update(
          _key([tag, signature]),
          (n) => n + 1,
          ifAbsent: () => 0,
        );
        final key = _key([tag, signature, occurrence]);
        row['PlaylistItemId'] = _playlistTargets.putIfAbsent(key, () {
          final used = _playlistUsedTargets[tag] ??= {};
          for (var instance = 0; ; instance++) {
            final candidate = _items[_key([signature, instance])];
            if (candidate == null) {
              throw MergeFailure(MergeErrorCode.invalidDatabase, source.name);
            }
            if (used.add(candidate)) return candidate;
          }
        });
      }
      final target = _key([
        tag,
        row['NoteId'],
        row['LocationId'],
        row['PlaylistItemId'],
      ]);
      if (_tagLinks.add(target)) {
        final position = _tagPositions.update(
          tag,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        row['Position'] = position;
        _insert('TagMap', row);
      }
    }
  }

  Map<int, String> _addModernPlaylists(
    _Source source,
    Map<String, Map<int, int>> ids,
    String? Function(Object?) mediaPath,
  ) {
    final locationLinks = _children(
      source,
      'PlaylistItemLocationMap',
      'PlaylistItemId',
      'LocationId',
    );
    final mediaLinks = _children(
      source,
      'PlaylistItemIndependentMediaMap',
      'PlaylistItemId',
      'IndependentMediaId',
    );
    final markers = _children(
      source,
      'PlaylistItemMarker',
      'PlaylistItemId',
      'StartTimeTicks',
    );
    final verses = _children(
      source,
      'PlaylistItemMarkerBibleVerseMap',
      'PlaylistItemMarkerId',
      'VerseId',
    );
    final paragraphs = _children(
      source,
      'PlaylistItemMarkerParagraphMap',
      'PlaylistItemMarkerId',
      'MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph',
    );
    final itemIds = ids['PlaylistItem'] = {};
    final signatures = <int, String>{};
    final occurrences = <String, int>{};
    for (final record in source.db.select(
      'SELECT * FROM PlaylistItem ORDER BY PlaylistItemId',
    )) {
      final row = Map<String, Object?>.of(record);
      final old = row.remove('PlaylistItemId') as int;
      row['Accuracy'] = ids['PlaylistItemAccuracy']![row['Accuracy']]!;
      row['ThumbnailFilePath'] = mediaPath(row['ThumbnailFilePath']);
      final locations = locationLinks[old] ?? [];
      for (final link in locations) {
        link['LocationId'] = ids['Location']![link['LocationId']]!;
      }
      final media = mediaLinks[old] ?? [];
      for (final link in media) {
        link['IndependentMediaId'] =
            ids['IndependentMedia']![link['IndependentMediaId']]!;
      }
      final itemMarkers = (markers[old] ?? []).map((marker) {
        final markerId = marker.remove('PlaylistItemMarkerId') as int;
        return (marker, verses[markerId] ?? [], paragraphs[markerId] ?? []);
      }).toList();
      final semanticRow = Map<String, Object?>.of(row)
        ..remove('ThumbnailFilePath');
      semanticRow['ThumbnailHash'] = row['ThumbnailFilePath'] == null
          ? null
          : db.select('SELECT Hash FROM IndependentMedia WHERE FilePath = ?', [
              row['ThumbnailFilePath'],
            ]).single['Hash'];
      final semanticMedia = [
        for (final link in media)
          {
            ...Map<String, Object?>.of(link)..remove('IndependentMediaId'),
            ...db.select(
              'SELECT Hash, MimeType FROM IndependentMedia WHERE IndependentMediaId = ?',
              [link['IndependentMediaId']],
            ).single,
          },
      ];
      final signature = _reportId([
        semanticRow,
        _sortedKeys(locations),
        _sortedKeys(semanticMedia),
        for (final (marker, v, a) in itemMarkers) [marker, v, a],
      ]);
      signatures[old] = signature;
      final key = _key([
        signature,
        occurrences.update(signature, (count) => count + 1, ifAbsent: () => 0),
      ]);
      final existing = _items[key];
      if (existing != null) {
        itemIds[old] = existing;
        continue;
      }
      final id = _insert('PlaylistItem', row);
      _items[key] = id;
      itemIds[old] = id;
      _insertChildren(
        'PlaylistItemLocationMap',
        'PlaylistItemId',
        id,
        locations,
      );
      _insertChildren(
        'PlaylistItemIndependentMediaMap',
        'PlaylistItemId',
        id,
        media,
      );
      for (final (marker, v, a) in itemMarkers) {
        final markerId = _insert('PlaylistItemMarker', {
          ...marker,
          'PlaylistItemId': id,
        });
        _insertChildren(
          'PlaylistItemMarkerBibleVerseMap',
          'PlaylistItemMarkerId',
          markerId,
          v,
        );
        _insertChildren(
          'PlaylistItemMarkerParagraphMap',
          'PlaylistItemMarkerId',
          markerId,
          a,
        );
      }
    }
    return signatures;
  }

  Map<String, Object?> _playlistGraph(_Source source, int id) {
    final db = source.db;
    final item = Map<String, Object?>.of(
      db.select('SELECT * FROM PlaylistItem WHERE PlaylistItemId = ?', [
        id,
      ]).single,
    );
    return {
      'Item': item,
      'Thumbnail': item['ThumbnailFilePath'] == null
          ? null
          : Map<String, Object?>.of(
              db.select('SELECT * FROM IndependentMedia WHERE FilePath = ?', [
                item['ThumbnailFilePath'],
              ]).single,
            ),
      'Locations': [
        for (final link in db.select(
          'SELECT * FROM PlaylistItemLocationMap WHERE PlaylistItemId = ? ORDER BY LocationId',
          [id],
        ))
          {
            ...link,
            'Location': Map<String, Object?>.of(
              db.select('SELECT * FROM Location WHERE LocationId = ?', [
                link['LocationId'],
              ]).single,
            ),
          },
      ],
      'Media': [
        for (final link in db.select(
          'SELECT * FROM PlaylistItemIndependentMediaMap WHERE PlaylistItemId = ? ORDER BY IndependentMediaId',
          [id],
        ))
          {
            ...link,
            'IndependentMedia': Map<String, Object?>.of(
              db.select(
                'SELECT * FROM IndependentMedia WHERE IndependentMediaId = ?',
                [link['IndependentMediaId']],
              ).single,
            ),
          },
      ],
      'Markers': [
        for (final marker in db.select(
          'SELECT * FROM PlaylistItemMarker WHERE PlaylistItemId = ? ORDER BY StartTimeTicks',
          [id],
        ))
          {
            ...marker,
            'Verses': [
              for (final r in db.select(
                'SELECT * FROM PlaylistItemMarkerBibleVerseMap WHERE PlaylistItemMarkerId = ? ORDER BY VerseId',
                [marker['PlaylistItemMarkerId']],
              ))
                Map<String, Object?>.of(r),
            ],
            'Paragraphs': [
              for (final r in db.select(
                'SELECT * FROM PlaylistItemMarkerParagraphMap WHERE PlaylistItemMarkerId = ? ORDER BY MepsDocumentId, ParagraphIndex, MarkerIndexWithinParagraph',
                [marker['PlaylistItemMarkerId']],
              ))
                Map<String, Object?>.of(r),
            ],
          },
      ],
    };
  }

  void writeBookmarks() {
    for (final publication in streamRows(
      report.store,
      'SELECT DISTINCT publication FROM Bookmarks ORDER BY publication',
    )) {
      final slots = <int>{};
      final pub = publication['publication'];
      for (final entry in streamRows(
        report.store,
        'SELECT * FROM Bookmarks WHERE publication = ? ORDER BY id',
        [pub],
      )) {
        final row = Map<String, Object?>.from(
          jsonDecode(entry['data'] as String) as Map,
        );
        final slot = row['Slot'] as int;
        if (slot >= 0 && slot < 10 && slots.add(slot)) {
          _insert('Bookmark', row);
        } else {
          report.store.execute(
            'UPDATE Bookmarks SET displaced = 1 WHERE id = ?',
            [entry['id']],
          );
        }
      }
      for (final entry in streamRows(
        report.store,
        'SELECT * FROM Bookmarks WHERE publication = ? AND displaced = 1 ORDER BY id',
        [pub],
      )) {
        bookmarkConflicts++;
        final available = List.generate(
          10,
          (i) => i,
        ).where((i) => !slots.contains(i));
        if (available.isNotEmpty) {
          final slot = available.first;
          slots.add(slot);
          final row = Map<String, Object?>.from(
            jsonDecode(entry['data'] as String) as Map,
          );
          _insert('Bookmark', {...row, 'Slot': slot});
        } else {
          skippedBookmarks++;
          report.retain(
            _sources[entry['source'] as int],
            'Bookmark',
            'bookmarkSlotsFull',
            Map<String, Object?>.from(
              jsonDecode(entry['original'] as String) as Map,
            ),
          );
        }
      }
    }
  }

  late final _statements = StatementCache(db);

  /// Closes cached statements; call before closing [db].
  void dispose() => _statements.dispose();

  int _insert(String table, Map<String, Object?> row) =>
      _statements.insert(table, row);

  void _update(String table, String pk, int id, Map<String, Object?> row) {
    final columns = row.keys
        .map((name) => '${quoteIdentifier(name)} = ?')
        .join(', ');
    _statements.execute(
      'UPDATE ${quoteIdentifier(table)} SET $columns WHERE ${quoteIdentifier(pk)} = ?',
      [...row.values, id],
    );
  }

  void _insertChildren(
    String table,
    String parentKey,
    int parent,
    List<Map<String, Object?>> rows,
  ) {
    for (final row in rows) {
      _insert(table, {...row, parentKey: parent});
    }
  }
}

Map<int, List<Map<String, Object?>>> _children(
  _Source source,
  String table,
  String parent,
  String order,
) {
  final children = <int, List<Map<String, Object?>>>{};
  for (final record in source.db.select(
    'SELECT * FROM "$table" ORDER BY "$parent", $order',
  )) {
    final row = Map<String, Object?>.of(record);
    final key = row.remove(parent) as int;
    (children[key] ??= []).add(row);
  }
  return children;
}

String _guid(Map<String, Object?> row, String column, _Source source) {
  final value = row[column];
  if (value is! String || value.isEmpty) {
    throw MergeFailure(MergeErrorCode.invalidDatabase, source.name);
  }
  return value.toLowerCase();
}

String _key(Object? values) => jsonEncode(values);

List<String> _sortedKeys(List<Map<String, Object?>> rows) =>
    rows.map(_key).toList()..sort();

String _stableJson(Object? value) {
  Object? sorted(Object? input) {
    if (input is Map) {
      final keys = input.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(input[key])};
    }
    if (input is List) return input.map(sorted).toList();
    return input;
  }

  return jsonEncode(sorted(value));
}

String _reportId(Object? value) =>
    sha256.convert(utf8.encode(_stableJson(value))).toString();
