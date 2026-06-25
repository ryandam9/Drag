import 'dart:typed_data';

import 'package:drag/fs/rate_limiter.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_backend.dart';

void main() {
  group('RateLimiter', () {
    test('unlimited never sleeps', () async {
      final waits = <Duration>[];
      final rl = RateLimiter(sleep: (d) async => waits.add(d)); // bytesPerSecond null
      await rl.acquire(1 << 20);
      expect(waits, isEmpty);
    });

    test('caps throughput at the configured rate', () async {
      var now = 0;
      final waits = <int>[];
      final rl = RateLimiter(
        bytesPerSecond: 1000,
        clockMs: () => now,
        sleep: (d) async {
          now += d.inMilliseconds;
          waits.add(d.inMilliseconds);
        },
      );
      await rl.acquire(1000); // tokens start empty → wait 1s
      await rl.acquire(1000); // wait 1s
      expect(waits, [1000, 1000]);
      expect(now, 2000); // 2000 bytes over 2000ms = 1000 B/s
    });

    test('concurrent acquires share the cap (serialised, not each full-rate)', () async {
      var now = 0;
      final rl = RateLimiter(
        bytesPerSecond: 1000,
        clockMs: () => now,
        sleep: (d) async => now += d.inMilliseconds,
      );
      await Future.wait([rl.acquire(1000), rl.acquire(1000)]);
      expect(now, 2000); // queued behind each other, not 1000
    });

    test('an idle bucket lets a later chunk through without waiting', () async {
      var now = 0;
      final waits = <int>[];
      final rl = RateLimiter(
        bytesPerSecond: 1000,
        clockMs: () => now,
        sleep: (d) async {
          now += d.inMilliseconds;
          waits.add(d.inMilliseconds);
        },
      );
      await rl.acquire(500); // empty bucket → wait 500ms (now=500)
      now += 1000; // a second passes with no transfer → bucket refills
      await rl.acquire(500); // covered by refilled tokens → no wait
      expect(waits, [500]);
    });

    test('lifting the limit to 0 stops throttling', () async {
      final waits = <Duration>[];
      final rl = RateLimiter(bytesPerSecond: 1000, sleep: (d) async => waits.add(d));
      rl.bytesPerSecond = 0;
      await rl.acquire(1 << 20);
      expect(waits, isEmpty);
    });
  });

  group('TransferService throttling', () {
    test('a bandwidth cap slows the transfer to the rate', () async {
      var now = 0;
      final waits = <int>[];
      final limiter = RateLimiter(
        clockMs: () => now,
        sleep: (d) async {
          now += d.inMilliseconds;
          waits.add(d.inMilliseconds);
        },
      );
      final service = TransferService(limiter: limiter);

      final src = MemoryBackend(files: {'/big.bin': Uint8List(4000)});
      final dst = MemoryBackend();
      final t = Transfer(
        name: 'big.bin',
        route: 'test',
        direction: TransferDirection.upload,
        sizeBytes: 4000,
        session: 's',
      );

      await service.run(
        t: t,
        src: src,
        srcPath: '/big.bin',
        dst: dst,
        dstPath: '/big.bin',
        onStatus: () {},
        bytesPerSecond: 1000, // 1000 B/s
      );

      expect(t.status, TransferStatus.done);
      expect(waits, isNotEmpty, reason: 'throttling should have engaged');
      // 4000 bytes at 1000 B/s ⇒ ~4s of simulated waiting.
      expect(now, greaterThanOrEqualTo(3000));
      expect((await dst.list('/')).any((e) => e.name == 'big.bin'), isTrue);
    });

    test('no cap means no throttling delay', () async {
      var now = 0;
      final limiter = RateLimiter(clockMs: () => now, sleep: (d) async => now += d.inMilliseconds);
      final service = TransferService(limiter: limiter);

      final src = MemoryBackend(files: {'/f.bin': Uint8List(4000)});
      final dst = MemoryBackend();
      final t = Transfer(
        name: 'f.bin',
        route: 'test',
        direction: TransferDirection.upload,
        sizeBytes: 4000,
        session: 's',
      );

      await service.run(
        t: t,
        src: src,
        srcPath: '/f.bin',
        dst: dst,
        dstPath: '/f.bin',
        onStatus: () {},
        bytesPerSecond: null, // unlimited
      );

      expect(t.status, TransferStatus.done);
      expect(now, 0); // never slept
    });
  });
}
