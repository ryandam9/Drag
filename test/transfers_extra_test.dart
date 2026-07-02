import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/memory_backend.dart';
import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tick([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

  PaneController pane(StorageBackend b) => PaneController(backend: b, onChanged: () {});

  group('disposal', () {
    test('disposing mid-transfer aborts in-flight runs without throwing', () async {
      // A hand-built container so the test controls the dispose moment itself
      // (makeContainer would dispose again in teardown).
      final container = ProviderContainer();
      final q = container.read(transfersProvider.notifier)..setMaxThreads(2);
      final gated = _GatedSource();
      final src = pane(gated);
      final dst = pane(MemoryBackend());

      for (var i = 0; i < 3; i++) {
        q.enqueueFile(src, dst, '/f$i.bin', '/f$i.bin', 'f$i.bin', 128, announce: false);
      }
      await tick();
      final state = container.read(transfersProvider);
      expect(state.activeCount, 2);
      final active = state.transfers.firstWhere((t) => t.status == TransferStatus.active);
      final queued = state.transfers.firstWhere((t) => t.status == TransferStatus.queued);

      // Dispose while both runs are still mid-flight (blocked in the gate).
      expect(container.dispose, returnsNormally);
      // Idle transfers are released right away…
      expect(queued.touchLive, throwsA(isA<Object>()));
      // …but an in-flight one must NOT be disposed yet — its unwinding stream
      // may still tick the notifier. (Immediate disposal used to throw here.)
      expect(active.touchLive, returnsNormally);

      // Once the aborted run settles it disposes its own notifier.
      gated.release();
      var disposed = false;
      for (var i = 0; i < 200 && !disposed; i++) {
        await tick(10);
        try {
          active.touchLive();
        } catch (_) {
          disposed = true;
        }
      }
      expect(disposed, isTrue);
    });
  });

  group('pause / resume through the queue', () {
    test('pause keeps the staging partial and resume finishes from it', () async {
      final c = makeContainer();
      final q = c.read(transfersProvider.notifier);
      final srcDir = await Directory.systemTemp.createTemp('qpause_src');
      final dstDir = await Directory.systemTemp.createTemp('qpause_dst');
      addTearDown(() => srcDir.delete(recursive: true));
      addTearDown(() => dstDir.delete(recursive: true));
      final payload = List<int>.generate(4000, (i) => i % 256);
      await File(p.join(srcDir.path, 'src.bin')).writeAsBytes(payload);

      final stalling = _StallingLocal(stallAfter: 1000);
      final src = pane(stalling)..path = srcDir.path;
      final dst = pane(LocalBackend())..path = dstDir.path;
      final dstPath = p.join(dstDir.path, 'out.bin');

      q.enqueueFile(src, dst, p.join(srcDir.path, 'src.bin'), dstPath, 'out.bin', 4000,
          announce: false);
      // Wait until the run has streamed up to the stall point (mid-transfer).
      for (var i = 0; i < 200 && !stalling.stalled; i++) {
        await tick(10);
      }
      final t = c.read(transfersProvider).transfers.single;
      expect(t.status, TransferStatus.active);

      q.pause(t); // aborts the stream with the pause reason
      stalling.release(); // deliver the next chunk so the abort is observed
      for (var i = 0; i < 200 && !t.pausedWithPartial; i++) {
        await tick(10);
      }
      expect(t.status, TransferStatus.paused);
      final partial = File('$dstPath.drag-partial-${t.id}');
      expect(partial.existsSync(), isTrue, reason: 'pause must keep the partial');
      expect(partial.lengthSync(), greaterThan(0));

      q.resume(t);
      for (var i = 0; i < 300 && t.status != TransferStatus.done; i++) {
        await tick(10);
      }
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload);
      // The resume used a ranged read from the kept offset — the bytes before
      // the pause were never re-sent.
      expect(stalling.rangeStart, greaterThan(0));
      expect(partial.existsSync(), isFalse); // promoted to the final name
    });

    test('cancelling a paused transfer discards its kept partial', () async {
      final c = makeContainer();
      final q = c.read(transfersProvider.notifier);
      final srcDir = await Directory.systemTemp.createTemp('qcancel_src');
      final dstDir = await Directory.systemTemp.createTemp('qcancel_dst');
      addTearDown(() => srcDir.delete(recursive: true));
      addTearDown(() => dstDir.delete(recursive: true));
      await File(p.join(srcDir.path, 'src.bin'))
          .writeAsBytes(List<int>.generate(4000, (i) => i % 256));

      final stalling = _StallingLocal(stallAfter: 1000);
      final src = pane(stalling)..path = srcDir.path;
      final dst = pane(LocalBackend())..path = dstDir.path;
      final dstPath = p.join(dstDir.path, 'out.bin');

      q.enqueueFile(src, dst, p.join(srcDir.path, 'src.bin'), dstPath, 'out.bin', 4000,
          announce: false);
      for (var i = 0; i < 200 && !stalling.stalled; i++) {
        await tick(10);
      }
      final t = c.read(transfersProvider).transfers.single;
      q.pause(t);
      stalling.release();
      for (var i = 0; i < 200 && !t.pausedWithPartial; i++) {
        await tick(10);
      }
      final partial = File('$dstPath.drag-partial-${t.id}');
      expect(partial.existsSync(), isTrue);

      // Cancelling the paused transfer must clean up the partial it kept.
      q.cancel(t);
      for (var i = 0; i < 200 && partial.existsSync(); i++) {
        await tick(10);
      }
      expect(partial.existsSync(), isFalse);
      expect(c.read(transfersProvider).transfers, isEmpty);
    });
  });

  group('folder-walk batching', () {
    test('a big tree is published in slices, not one emission per file', () async {
      final c = makeContainer();
      final q = c.read(transfersProvider.notifier)..setMaxThreads(1);
      final gated = _GatedTree(files: 120);
      final src = pane(gated);
      final dst = pane(MemoryBackend());

      var emissions = 0;
      c.listen(transfersProvider, (_, _) => emissions++);

      final count = await q.enqueueTree(src, dst, const FileItem(name: 'folder', isDir: true));
      expect(count, 120);
      expect(c.read(transfersProvider).transfers.length, 120);
      // Batched: a handful of emissions (50-file slices plus scheduler status
      // changes) instead of a full-list copy + emission per enqueued file.
      expect(emissions, lessThan(20));
      gated.release(); // let the one active transfer settle before teardown
      await tick();
    });
  });
}

