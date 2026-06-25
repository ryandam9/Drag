import 'dart:async';
import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_backend.dart';
import 'support/harness.dart';

/// A source backend whose reads block until [release]d, so transfers stay
/// `active` and we can observe how many the scheduler runs concurrently.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tick([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

  PaneController pane(StorageBackend b) => PaneController(backend: b, onChanged: () {});

  void enqueueN(TransfersNotifier q, PaneController src, PaneController dst, int n) {
    for (var i = 0; i < n; i++) {
      q.enqueueFile(src, dst, '/f$i.bin', '/f$i.bin', 'f$i.bin', 128, announce: false);
    }
  }

  test('runs at most maxThreads transfers at once, queuing the rest', () async {
    final c = makeContainer();
    final q = c.read(transfersProvider.notifier)..setMaxThreads(2);
    final gated = _GatedSource();
    final src = pane(gated);
    final dst = pane(MemoryBackend());

    enqueueN(q, src, dst, 4);
    await tick();

    // Only two run; the other two wait.
    expect(c.read(transfersProvider).activeCount, 2);
    expect(c.read(transfersProvider).queuedCount, 2);

    // Releasing lets them all drain through the 2-wide gate.
    gated.release();
    for (var i = 0; i < 200 && c.read(transfersProvider).doneCount < 4; i++) {
      await tick(10);
    }
    expect(c.read(transfersProvider).doneCount, 4);
    expect(c.read(transfersProvider).activeCount, 0);
  });

  test('raising the limit starts more queued transfers immediately', () async {
    final c = makeContainer();
    final q = c.read(transfersProvider.notifier)..setMaxThreads(1);
    final gated = _GatedSource();
    final src = pane(gated);
    final dst = pane(MemoryBackend());

    enqueueN(q, src, dst, 3);
    await tick();
    expect(c.read(transfersProvider).activeCount, 1);
    expect(c.read(transfersProvider).queuedCount, 2);

    q.setMaxThreads(3); // a third slot... two more should start
    await tick();
    expect(c.read(transfersProvider).activeCount, 3);
    expect(c.read(transfersProvider).queuedCount, 0);

    gated.release();
    for (var i = 0; i < 200 && c.read(transfersProvider).doneCount < 3; i++) {
      await tick(10);
    }
    expect(c.read(transfersProvider).doneCount, 3);
  });

  test('a paused active transfer frees a slot for a queued one', () async {
    final c = makeContainer();
    final q = c.read(transfersProvider.notifier)..setMaxThreads(1);
    final gated = _GatedSource();
    final src = pane(gated);
    final dst = pane(MemoryBackend());

    enqueueN(q, src, dst, 2);
    await tick();
    final state = c.read(transfersProvider);
    expect(state.activeCount, 1);
    expect(state.queuedCount, 1);

    // Pause the active one → the queued one should take the freed slot.
    final active = state.transfers.firstWhere((t) => t.status == TransferStatus.active);
    q.pause(active);
    await tick();
    expect(c.read(transfersProvider).activeCount, 1);
    expect(c.read(transfersProvider).pausedCount, 1);
  });
}
