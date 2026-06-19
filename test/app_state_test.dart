import 'dart:io';

import 'package:filesync/fs/storage_backend.dart';
import 'package:filesync/models/connection.dart';
import 'package:filesync/models/file_item.dart';
import 'package:filesync/models/transfer.dart';
import 'package:filesync/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
        ..bucket = 'b';
      await app.connect(s3);
      expect(s3.online, isTrue);
      expect(app.toasts.last.kind, ToastKind.info);
    });

    test('connect() marks SFTP connections online', () async {
      final sftp = app.connections.firstWhere((c) => c.kind == EndpointKind.sftp);
      await app.connect(sftp);
      expect(sftp.online, isTrue);
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

    test('SFTP endpoint produces a simulated (non-live) queued transfer', () async {
      await app.setPaneEndpoint(true, null); // local ready
      final sftp = app.connections.firstWhere((c) => c.kind == EndpointKind.sftp);
      await app.setPaneEndpoint(false, sftp); // simulated, ready
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
  });
}

/// Minimal const FileItems for drop-decision tests.
const _file = FileItem(name: 'note.txt', sizeBytes: 10);
const _dir = FileItem(name: 'folder', isDir: true);
