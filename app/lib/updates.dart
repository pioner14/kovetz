import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_info.dart';

/// Where the app looks for new versions: releases of the public repository.
final updateFeed = Uri.parse(
  'https://api.github.com/repos/pioner14/kovetz/releases?per_page=20',
);

enum UpdateErrorKind { network, server, format }

class UpdateFailure implements Exception {
  const UpdateFailure(this.kind, [this.detail]);

  final UpdateErrorKind kind;
  final String? detail;

  @override
  String toString() =>
      'UpdateFailure($kind${detail == null ? '' : ', $detail'})';
}

/// One published version of the app.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.page,
    required this.notes,
    required this.prerelease,
    required this.assets,
  });

  /// Numbers of the version, e.g. `0.5.1`.
  final String version;
  final String tag;
  final Uri page;

  /// Release description written for people, possibly empty.
  final String notes;
  final bool prerelease;

  /// File name → download link.
  final Map<String, Uri> assets;

  /// The file for this platform (`android`, `linux` or `windows`), or null.
  Uri? assetFor(String platform) {
    for (final entry in assets.entries) {
      final name = entry.key.toLowerCase();
      final match = switch (platform) {
        'android' => name.endsWith('.apk'),
        'linux' => name.contains('linux') && name.endsWith('.appimage'),
        'windows' => name.contains('windows') && name.endsWith('.exe'),
        _ => false,
      };
      if (match) return entry.value;
    }
    return null;
  }
}

/// `1.2.3` from `v1.2.3`, `1.2.3-beta` or `1.2.3+4`; null if not a version.
List<int>? parseVersion(String text) {
  final match = RegExp(r'^[vV]?(\d+(?:\.\d+){0,3})').firstMatch(text.trim());
  if (match == null) return null;
  return [for (final part in match.group(1)!.split('.')) int.parse(part)];
}

/// Negative when [a] is older than [b], zero when equal, positive when newer.
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}

/// The newest release of the app in a GitHub `releases` JSON list.
///
/// Drafts are skipped. A release counts only if it carries files named
/// `kovetz-…`: the repository also holds releases of the old Python
/// tool, and those must never be offered as an update.
ReleaseInfo? newestRelease(String json) {
  final Object? data;
  try {
    data = jsonDecode(json);
  } on FormatException {
    throw const UpdateFailure(UpdateErrorKind.format);
  }
  if (data is! List) throw const UpdateFailure(UpdateErrorKind.format);
  ReleaseInfo? best;
  List<int>? bestVersion;
  for (final raw in data) {
    if (raw is! Map || raw['draft'] == true) continue;
    final tag = raw['tag_name'];
    final page = raw['html_url'];
    if (tag is! String || page is! String) continue;
    final version = parseVersion(tag);
    if (version == null) continue;
    final assets = <String, Uri>{};
    for (final asset in raw['assets'] is List ? raw['assets'] as List : []) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String &&
          url is String &&
          name.toLowerCase().startsWith('kovetz-')) {
        assets[name] = Uri.parse(url);
      }
    }
    if (assets.isEmpty) continue;
    if (bestVersion == null || compareVersions(version, bestVersion) > 0) {
      bestVersion = version;
      best = ReleaseInfo(
        version: version.join('.'),
        tag: tag,
        page: Uri.parse(page),
        notes: (raw['body'] as String?)?.trim() ?? '',
        prerelease: raw['prerelease'] == true,
        assets: assets,
      );
    }
  }
  return best;
}

class UpdateResult {
  const UpdateResult(this.latest, this.available);

  /// The newest release found, or null when there is none.
  final ReleaseInfo? latest;

  /// Whether [latest] is newer than the running version.
  final bool available;
}

/// Downloads the list of releases and compares it with the running version.
/// Only the public release list is requested; nothing about the person, the
/// device or the files is sent.
class UpdateChecker {
  UpdateChecker({Future<String> Function(Uri)? fetch, String? current})
    : _fetch = fetch ?? _download,
      _current = current ?? appVersion;

  final Future<String> Function(Uri) _fetch;
  final String _current;

  Future<UpdateResult> check() async {
    final String body;
    try {
      body = await _fetch(updateFeed);
    } on UpdateFailure {
      rethrow;
    } on Object catch (error) {
      throw UpdateFailure(
        UpdateErrorKind.network,
        error.runtimeType.toString(),
      );
    }
    final latest = newestRelease(body);
    final running = parseVersion(_current);
    if (latest == null || running == null) return UpdateResult(latest, false);
    return UpdateResult(
      latest,
      compareVersions(parseVersion(latest.version)!, running) > 0,
    );
  }
}

const _maxBytes = 2 * 1024 * 1024;

Future<String> _download(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    // A generic name: no version, device or person is revealed.
    ..userAgent = 'Kovetz-UpdateCheck';
  try {
    final request = await client.getUrl(uri);
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw UpdateFailure(
        UpdateErrorKind.server,
        'HTTP ${response.statusCode}',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBytes) {
        throw const UpdateFailure(UpdateErrorKind.format, 'too large');
      }
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}
