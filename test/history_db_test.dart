import 'package:drag/data/history_db.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late HistoryRepository repo;

  setUp(() async {
    repo = await HistoryRepository.open(inMemoryDatabasePath);
  });
  tearDown(() => repo.close());

  TransferRecord rec({
    String name = 'f.bin',
    int size = 1000,
    int direction = 0,
    int durationMs = 500,
    bool success = true,
  }) =>
      TransferRecord(
        name: name,
        sourcePath: 'Local:/a/$name',
        destPath: 's3://bucket/$name',
        session: 'bucket',
        sizeBytes: size,
        direction: direction,
        durationMs: durationMs,
        success: success,
        finishedAt: DateTime.now(),
      );

  test('starts empty', () async {
    expect(await repo.recent(), isEmpty);
    final s = await repo.stats();
    expect(s.total, 0);
  });

  test('add + recent returns newest first', () async {
    await repo.add(rec(name: 'first.bin'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.add(rec(name: 'second.bin'));
    final list = await repo.recent();
    expect(list.length, 2);
    expect(list.first.name, 'second.bin');
  });

  test('stats aggregates totals, success/fail and average speed', () async {
    await repo.add(rec(name: 'ok1.bin', size: 1000, durationMs: 1000, success: true)); // 1000 B/s
    await repo.add(rec(name: 'ok2.bin', size: 3000, durationMs: 1000, success: true)); // 3000 B/s
    await repo.add(rec(name: 'bad.bin', size: 500, durationMs: 0, success: false));

    final s = await repo.stats();
    expect(s.total, 3);
    expect(s.succeeded, 2);
    expect(s.failed, 1);
    expect(s.totalBytes, 4500);
    // (1000 + 3000) bytes over (1000 + 1000) ms = 2000 B/s.
    expect(s.avgBytesPerSecond, closeTo(2000, 0.001));
  });

  test('clear empties the table', () async {
    await repo.add(rec());
    await repo.clear();
    expect(await repo.recent(), isEmpty);
    expect((await repo.stats()).total, 0);
  });

  test('round-trips fields through the DB', () async {
    await repo.add(rec(name: 'photo.jpg', size: 2048, direction: 1, durationMs: 750));
    final r = (await repo.recent()).single;
    expect(r.name, 'photo.jpg');
    expect(r.sizeBytes, 2048);
    expect(r.isUpload, isFalse);
    expect(r.durationMs, 750);
    expect(r.destPath, 's3://bucket/photo.jpg');
    expect(r.bytesPerSecond, closeTo(2048 * 1000 / 750, 0.001));
  });

  group('TransferRecord.fromTransfer', () {
    test('maps a finished transfer', () {
      final t = Transfer(
        name: 'x.zip',
        route: 'r',
        direction: TransferDirection.download,
        sizeBytes: 4096,
        session: 'bk',
        sourcePath: 's3://bk/x.zip',
        destPath: 'Local:/tmp/x.zip',
        status: TransferStatus.done,
      )
        ..startedAt = DateTime(2025, 1, 1, 0, 0, 0)
        ..finishedAt = DateTime(2025, 1, 1, 0, 0, 2);
      final r = TransferRecord.fromTransfer(t);
      expect(r.success, isTrue);
      expect(r.direction, 1);
      expect(r.durationMs, 2000);
      expect(r.sizeBytes, 4096);
    });
  });
}
