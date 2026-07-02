import 'history_db.dart';

/// Columns written by [historyToCsv], in order.
const _csvHeader = [
  'name',
  'source',
  'destination',
  'size_bytes',
  'direction',
  'duration_ms',
  'speed_bytes_per_sec',
  'success',
  'error',
  'session',
  'finished_at',
];

/// Escapes one CSV cell per RFC 4180: wrap in quotes when it contains a comma,
/// quote, or newline, doubling any embedded quotes.
String _cell(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Serialises [records] to a CSV document (header row + one row per transfer).
/// Pure and deterministic — the caller decides where the bytes go (file or
/// clipboard).
String historyToCsv(List<TransferRecord> records) {
  final buf = StringBuffer()..writeln(_csvHeader.join(','));
  for (final r in records) {
    buf.writeln(
      [
        _cell(r.name),
        _cell(r.sourcePath),
        _cell(r.destPath),
        _cell(r.sizeBytes),
        _cell(r.isUpload ? 'upload' : 'download'),
        _cell(r.durationMs),
        _cell(r.bytesPerSecond.round()),
        _cell(r.success ? 'true' : 'false'),
        _cell(r.error ?? ''),
        _cell(r.session),
        _cell(r.finishedAt.toUtc().toIso8601String()),
      ].join(','),
    );
  }
  return buf.toString();
}

/// A filesystem-safe, timestamped export filename like
/// `drag-history-20260625-143012.csv`.
String csvFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = now;
  return 'drag-history-${d.year}${two(d.month)}${two(d.day)}'
      '-${two(d.hour)}${two(d.minute)}${two(d.second)}.csv';
}