/// A source backend whose reads block until [release]d, so transfers stay
/// `active` while the test inspects or disposes the queue.
class _GatedSource extends MemoryBackend {
  _GatedSource()
      : super(files: {
          for (var i = 0; i < 5; i++) '/f$i.bin': Uint8List(128),
        });
  final _gate = Completer<void>();
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    await _gate.future;
    return super.openRead(path);
  }
}

/// A folder of [files] small files whose reads block until [release]d, so a
/// recursive enqueue can be observed without transfers racing to completion.
class _GatedTree extends MemoryBackend {
  _GatedTree({required int files})
      : super(dirs: {'/', '/folder'}, files: {
          for (var i = 0; i < files; i++) '/folder/f$i.bin': Uint8List(16),
        });
  final _gate = Completer<void>();
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    await _gate.future;
    return super.openRead(path);
  }
}

/// A [LocalBackend] whose read re-chunks the file and stalls after
/// [stallAfter] bytes until [release]d — keeping a transfer mid-stream so the
/// test can pause it with bytes already written. Ranged reads (the resume
/// path) record their offset and are not stalled.
class _StallingLocal extends LocalBackend {
  _StallingLocal({required this.stallAfter});
  final int stallAfter;
  final _gate = Completer<void>();
  bool stalled = false;
  int? rangeStart;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    final h = await super.openRead(path);
    Stream<Uint8List> chunks() async* {
      var sent = 0;
      await for (final c in h.stream) {
        for (var i = 0; i < c.length; i += 250) {
          final end = i + 250 < c.length ? i + 250 : c.length;
          yield Uint8List.sublistView(c, i, end);
          sent += end - i;
          if (sent >= stallAfter && !_gate.isCompleted) {
            stalled = true;
            await _gate.future;
          }
        }
      }
    }

    return ReadHandle(chunks(), h.length);
  }

  @override
  Future<ReadHandle> openReadRange(String path, int start) {
    rangeStart = start;
    return super.openReadRange(path, start);
  }
}
