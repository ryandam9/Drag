import 'dart:io';

import 'package:drag/data/history_db.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_remote_backend.dart';
import 'support/harness.dart';

const _mB = 1024 * 1024;

List<Transfer> _seedTransfers() => [
      Transfer(name: 'big.tar.gz', route: 'r', direction: TransferDirection.upload, sizeBytes: 248 * _mB, session: 's', status: TransferStatus.active, speed: '1.4 MB/s'),
      Transfer(name: 'config.yaml', route: 'r', direction: TransferDirection.upload, sizeBytes: 4096, session: 's', status: TransferStatus.active),
      Transfer(name: 'deploy.sh', route: 'r', direction: TransferDirection.upload, sizeBytes: 1800, session: 's', status: TransferStatus.queued),
      Transfer(name: 'dist.zip', route: 'r', direction: TransferDirection.upload, sizeBytes: 35 * _mB, session: 's', status: TransferStatus.paused),
      Transfer(name: '.env', route: 'r', direction: TransferDirection.upload, sizeBytes: 512, session: 's', status: TransferStatus.error, errorMessage: 'denied'),
      Transfer(name: 'server.js', route: 'r', direction: TransferDirection.download, sizeBytes: 22000, session: 's', status: TransferStatus.done),
    ];

void main() {
  group('navigation', () {
    test('starts on browser; go() switches screen', () {
      final c = makeContainer();
      expect(c.read(navProvider), AppScreen.browser);
      c.read(navProvider.notifier).go(AppScreen.queue);
      expect(c.read(navProvider), AppScreen.queue);
    });

    test('selectConnection updates selection', () {
      final c = makeContainer(connections: sampleConnections());
      final conn = c.read(connectionsProvider).connections.last;
      c.read(connectionsProvider.notifier).select(conn);
      expect(identical(c.read(connectionsProvider).selected, conn), isTrue);
    });

    test('connections start empty on a fresh install', () {
      final c = makeContainer();
      expect(c.read(connectionsProvider).connections, isEmpty);
      expect(c.read(connectionsProvider).selected, isNull);
    });
  });

  group('transfer queue controls', () {
    late ProviderContainer c;
    late TransfersNotifier q;
    setUp(() {
      c = makeContainer();
      q = c.read(transfersProvider.notifier)..debugSetTransfers(_seedTransfers());
    });

    TransfersState state() => c.read(transfersProvider);

    test('initial breakdown', () {
      expect(state().activeCount, 2);
      expect(state().queuedCount, 1);
      expect(state().pausedCount, 1);
      expect(state().errorCount, 1);
      expect(state().doneCount, 1);
    });

    test('queue starts empty without seeding', () {
      final c2 = makeContainer();
      expect(c2.read(transfersProvider).transfers, isEmpty);
    });

    test('pauseAll moves active+queued to paused', () {
      q.pauseAll();
      expect(state().activeCount, 0);
      expect(state().queuedCount, 0);
      expect(state().pausedCount, 4);
    });

    test('resumeAll moves paused to queued', () {
      q.pauseAll();
      q.resumeAll();
      expect(state().pausedCount, 0);
      expect(state().queuedCount, 4);
    });

    test('clearDone removes completed transfers', () {
      final before = state().transfers.length;
      q.clearDone();
      expect(state().doneCount, 0);
      expect(state().transfers.length, before - 1);
    });

    test('togglePause flips a transfer between paused and queued', () {
      final t = state().transfers.firstWhere((t) => t.status == TransferStatus.active);
      q.togglePause(t);
      expect(t.status, TransferStatus.paused);
      q.togglePause(t);
      expect(t.status, TransferStatus.queued);
    });

    test('retry resets an errored transfer', () {
      final t = state().transfers.firstWhere((t) => t.status == TransferStatus.error);
      q.retry(t);
      expect(t.status, TransferStatus.queued);
      expect(t.errorMessage, isNull);
      expect(t.progress, 0);
    });

    test('setMaxThreads clamps to 1..16', () {
      q.setMaxThreads(100);
      expect(state().maxThreads, 16);
      q.setMaxThreads(0);
      expect(state().maxThreads, 1);
      q.setMaxThreads(4);
      expect(state().maxThreads, 4);
    });
  });

  group('toasts', () {
    test('push appends a message with the right fields', () {
      final c = makeContainer();
      c.read(toastsProvider.notifier).push('Title', 'Sub', ToastKind.success);
      final toasts = c.read(toastsProvider);
      expect(toasts.length, 1);
      expect(toasts.last.title, 'Title');
      expect(toasts.last.subtitle, 'Sub');
      expect(toasts.last.kind, ToastKind.success);
    });
  });

  group('endpoints', () {
    test('setPaneEndpoint to Local and to S3 connection', () async {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      await s.setPaneEndpoint(true, null);
      expect(s.leftPane.kind, EndpointKind.local);

      final s3 = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      await s.setPaneEndpoint(false, s3);
      expect(s.rightPane.kind, EndpointKind.s3);
      expect(identical(s.rightPane.connection, s3), isTrue);
      expect(s.rightPane.isReady, isFalse); // no creds yet
    });

    test('connect() flags S3 online only with credentials', () async {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      final s3 = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      await s.connect(s3);
      expect(s3.online, isFalse);
      expect(c.read(toastsProvider).last.kind, ToastKind.error);

      s3
        ..accessKeyId = 'AKIA'
        ..secretAccessKey = 'sec'
        ..bucket = 'b'
        ..endpoint = '127.0.0.1:1';
      await s.connect(s3);
      expect(s3.online, isTrue);
      expect(c.read(toastsProvider).last.kind, ToastKind.info);
    });

    test('connect() marks SFTP connections online', () async {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      final sftp = c.read(connectionsProvider).connections.firstWhere((x) => x.kind == EndpointKind.sftp)
        ..host = '127.0.0.1'
        ..port = 1;
      await s.connect(sftp);
      expect(sftp.online, isTrue);
    });
  });

  group('file operations (focused pane, real local dir)', () {
    late ProviderContainer c;
    late SessionsNotifier s;
    late Directory dir;
    setUp(() async {
      c = makeContainer();
      s = c.read(sessionsProvider.notifier);
      dir = await Directory.systemTemp.createTemp('fs_ops');
      await File(p.join(dir.path, 'a.txt')).writeAsString('a');
      s.leftPane
        ..backend = LocalBackend()
        ..path = dir.path;
      await s.leftPane.refresh();
      s.focusPane(true);
    });
    tearDown(() => dir.delete(recursive: true));

    test('createFolder makes a real directory and refreshes', () async {
      await s.createFolder(s.leftPane, 'docs');
      expect(await Directory(p.join(dir.path, 'docs')).exists(), isTrue);
      expect(s.leftPane.items.any((e) => e.name == 'docs'), isTrue);
    });

    test('renameItem renames the file on disk', () async {
      final item = s.leftPane.items.firstWhere((e) => e.name == 'a.txt');
      await s.renameItem(s.leftPane, item, 'b.txt');
      expect(await File(p.join(dir.path, 'a.txt')).exists(), isFalse);
      expect(await File(p.join(dir.path, 'b.txt')).exists(), isTrue);
    });

    test('deleteItems removes multiple files', () async {
      await File(p.join(dir.path, 'c.txt')).writeAsString('c');
      await s.leftPane.refresh();
      final items = s.leftPane.items.where((e) => e.name == 'a.txt' || e.name == 'c.txt').toList();
      expect(items.length, 2);
      await s.deleteItems(s.leftPane, items);
      expect(await File(p.join(dir.path, 'a.txt')).exists(), isFalse);
      expect(await File(p.join(dir.path, 'c.txt')).exists(), isFalse);
    });

    test('createFolder on a read-only backend reports an error', () async {
      s.leftPane.backend = FakeRemoteBackend(Connection(name: 'd', protocol: Protocol.sftp));
      await s.createFolder(s.leftPane, 'x');
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
    });
  });

  group('sessions / tabs', () {
    test('starts with one Local session', () {
      final c = makeContainer();
      final state = c.read(sessionsProvider);
      expect(state.sessions.length, 1);
      final s = c.read(sessionsProvider.notifier);
      expect(s.activeSession.connection, isNull);
      expect(s.activeSession.title, 'Local');
    });

    test('openSession adds a tab and focuses it', () {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      final conn = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      final opened = s.openSession(conn);
      expect(c.read(sessionsProvider).sessions.length, 2);
      expect(c.read(sessionsProvider).activeSessionId, opened.id);
      expect(s.activeSession.title, conn.name);
    });

    test('openSession focuses the existing tab for the same connection', () {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      final conn = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      final first = s.openSession(conn);
      final again = s.openSession(conn);
      expect(c.read(sessionsProvider).sessions.length, 2); // not 3
      expect(again.id, first.id);
    });

    test('closeSession removes a tab and re-points active', () {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      final conn = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      final opened = s.openSession(conn);
      s.closeSession(opened.id);
      expect(c.read(sessionsProvider).sessions.any((x) => x.id == opened.id), isFalse);
      expect(c.read(sessionsProvider).sessions.length, 1);
    });

    test('closing the last tab leaves a fresh Local session', () {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      s.closeSession(c.read(sessionsProvider).activeSessionId);
      expect(c.read(sessionsProvider).sessions.length, 1);
      expect(s.activeSession.connection, isNull);
      expect(s.activeSession.title, 'Local');
    });
  });

  group('dropTransfer decisions', () {
    test('ignores a drop onto the same pane', () {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      s.dropTransfer(const DragPayload(_file, true), true);
      expect(c.read(transfersProvider).transfers, isEmpty);
    });

    test('directory drops transfer the whole tree recursively (Local→Local)', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('drop_tree_src');
      final dst = await Directory.systemTemp.createTemp('drop_tree_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      // folder/a.txt, folder/sub/b.txt, folder/empty/
      final folder = Directory(p.join(src.path, 'folder'))..createSync();
      await File(p.join(folder.path, 'a.txt')).writeAsString('aaa');
      final sub = Directory(p.join(folder.path, 'sub'))..createSync();
      await File(p.join(sub.path, 'b.txt')).writeAsString('bbb');
      Directory(p.join(folder.path, 'empty')).createSync();

      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      final item = s.leftPane.items.firstWhere((e) => e.name == 'folder');
      s.dropTransfer(DragPayload(item, true), false);

      // enqueueTree walks asynchronously, then the file transfers run.
      final aFile = File(p.join(dst.path, 'folder', 'a.txt'));
      final bFile = File(p.join(dst.path, 'folder', 'sub', 'b.txt'));
      for (var i = 0; i < 200 && !(aFile.existsSync() && bFile.existsSync()); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await aFile.readAsString(), 'aaa');
      expect(await bFile.readAsString(), 'bbb');
      // Empty subdirectories are recreated too.
      expect(Directory(p.join(dst.path, 'folder', 'empty')).existsSync(), isTrue);
      // Two files were enqueued.
      expect(c.read(transfersProvider).transfers.length, 2);
    });

    test('importFiles uploads OS files and folders into the destination pane', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final ext = await Directory.systemTemp.createTemp('os_ext'); // simulated OS files
      final dst = await Directory.systemTemp.createTemp('os_dst');
      addTearDown(() => ext.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(ext.path, 'f.txt')).writeAsString('F');
      final folder = Directory(p.join(ext.path, 'fold'))..createSync();
      await File(p.join(folder.path, 'g.txt')).writeAsString('G');

      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      c.read(transfersProvider.notifier)
          .importFiles(s.rightPane, [p.join(ext.path, 'f.txt'), folder.path]);

      final f = File(p.join(dst.path, 'f.txt'));
      final g = File(p.join(dst.path, 'fold', 'g.txt'));
      for (var i = 0; i < 200 && !(f.existsSync() && g.existsSync()); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await f.readAsString(), 'F');
      expect(await g.readAsString(), 'G');
    });

    // Sets up Local→Local panes where the destination already holds a file of
    // the same name, with a conflict resolver returning [action].
    Future<(SessionsNotifier, Directory)> _conflictSetup(
        ProviderContainer c, ConflictAction action) async {
      final s = c.read(sessionsProvider.notifier);
      c
          .read(transfersProvider.notifier)
          .setConflictResolver((_) async => ConflictResolution(action));
      final src = await Directory.systemTemp.createTemp('cf_src');
      final dst = await Directory.systemTemp.createTemp('cf_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'dup.txt')).writeAsString('SRC');
      await File(p.join(dst.path, 'dup.txt')).writeAsString('DST');
      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();
      return (s, dst);
    }

    test('conflict: Skip leaves the destination untouched and enqueues nothing', () async {
      final c = makeContainer();
      final (s, dst) = await _conflictSetup(c, ConflictAction.skip);
      final item = s.leftPane.items.firstWhere((e) => e.name == 'dup.txt');
      s.dropTransfer(DragPayload(item, true), false);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.read(transfersProvider).transfers, isEmpty);
      expect(await File(p.join(dst.path, 'dup.txt')).readAsString(), 'DST');
    });

    test('conflict: Overwrite replaces the destination file', () async {
      final c = makeContainer();
      final (s, dst) = await _conflictSetup(c, ConflictAction.overwrite);
      final item = s.leftPane.items.firstWhere((e) => e.name == 'dup.txt');
      s.dropTransfer(DragPayload(item, true), false);
      final f = File(p.join(dst.path, 'dup.txt'));
      for (var i = 0; i < 200 && (await f.readAsString()) != 'SRC'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await f.readAsString(), 'SRC');
    });

    test('conflict: Rename writes a non-colliding copy and keeps the original', () async {
      final c = makeContainer();
      final (s, dst) = await _conflictSetup(c, ConflictAction.rename);
      final item = s.leftPane.items.firstWhere((e) => e.name == 'dup.txt');
      s.dropTransfer(DragPayload(item, true), false);
      final renamed = File(p.join(dst.path, 'dup (1).txt'));
      for (var i = 0; i < 200 && !renamed.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await renamed.readAsString(), 'SRC');
      expect(await File(p.join(dst.path, 'dup.txt')).readAsString(), 'DST');
    });

    test('auto-retries a transient failure and then succeeds', () async {
      final c = makeContainer();
      c.read(transfersProvider.notifier).backoffFor = (_) => Duration.zero;
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('rt_src');
      final dst = await Directory.systemTemp.createTemp('rt_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'x.bin')).writeAsBytes(List.filled(512, 7));

      final flaky = _FlakyLocal()..failsLeft = 2; // fail first 2 reads, succeed on the 3rd
      s.leftPane
        ..backend = flaky
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      final item = s.leftPane.items.firstWhere((e) => e.name == 'x.bin');
      s.dropTransfer(DragPayload(item, true), false);

      // Transient errors (attempts < max) shouldn't end the poll — only a
      // success or an exhausted failure is terminal.
      Transfer? t;
      for (var i = 0; i < 300; i++) {
        final list = c.read(transfersProvider).transfers;
        t = list.isEmpty ? null : list.first;
        if (t != null &&
            (t.status == TransferStatus.done ||
                (t.status == TransferStatus.error && t.attempts >= TransfersNotifier.maxAttempts))) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t!.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(t.attempts, 3);
      expect(File(p.join(dst.path, 'x.bin')).existsSync(), isTrue);
    });

    test('manual retry re-runs an exhausted transfer', () async {
      final c = makeContainer();
      final n = c.read(transfersProvider.notifier)..backoffFor = (_) => Duration.zero;
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('mr_src');
      final dst = await Directory.systemTemp.createTemp('mr_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'x.bin')).writeAsBytes(List.filled(512, 7));

      final flaky = _FlakyLocal()..failsLeft = 99; // fail every attempt for now
      s.leftPane
        ..backend = flaky
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      final item = s.leftPane.items.firstWhere((e) => e.name == 'x.bin');
      s.dropTransfer(DragPayload(item, true), false);

      Transfer? t;
      for (var i = 0; i < 300; i++) {
        final list = c.read(transfersProvider).transfers;
        t = list.isEmpty ? null : list.first;
        if (t != null && t.status == TransferStatus.error && t.attempts >= TransfersNotifier.maxAttempts) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t!.status, TransferStatus.error);
      expect(t.attempts, TransfersNotifier.maxAttempts);

      // Fix the source and retry manually.
      flaky.failsLeft = 0;
      n.retry(t);
      for (var i = 0; i < 300 && t.status != TransferStatus.done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(File(p.join(dst.path, 'x.bin')).existsSync(), isTrue);
    });

    test('rejects when destination endpoint is not ready', () async {
      final c = makeContainer(connections: sampleConnections());
      final s = c.read(sessionsProvider.notifier);
      await s.setPaneEndpoint(true, null);
      final s3 = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      await s.setPaneEndpoint(false, s3);
      s.dropTransfer(const DragPayload(_file, true), false);
      expect(c.read(transfersProvider).transfers, isEmpty);
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
    });

    test('a non-transferring backend is rejected with an error toast', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      await s.setPaneEndpoint(true, null); // local ready
      s.rightPane
        ..backend = FakeRemoteBackend(Connection(name: 'demo', protocol: Protocol.sftp, remotePath: '/srv'))
        ..connection = Connection(name: 'demo', protocol: Protocol.sftp);
      await s.rightPane.refresh();
      s.dropTransfer(const DragPayload(_file, true), false);
      expect(c.read(transfersProvider).transfers, isEmpty);
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
    });

    test('Local→Local creates a real (live) transfer that completes', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('drop_src');
      final dst = await Directory.systemTemp.createTemp('drop_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'payload.bin')).writeAsBytes(List.filled(4096, 9));

      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      final item = s.leftPane.items.firstWhere((e) => e.name == 'payload.bin');
      s.dropTransfer(DragPayload(item, true), false);

      final t = c.read(transfersProvider).transfers.first;
      expect(t.live, isTrue);

      for (var i = 0; i < 100 && t.status != TransferStatus.done && t.status != TransferStatus.error; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(p.join(dst.path, 'payload.bin')).readAsBytes(), List.filled(4096, 9));
    });

    test('dropping a multi-selection transfers every selected file', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('drop_msrc');
      final dst = await Directory.systemTemp.createTemp('drop_mdst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'f1.bin')).writeAsBytes(List.filled(1024, 1));
      await File(p.join(src.path, 'f2.bin')).writeAsBytes(List.filled(2048, 2));

      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      for (var i = 0; i < s.leftPane.items.length; i++) {
        final f = s.leftPane.items[i];
        if (f.name == 'f1.bin' || f.name == 'f2.bin') s.leftPane.toggleSelect(i);
      }
      final dragged = s.leftPane.items.firstWhere((e) => e.name == 'f1.bin');
      s.dropTransfer(DragPayload(dragged, true), false);

      // dropTransfer enqueues asynchronously now (it resolves conflicts first).
      int selectedCount() =>
          c.read(transfersProvider).transfers.where((t) => t.name == 'f1.bin' || t.name == 'f2.bin').length;
      for (var i = 0; i < 100 && selectedCount() < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(selectedCount(), 2);

      for (var i = 0; i < 200; i++) {
        final pending = c.read(transfersProvider).transfers
            .where((t) => t.live && t.status != TransferStatus.done && t.status != TransferStatus.error);
        if (pending.isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await File(p.join(dst.path, 'f1.bin')).exists(), isTrue);
      expect(await File(p.join(dst.path, 'f2.bin')).exists(), isTrue);
    });
  });

  group('history recording', () {
    test('a completed real transfer is written to history', () async {
      final repo = await HistoryRepository.open(inMemoryDatabasePath);
      addTearDown(repo.close);
      final c = makeContainer(history: repo);
      final s = c.read(sessionsProvider.notifier);

      final src = await Directory.systemTemp.createTemp('hist_src');
      final dst = await Directory.systemTemp.createTemp('hist_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'rec.bin')).writeAsBytes(List.filled(2048, 5));

      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();

      final item = s.leftPane.items.firstWhere((e) => e.name == 'rec.bin');
      s.dropTransfer(DragPayload(item, true), false);

      final t = c.read(transfersProvider).transfers.first;
      for (var i = 0; i < 200 && t.status != TransferStatus.done && t.status != TransferStatus.error; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');

      // record runs asynchronously; let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(historyProvider).records, isNotEmpty);
      expect(c.read(historyProvider).records.any((r) => r.name == 'rec.bin'), isTrue);
    });
  });
}

/// Minimal const FileItems for drop-decision tests.
const _file = FileItem(name: 'note.txt', sizeBytes: 10);

/// A LocalBackend whose [openRead] fails the first [failsLeft] times — used to
/// exercise transfer retry/backoff against real temp files.
class _FlakyLocal extends LocalBackend {
  int failsLeft = 0;
  @override
  Future<ReadHandle> openRead(String path) {
    if (failsLeft > 0) {
      failsLeft--;
      throw Exception('flaky read');
    }
    return super.openRead(path);
  }
}
