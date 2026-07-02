import 'package:drag/data/history_csv.dart';
import 'package:drag/data/history_db.dart';
import 'package:flutter_test/flutter_test.dart';

TransferRecord _rec({
  String name = 'file.bin',
  String source = '/src/file.bin',
  String dest = 's3://bucket/file.bin',
  String session = 'sess',
  int sizeBytes = 2048,
  int direction = 0,
  int durationMs = 1000,
  bool success = true,
  String? error,
  DateTime? finishedAt,
}) => TransferRecord(
  name: name,
  sourcePath: source,
  destPath: dest,
  session: session,
  sizeBytes: sizeBytes,
  direction: direction,
  durationMs: durationMs,
  success: success,
  error: error,
  finishedAt: finishedAt ?? DateTime.utc(2026, 6, 25, 14, 30, 12),
);

void main() {
  group('historyToCsv', () {
    test('empty history is just the header row', () {
      final csv = historyToCsv(const []);
      final lines = csv.trim().split('\n');
      expect(lines, hasLength(1));
      expect(
        lines.first,
        'name,source,destination,size_bytes,direction,duration_ms,speed_bytes_per_sec,success,error,session,finished_at',
      );
    });

    test('serialises a record with derived speed, direction and status', () {
      final csv = historyToCsv([_rec(sizeBytes: 2000, durationMs: 1000)]);
      final rows = csv.trim().split('\n');
      expect(rows, hasLength(2));
      final cols = rows[1].split(',');
      expect(cols[0], 'file.bin');
      expect(cols[3], '2000'); // size_bytes
      expect(cols[4], 'upload');
      expect(cols[5], '1000'); // duration_ms
      expect(cols[6], '2000'); // 2000 bytes / 1s
      expect(cols[7], 'true');
      expect(cols.last, '2026-06-25T14:30:12.000Z'); // ISO-8601 UTC
    });

    test('download direction and failed status are labelled', () {
      final csv = historyToCsv([
        _rec(direction: 1, success: false, error: 'timeout'),
      ]);
      final cols = csv.trim().split('\n')[1].split(',');
      expect(cols[4], 'download');
      expect(cols[7], 'false');
      expect(cols[8], 'timeout');
    });

    test('escapes commas, quotes and newlines per RFC 4180', () {
      final csv = historyToCsv([
        _rec(name: 'a,b.txt', source: 'has "quote"', dest: 'line1\nline2'),
      ]);
      final row = csv
          .trim()
          .split('\n')
          .sublist(1)
          .join('\n'); // re-join the embedded newline
      expect(row, contains('"a,b.txt"'));
      expect(row, contains('"has ""quote"""'));
      expect(row, contains('"line1\nline2"'));
    });

    test('one CSV line per record (ignoring quoted newlines)', () {
      final csv = historyToCsv([_rec(), _rec(name: 'second.bin')]);
      expect(csv.trim().split('\n'), hasLength(3)); // header + 2
    });
  });

  group('csvFileName', () {
    test('is timestamped and filesystem-safe', () {
      final name = csvFileName(DateTime(2026, 1, 5, 9, 3, 7));
      expect(name, 'drag-history-20260105-090307.csv');
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains(' ')));
    });
  });
}
