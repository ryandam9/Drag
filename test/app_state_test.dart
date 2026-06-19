import 'dart:io';

import 'package:drag/fs/simulated_backend.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/data/history_db.dart';
import 'package:drag/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppState app;

  setUp(() {
    // Deterministic: no background ticker, no real-FS auto-refresh.
    app = AppState(tickEnabled: false, autoRefreshPanes: false);
  });
  tearDown(() => app.dispose());

  group('navigation', () {
    test('starts on browser; go() switches screen', () {
      expect(app.screen, AppScreen.browser);
      app.go(AppScreen.queue);
      expect(app.screen, AppScreen.queue);
    });

    test('selectConnection updates selection', () {
      final c = app.connections.last;
      app.selectConnection(c);
      expect(identical(app.selectedConnection, c), isTrue);
    });
  });

  group('transfer queue counts (seed data)', () {
    test('initial breakdown', () {
      expect(app.activeCount, 2);
      expect(app.queuedCount, 1);
      expect(app.pausedCount, 1);
      expect(app.errorCount, 1);
      expect(app.doneCount, 1);
    });

    test('pauseAll moves active+queued to paused', () {
      app.pauseAll();
      expect(app.activeCount, 0);
      expect(app.queuedCount, 0);
      expect(app.pausedCount, 4); // 1 existing + 2 active + 1 queued
    });

    test('resumeAll moves paused to queued', () {
      app.pauseAll();
      app.resumeAll();
      expect(app.pausedCount, 0);
      expect(app.queuedCount, 4);
    });

    test('clearDone removes completed transfers', () {
      final before = app.transfers.length;
      app.clearDone();
      expect(app.doneCount, 0);
      expect(app.transfers.length, before - 1);
    });

    test('togglePause flips a transfer between paused and queued', () {
      final t = app.transfers.firstWhere((t) => t.status == TransferStatus.active);
      app.togglePause(t);
      expect(t.status, TransferStatus.paused);
      app.togglePause(t);
      expect(t.status, TransferStatus.queued);
    });

    test('retry resets an errored transfer', () {
      final t = app.transfers.firstWhere((t) => t.status == TransferStatus.error);
      app.retry(t);
      expect(t.status, TransferStatus.queued);
      expect(t.errorMessage, isNull);
      expect(t.progress, 0);
    });

    test('setMaxThreads clamps to 1..16', () {
      app.setMaxThreads(100);
      expect(app.maxThreads, 16);
      app.setMaxThreads(0);
      expect(app.maxThreads, 1);
      app.setMaxThreads(4);
      expect(app.maxThreads, 4);
    });
  });

  group('toasts', () {
    test('pushToast appends a message with the right fields', () {
      final before = app.toasts.length;
      app.pushToast('Title', 'Sub', ToastKind.success);
      expect(app.toasts.length, before + 1);
      final t = app.toasts.last;
      expect(t.title, 'Title');
      expect(t.subtitle, 'Sub');
      expect(t.kind, ToastKind.success);
    });
  });

  group('simulated ticker (debugTick)', () {
    test('advances active simulated transfers and completes them', () {
      final t = app.transfers.firstWhere(
          (t) => t.status == TransferStatus.active && t.sizeBytes < 10 * 1024 * 1024);
      // Small file advances 0.18 per tick → completes within a few ticks.
      for (var i = 0; i < 10 && t.status == TransferStatus.active; i++) {
        app.debugTick();
      }
      expect(t.status, TransferStatus.done);
      expect(t.progress, 1.0);
    });

    test('promotes a queued transfer to active under the thread budget', () {
      // Pause the two active ones so the queued one gets promoted.
      final actives = app.transfers.where((t) => t.status == TransferStatus.active).toList();
      for (final a in actives) {
        a.status = TransferStatus.paused;
      }
      final queued = app.transfers.firstWhere((t) => t.status == TransferStatus.queued);
      app.debugTick();
      expect(queued.status, TransferStatus.active);
    });

    test('progress-only tick bumps the transfer liveTick, not the global notifier', () {
      // Isolate a single small active transfer; park everything else as done so
      // the tick neither promotes a queued one nor completes this one.
      final t = app.transfers.firstWhere(
          (t) => t.status == TransferStatus.active && t.sizeBytes < 10 * 1024 * 1024);
      for (final other in app.transfers) {
        if (!identical(other, t)) other.status = TransferStatus.done;
      }
      t.progress = 0; // ensure one 0.18 step stays below 1.0

      var globalNotifies = 0;
      app.addListener(() => globalNotifies++);
      final tickBefore = t.liveTick.value;

      app.debugTick();

      expect(t.progress, greaterThan(0)); // advanced
      expect(t.progress, lessThan(1));
      expect(t.liveTick.value, tickBefore + 1); // local repaint fired
      expect(globalNotifies, 0); // file tables / counts did NOT rebuild
    });

    test('completing a transfer DOES fire the global notifier', () {
      final t = app.transfers.firstWhere(
          (t) => t.status == TransferStatus.active && t.sizeBytes < 10 * 1024 * 1024);
      for (final other in app.transfers) {
        if (!identical(other, t)) other.status = TransferStatus.done;
      }
      t.progress = 0.95; // one step tips it over → status change

      var globalNotifies = 0;
      app.addListener(() => globalNotifies++);
      app.debugTick();

      expect(t.status, TransferStatus.done);
      expect(globalNotifies, greaterThan(0));
    });
  });

  group('endpoints', () {
    test('setPaneEndpoint to Local and to S3 connection', () async {
      await app.setPaneEndpoint(true, null);
      expect(app.leftPane.kind, EndpointKind.local);

      final s3 = app.connections.firstWhere((c) => c.isS3);
      await app.setPaneEndpoint(false, s3);
      expect(app.rightPane.kind, EndpointKind.s3);
      expect(identical(app.rightPane.connection, s3), isTrue);
      expect(app.rightPane.isReady, isFalse); // no creds yet
    });

    test('connect() flags S3 online only with credentials', () async {
      final s3 = app.connections.firstWhere((c) => c.isS3);
      await app.connect(s3);
      expect(s3.online, isFalse);
      expect(app.toasts.last.kind, ToastKind.error);

      s3
        ..accessKeyId = 'AKIA'
        ..secretAccessKey = 'sec'
        ..bucket = 'b'
        ..endpoint = '127.0.0.1:1'; // fail fast: don't hit real AWS in tests
      await app.connect(s3);
      expect(s3.online, isTrue);
      expect(app.toasts.last.kind, ToastKind.info);
    });

    test('connect() marks SFTP connections online', () async {
      final sftp = app.connections.firstWhere((c) => c.kind == EndpointKind.sftp)
        // Point at a closed local port so the background SFTP connect fails
        // fast (this test only asserts the synchronous online flag).
        ..host = '127.0.0.1'
        ..port = 1;
      await app.connect(sftp);
      expect(sftp.online, isTrue);
    });
  });

  group('file operations (focused pane, real local dir)', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fs_ops');
      await File(p.join(dir.path, 'a.txt')).writeAsString('a');
      app.leftPane
        ..backend = LocalBackend()
        ..path = dir.path;
      await app.leftPane.refresh();
      app.focusPane(true);
    });
    tearDown(() => dir.delete(recursive: true));

    test('createFolder makes a real directory and refreshes', () async {
      await app.createFolder(app.leftPane, 'docs');
      expect(await Directory(p.join(dir.path, 'docs')).exists(), isTrue);
      expect(app.leftPane.items.any((e) => e.name == 'docs'), isTrue);
    });

    test('renameItem renames the file on disk', () async {
      final item = app.leftPane.items.firstWhere((e) => e.name == 'a.txt');
      await app.renameItem(app.leftPane, item, 'b.txt');
      expect(await File(p.join(dir.path, 'a.txt')).exists(), isFalse);
      expect(await File(p.join(dir.path, 'b.txt')).exists(), isTrue);
    });

    test('deleteItem deletes the file', () async {
      final item = app.leftPane.items.firstWhere((e) => e.name == 'a.txt');
      await app.deleteItem(app.leftPane, item);
      expect(await File(p.join(dir.path, 'a.txt')).exists(), isFalse);
    });

    test('deleteItems removes multiple files', () async {
      await File(p.join(dir.path, 'c.txt')).writeAsString('c');
      await app.leftPane.refresh();
      final items = app.leftPane.items.where((e) => e.name == 'a.txt' || e.name == 'c.txt').toList();
      expect(items.length, 2);
      await app.deleteItems(app.leftPane, items);
      expect(await File(p.join(dir.path, 'a.txt')).exists(), isFalse);
      expect(await File(p.join(dir.path, 'c.txt')).exists(), isFalse);
    });

    test('focusedPane follows focusPane', () {
      app.focusPane(false);
      expect(identical(app.focusedPane, app.rightPane), isTrue);
      app.focusPane(true);
      expect(identical(app.focusedPane, app.leftPane), isTrue);
    });

    test('createFolder on a read-only backend reports an error', () async {
      app.leftPane.backend = SimulatedBackend(Connection(name: 'd', protocol: Protocol.sftp));
      await app.createFolder(app.leftPane, 'x');
      expect(app.toasts.last.kind, ToastKind.error);
    });
  });

  group('sessions / tabs', () {
    test('starts with one session for the first S3 account', () {
      expect(app.sessions.length, 1);
      expect(app.activeSession.connection!.isS3, isTrue);
      expect(app.leftPane, same(app.activeSession.left));
      expect(app.rightPane, same(app.activeSession.right));
    });

    // Use the second (credential-less) S3 account so opening a tab doesn't hit
    // the network on refresh (S3 without creds short-circuits).
    Connection secondConn() =>
        app.connections.firstWhere((c) => c.isS3 && c.name.startsWith('s3-archive'));

    test('openSession adds a tab and focuses it', () {
      final conn = secondConn();
      final s = app.openSession(conn);
      expect(app.sessions.length, 2);
      expect(app.activeSessionId, s.id);
      expect(app.activeSession.title, conn.name);
    });

    test('openSession focuses the existing tab for the same connection', () {
      final conn = secondConn();
      final first = app.openSession(conn);
      final again = app.openSession(conn);
      expect(app.sessions.length, 2); // not 3
      expect(again.id, first.id);
    });

    test('switchSession changes the active tab (and panes)', () {
      final initialId = app.activeSessionId;
      app.openSession(secondConn());
      app.switchSession(initialId);
      expect(app.activeSessionId, initialId);
      expect(app.rightPane, same(app.activeSession.right));
    });

    test('closeSession removes a tab and re-points active', () {
      final s = app.openSession(secondConn());
      app.closeSession(s.id);
      expect(app.sessions.any((x) => x.id == s.id), isFalse);
      expect(app.sessions.length, 1);
    });

    test('closing the last tab leaves a fresh Local session', () {
      // Close down to nothing → a Local tab is recreated.
      while (app.sessions.length > 1) {
        app.closeSession(app.sessions.first.id);
      }
      app.closeSession(app.activeSessionId);
      expect(app.sessions.length, 1);
      expect(app.activeSession.connection, isNull); // Local
      expect(app.activeSession.title, 'Local');
    });
  });

  group('dropTransfer decisions', () {
    test('ignores a drop onto the same pane', () {
      final before = app.transfers.length;
      app.dropTransfer(const DragPayload(_file, true), true);
      expect(app.transfers.length, before);
    });

    test('rejects directory drops with an info toast', () {
      final before = app.transfers.length;
      app.dropTransfer(const DragPayload(_dir, true), false);
      expect(app.transfers.length, before);
      expect(app.toasts.last.kind, ToastKind.info);
    });

    test('rejects when destination endpoint is not ready', () async {
      // Left = local (ready), right = S3 without creds (not ready).
      await app.setPaneEndpoint(true, null);
      final s3 = app.connections.firstWhere((c) => c.isS3);
      await app.setPaneEndpoint(false, s3);
      final before = app.transfers.length;
      app.dropTransfer(const DragPayload(_file, true), false);
      expect(app.transfers.length, before);
      expect(app.toasts.last.kind, ToastKind.error);
    });

    test('a non-transferring (demo) backend produces a simulated, non-live transfer', () async {
      await app.setPaneEndpoint(true, null); // local ready
      // Right pane: a demo backend that can't move real bytes.
      app.rightPane
        ..backend = SimulatedBackend(Connection(name: 'demo', protocol: Protocol.sftp, remotePath: '/srv'))
        ..connection = Connection(name: 'demo', protocol: Protocol.sftp);
      await app.rightPane.refresh();
      final before = app.transfers.length;
      app.dropTransfer(const DragPayload(_file, true), false);
      expect(app.transfers.length, before + 1);
      final t = app.transfers.first;
      expect(t.live, isFalse);
      expect(t.status, TransferStatus.queued);
      expect(t.direction, TransferDirection.upload);
    });

    test('Local→Local creates a real (live) transfer that completes', () async {
      final src = await Directory.systemTemp.createTemp('drop_src');
      final dst = await Directory.systemTemp.createTemp('drop_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'payload.bin')).writeAsBytes(List.filled(4096, 9));

      app.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await app.leftPane.refresh();
      app.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await app.rightPane.refresh();

      final item = app.leftPane.items.firstWhere((e) => e.name == 'payload.bin');
      app.dropTransfer(DragPayload(item, true), false);

      final t = app.transfers.first;
      expect(t.live, isTrue);

      // Wait for the streamed copy to finish.
      for (var i = 0; i < 100 && t.status != TransferStatus.done && t.status != TransferStatus.error; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(p.join(dst.path, 'payload.bin')).readAsBytes(), List.filled(4096, 9));
    });

    test('dropping a multi-selection transfers every selected file', () async {
      final src = await Directory.systemTemp.createTemp('drop_msrc');
      final dst = await Directory.systemTemp.createTemp('drop_mdst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'f1.bin')).writeAsBytes(List.filled(1024, 1));
      await File(p.join(src.path, 'f2.bin')).writeAsBytes(List.filled(2048, 2));

      app.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await app.leftPane.refresh();
      app.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await app.rightPane.refresh();

      for (var i = 0; i < app.leftPane.items.length; i++) {
        final f = app.leftPane.items[i];
        if (f.name == 'f1.bin' || f.name == 'f2.bin') app.leftPane.toggleSelect(i);
      }
      final dragged = app.leftPane.items.firstWhere((e) => e.name == 'f1.bin');
      app.dropTransfer(DragPayload(dragged, true), false);

      expect(app.transfers.where((t) => t.name == 'f1.bin' || t.name == 'f2.bin').length, 2);

      for (var i = 0; i < 200; i++) {
        final pending = app.transfers
            .where((t) => t.live && t.status != TransferStatus.done && t.status != TransferStatus.error);
        if (pending.isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await File(p.join(dst.path, 'f1.bin')).exists(), isTrue);
      expect(await File(p.join(dst.path, 'f2.bin')).exists(), isTrue);
    });
  });

  group('history recording', () {
    test('a completed simulated transfer is written to history', () async {
      final repo = await HistoryRepository.open(inMemoryDatabasePath);
      addTearDown(repo.close);
      final withDb = AppState(tickEnabled: false, autoRefreshPanes: false, history: repo);
      addTearDown(withDb.dispose);

      expect(withDb.hasHistoryDb, isTrue);

      final t = withDb.transfers.firstWhere(
          (t) => t.status == TransferStatus.active && t.sizeBytes < 10 * 1024 * 1024);
      for (var i = 0; i < 10 && t.status == TransferStatus.active; i++) {
        withDb.debugTick();
      }
      expect(t.status, TransferStatus.done);

      // _record runs asynchronously; let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(withDb.history, isNotEmpty);
      expect(withDb.historyStats.total, greaterThanOrEqualTo(1));
      expect(withDb.history.any((r) => r.name == t.name), isTrue);
    });
  });
}

/// Minimal const FileItems for drop-decision tests.
const _file = FileItem(name: 'note.txt', sizeBytes: 10);
const _dir = FileItem(name: 'folder', isDir: true);
