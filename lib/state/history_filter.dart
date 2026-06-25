import '../data/history_db.dart';

/// Status filter for the history table.
enum HistoryStatusFilter { all, succeeded, failed }

/// Direction filter for the history table.
enum HistoryDirectionFilter { all, upload, download }

/// Time-window filter for the history table.
enum HistoryDateFilter { all, last24h, last7d, last30d }

/// The cut-off instant for [filter] relative to [now], or null for "all time".
DateTime? historySince(HistoryDateFilter filter, DateTime now) {
  switch (filter) {
    case HistoryDateFilter.all:
      return null;
    case HistoryDateFilter.last24h:
      return now.subtract(const Duration(hours: 24));
    case HistoryDateFilter.last7d:
      return now.subtract(const Duration(days: 7));
    case HistoryDateFilter.last30d:
      return now.subtract(const Duration(days: 30));
  }
}

/// True when [r] matches the active filters: a case-insensitive substring
/// [query] over the file name, source/destination paths and session, plus the
/// status and direction selectors and an optional `finishedAt >= since`
/// window. A blank query matches all.
bool historyMatches(
  TransferRecord r, {
  String query = '',
  HistoryStatusFilter status = HistoryStatusFilter.all,
  HistoryDirectionFilter direction = HistoryDirectionFilter.all,
  DateTime? since,
}) {
  switch (status) {
    case HistoryStatusFilter.succeeded:
      if (!r.success) return false;
    case HistoryStatusFilter.failed:
      if (r.success) return false;
    case HistoryStatusFilter.all:
      break;
  }
  switch (direction) {
    case HistoryDirectionFilter.upload:
      if (!r.isUpload) return false;
    case HistoryDirectionFilter.download:
      if (r.isUpload) return false;
    case HistoryDirectionFilter.all:
      break;
  }
  if (since != null && r.finishedAt.isBefore(since)) return false;
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  for (final field in [r.name, r.sourcePath, r.destPath, r.session]) {
    if (field.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// Filters [all] by the active selectors, preserving order.
List<TransferRecord> filterHistory(
  List<TransferRecord> all, {
  String query = '',
  HistoryStatusFilter status = HistoryStatusFilter.all,
  HistoryDirectionFilter direction = HistoryDirectionFilter.all,
  DateTime? since,
}) =>
    [
      for (final r in all)
        if (historyMatches(r, query: query, status: status, direction: direction, since: since)) r
    ];

/// Aggregate stats for one endpoint (transfer [session]).
class EndpointStat {
  final String endpoint;
  final int count;
  final int succeeded;
  final int totalBytes;
  const EndpointStat(this.endpoint, this.count, this.succeeded, this.totalBytes);

  int get failed => count - succeeded;
}

/// Per-endpoint breakdown of [records], grouped by `session`, ordered by bytes
/// transferred (descending), then by count. Blank sessions group under "—".
List<EndpointStat> breakdownByEndpoint(List<TransferRecord> records) {
  final counts = <String, int>{};
  final ok = <String, int>{};
  final bytes = <String, int>{};
  for (final r in records) {
    final key = r.session.trim().isEmpty ? '—' : r.session;
    counts[key] = (counts[key] ?? 0) + 1;
    if (r.success) ok[key] = (ok[key] ?? 0) + 1;
    bytes[key] = (bytes[key] ?? 0) + r.sizeBytes;
  }
  final stats = [
    for (final key in counts.keys)
      EndpointStat(key, counts[key]!, ok[key] ?? 0, bytes[key]!),
  ];
  stats.sort((a, b) {
    final byBytes = b.totalBytes.compareTo(a.totalBytes);
    return byBytes != 0 ? byBytes : b.count.compareTo(a.count);
  });
  return stats;
}

/// Sums the bytes of [records] into [buckets] equal time slices spanning
/// `[start, end)`, ordered oldest-first. Records outside the range are
/// ignored; an [end] at or before [start], or a non-positive [buckets], yields
/// an empty series. Useful for a throughput-over-time sparkline.
List<int> bytesOverTime(
  List<TransferRecord> records, {
  required DateTime start,
  required DateTime end,
  int buckets = 24,
}) {
  if (buckets <= 0 || !end.isAfter(start)) return const [];
  final span = end.difference(start).inMicroseconds;
  final slice = span / buckets;
  final out = List<int>.filled(buckets, 0);
  for (final r in records) {
    final t = r.finishedAt;
    if (t.isBefore(start) || !t.isBefore(end)) continue;
    final offset = t.difference(start).inMicroseconds;
    var i = (offset / slice).floor();
    if (i < 0) i = 0;
    if (i >= buckets) i = buckets - 1;
    out[i] += r.sizeBytes;
  }
  return out;
}
