import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// Resource budget for one untrusted `.jwlibrary` archive.
///
/// Declared sizes from the ZIP central directory are checked before
/// extraction, and the bytes actually produced are counted while writing, so a
/// header that understates the content cannot exceed the budget.
class ArchiveLimits {
  const ArchiveLimits({
    this.maxEntries = 20000,
    this.maxEntryBytes = 4 * _gib,
    this.maxTotalBytes = 8 * _gib,
    this.maxManifestBytes = _mib,
    this.maxReportBytes = 256 * _mib,
  });

  static const _mib = 1024 * 1024;
  static const _gib = 1024 * _mib;

  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;
  final int maxManifestBytes;
  final int maxReportBytes;
}

/// Thrown when an entry produces more bytes than it was allowed.
class ArchiveLimitExceeded implements Exception {
  const ArchiveLimitExceeded();
}

/// Passes writes to [target] and stops as soon as more than [limit] bytes are
/// produced. The archive package checks declared sizes as well; this guard
/// keeps the budget independent of that implementation detail. Inflate reads
/// back its own output, so [subset] is delegated too.
class LimitedOutputStream extends OutputStream {
  LimitedOutputStream(this.target, this.limit)
    : super(byteOrder: target.byteOrder);

  final OutputStream target;
  final int limit;
  var _written = 0;

  void _count(int bytes) {
    _written += bytes;
    if (_written > limit) throw const ArchiveLimitExceeded();
  }

  @override
  int get length => target.length;

  @override
  void clear() => target.clear();

  @override
  void flush() => target.flush();

  @override
  void writeByte(int value) {
    _count(1);
    target.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _count(length ?? bytes.length);
    target.writeBytes(bytes, length: length);
  }

  @override
  void writeRange(Uint8List bytes, int start, int end) {
    _count(end - start);
    target.writeRange(bytes, start, end);
  }

  @override
  void writeStream(InputStream stream) {
    _count(stream.length);
    target.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _count(count);
    target.writeBackReference(distance, count);
  }

  @override
  Uint8List subset(int start, [int? end]) => target.subset(start, end);
}
