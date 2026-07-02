import 'package:drag/data/history_db.dart';
import 'package:drag/state/history_filter.dart';
import 'package:flutter_test/flutter_test.dart';

TransferRecord rec({
  String name = 'file.bin',
  String sourcePath = '/src/file.bin',
  String destPath = '/dst/file.bin',
  String session = 'prod-server',
  int sizeBytes = 1000,
  int direction = 0, // 0 = upload
  bool success = true,
  DateTime? finishedAt,
}) => TransferRecord(
  name: name,
  sourcePath: sourcePath,
  destPath: destPath,
  session: session,
  sizeBytes: sizeBytes,
  direction: direction,
  durationMs: 1000,
  success: success,
  finishedAt: finishedAt ?? DateTime(2024, 1, 1),
);

void main() {
  group('historyMatches', () {
    test('blank query and all-filters matches everything', () {
      expect(historyMatches(rec()), isTrue);
      expect(historyMatches(rec(success: false, direction: 1)), isTrue);
    });

    test('status filter', () {
      final ok = rec(success: true);
      final bad = rec(success: false);
      expect(historyMatches(ok, status: HistoryStatusFilter.succeeded), isTrue);
      expect(
        historyMatches(bad, status: HistoryStatusFilter.succeeded),
        isFalse,
      );
      expect(historyMatches(bad, status: HistoryStatusFilter.failed), isTrue);
      expect(historyMatches(ok, status: HistoryStatusFilter.failed), isFalse);
    });

    test('direction filter', () {
      final up = rec(direction: 0);
      final down = rec(direction: 1);
      expect(
        historyMatches(up, direction: HistoryDirectionFilter.upload),
        isTrue,
      );
      expect(
        historyMatches(down, direction: HistoryDirectionFilter.upload),
        isFalse,
      );
      expect(
        historyMatches(down, direction: HistoryDirectionFilter.download),
        isTrue,
      );
      expect(
        historyMatches(up, direction: HistoryDirectionFilter.download),
        isFalse,
      );
    });

    test(
      'text query is case-insensitive and spans name, paths and session',
      () {
        final r = rec(
          name: 'Report.pdf',
          sourcePath: '/home/docs/report.pdf',
          destPath: '/backup/report.pdf',
          session: 'EU-West-Bucket',
        );
        expect(historyMatches(r, query: 'report'), isTrue);
        expect(historyMatches(r, query: 'REPORT'), isTrue);
        expect(historyMatches(r, query: '/backup'), isTrue);
        expect(historyMatches(r, query: 'eu-west'), isTrue);
        expect(historyMatches(r, query: '  report  '), isTrue);
        expect(historyMatches(r, query: 'nomatch'), isFalse);
      },
    );

    test('combines status, direction and query (all must hold)', () {
      final r = rec(name: 'a.txt', success: false, direction: 1);
      expect(
        historyMatches(
          r,
          query: 'a.txt',
          status: HistoryStatusFilter.failed,
          direction: HistoryDirectionFilter.download,
        ),
        isTrue,
      );
      // wrong status fails the whole match
      expect(
        historyMatches(
          r,
          query: 'a.txt',
          status: HistoryStatusFilter.succeeded,
          direction: HistoryDirectionFilter.download,
        ),
        isFalse,
      );
    });
  });

  TransferRecord named(String name, {bool success = true, int direction = 0}) =>
      rec(
        name: name,
        sourcePath: '/src/$name',
        destPath: '/dst/$name',
        success: success,
        direction: direction,
      );

  group('filterHistory', () {
    final all = [
      named('one.bin', success: true, direction: 0),
      named('two.bin', success: false, direction: 1),
      named('three.log', success: true, direction: 1),
    ];

    test('no filters returns all in order', () {
      final out = filterHistory(all);
      expect(out.map((r) => r.name), ['one.bin', 'two.bin', 'three.log']);
    });

    test('status filter narrows results', () {
      final out = filterHistory(all, status: HistoryStatusFilter.failed);
      expect(out.map((r) => r.name), ['two.bin']);
    });

    test('query filter narrows results', () {
      final out = filterHistory(all, query: '.bin');
      expect(out.map((r) => r.name), ['one.bin', 'two.bin']);
    });

    test('preserves input order', () {
      final out = filterHistory(
        all,
        direction: HistoryDirectionFilter.download,
      );
      expect(out.map((r) => r.name), ['two.bin', 'three.log']);
    });
  });

  group('breakdownByEndpoint', () {
    test('groups by session and aggregates count/succeeded/bytes', () {
      final records = [
        rec(session: 'alpha', sizeBytes: 100, success: true),
        rec(session: 'alpha', sizeBytes: 200, success: false),
        rec(session: 'beta', sizeBytes: 50, success: true),
      ];
      final stats = breakdownByEndpoint(records);
      final alpha = stats.firstWhere((s) => s.endpoint == 'alpha');
      expect(alpha.count, 2);
      expect(alpha.succeeded, 1);
      expect(alpha.failed, 1);
      expect(alpha.totalBytes, 300);
      final beta = stats.firstWhere((s) => s.endpoint == 'beta');
      expect(beta.count, 1);
      expect(beta.succeeded, 1);
      expect(beta.totalBytes, 50);
    });

    test('orders by total bytes descending, then by count', () {
      final records = [
        rec(session: 'small', sizeBytes: 10),
        rec(session: 'big', sizeBytes: 5000),
        rec(session: 'mid', sizeBytes: 500),
      ];
      final stats = breakdownByEndpoint(records);
      expect(stats.map((s) => s.endpoint), ['big', 'mid', 'small']);
    });

    test('blank session groups under em dash', () {
      final stats = breakdownByEndpoint([rec(session: '   ', sizeBytes: 1)]);
      expect(stats.single.endpoint, '—');
    });

    test('empty input yields empty breakdown', () {
      expect(breakdownByEndpoint(const []), isEmpty);
    });
  });

  group('date window', () {
    final now = DateTime(2024, 6, 15, 12);
    test('historySince computes the right cut-offs', () {
      expect(historySince(HistoryDateFilter.all, now), isNull);
      expect(
        historySince(HistoryDateFilter.last24h, now),
        now.subtract(const Duration(hours: 24)),
      );
      expect(
        historySince(HistoryDateFilter.last7d, now),
        now.subtract(const Duration(days: 7)),
      );
      expect(
        historySince(HistoryDateFilter.last30d, now),
        now.subtract(const Duration(days: 30)),
      );
    });

    test('since excludes records finished before the cut-off', () {
      final recent = rec(
        name: 'recent',
        finishedAt: now.subtract(const Duration(hours: 2)),
      );
      final old = rec(
        name: 'old',
        finishedAt: now.subtract(const Duration(days: 3)),
      );
      final since = historySince(HistoryDateFilter.last24h, now);
      expect(historyMatches(recent, since: since), isTrue);
      expect(historyMatches(old, since: since), isFalse);
      final out = filterHistory([recent, old], since: since);
      expect(out.map((r) => r.name), ['recent']);
    });
  });

  group('bytesOverTime', () {
    final start = DateTime(2024, 1, 1);
    final end = DateTime(2024, 1, 1, 4); // 4-hour span

    test('buckets bytes by finish time, oldest first', () {
      final records = [
        rec(sizeBytes: 100, finishedAt: start), // bucket 0
        rec(
          sizeBytes: 50,
          finishedAt: start.add(const Duration(hours: 1)),
        ), // bucket 1
        rec(
          sizeBytes: 25,
          finishedAt: start.add(const Duration(hours: 1, minutes: 30)),
        ), // bucket 1
        rec(
          sizeBytes: 10,
          finishedAt: start.add(const Duration(hours: 3)),
        ), // bucket 3
      ];
      final series = bytesOverTime(records, start: start, end: end, buckets: 4);
      expect(series, [100, 75, 0, 10]);
    });

    test('ignores records outside the range', () {
      final records = [
        rec(
          sizeBytes: 999,
          finishedAt: start.subtract(const Duration(hours: 1)),
        ),
        rec(sizeBytes: 999, finishedAt: end.add(const Duration(hours: 1))),
        rec(sizeBytes: 7, finishedAt: start.add(const Duration(hours: 2))),
      ];
      final series = bytesOverTime(records, start: start, end: end, buckets: 4);
      expect(series.fold<int>(0, (a, b) => a + b), 7);
    });

    test('the end instant lands in the last bucket (half-open at end)', () {
      final atEnd = rec(sizeBytes: 5, finishedAt: end);
      final series = bytesOverTime([atEnd], start: start, end: end, buckets: 4);
      // end is exclusive → excluded entirely
      expect(series, [0, 0, 0, 0]);
    });

    test('degenerate inputs yield an empty series', () {
      expect(
        bytesOverTime(const [], start: start, end: start, buckets: 4),
        isEmpty,
      );
      expect(
        bytesOverTime(const [], start: end, end: start, buckets: 4),
        isEmpty,
      );
      expect(
        bytesOverTime(const [], start: start, end: end, buckets: 0),
        isEmpty,
      );
    });
  });
}
