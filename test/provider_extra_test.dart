import 'package:drag/data/history_db.dart';
import 'package:drag/data/settings_store.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  group('toasts', () {
    test('auto-dismiss removes the toast after the 10s lifetime', () {
      fakeAsync((async) {
        final c = makeContainer();
        c.read(toastsProvider.notifier).push('A', 'b', ToastKind.info);
        expect(c.read(toastsProvider).length, 1);
        // Still visible just before the lifetime elapses…
        async.elapse(const Duration(seconds: 9));
        expect(c.read(toastsProvider).length, 1);
        // …and gone shortly after.
        async.elapse(const Duration(seconds: 2));
        expect(c.read(toastsProvider), isEmpty);
      });
    });

    test('multiple toasts get distinct ids', () {
      final c = makeContainer();
      final n = c.read(toastsProvider.notifier)
        ..push('A', '1', ToastKind.info)
        ..push('B', '2', ToastKind.error);
      final ids = c.read(toastsProvider).map((t) => t.id).toSet();
      expect(ids.length, 2);
      expect(n, isNotNull);
    });

    test('dismiss removes a single toast immediately', () {
      final c = makeContainer();
      c.read(toastsProvider.notifier)
        ..push('A', '1', ToastKind.info)
        ..push('B', '2', ToastKind.error);
      final first = c.read(toastsProvider).first.id;
      c.read(toastsProvider.notifier).dismiss(first);
      final remaining = c.read(toastsProvider);
      expect(remaining.length, 1);
      expect(remaining.single.title, 'B');
    });
  });

  group('transfer speed limit', () {
    test('a changed limit updates the shared limiter live', () {
      final c = makeContainer();
      final transfers = c.read(transfersProvider.notifier);
      // fireImmediately wired the default (Unlimited) cap.
      expect(transfers.currentRateCap, isNull);

      c.read(settingsProvider.notifier).setTransferLimitKbps(512);
      expect(transfers.currentRateCap, 512 * 1024); // applied without a restart

      c.read(settingsProvider.notifier).setTransferLimitKbps(0);
      expect(transfers.currentRateCap, isNull); // back to unlimited
    });
  });

  group('settings', () {
    test('setters update the in-memory state', () {
      final c = makeContainer();
      final n = c.read(settingsProvider.notifier);
      n.setThemeName('Light');
      n.setMonospaceFont('Fira Code');
      n.setShowPermsColumn(false);
      n.setConfirmOverwrite(false);
      n.setUiFontSize(14);
      final s = c.read(settingsProvider);
      expect(s.themeName, 'Light');
      expect(s.monospaceFont, 'Fira Code');
      expect(s.showPermsColumn, isFalse);
      expect(s.confirmOverwrite, isFalse);
      expect(s.uiFontSize, 14);
    });

    test('saveWindowState persists geometry to SQLite', () async {
      final store = await SettingsStore.open(inMemoryDatabasePath);
      addTearDown(store.close);
      final c = makeContainer(settingsStore: store);
      await c
          .read(settingsProvider.notifier)
          .saveWindowState(width: 1200, height: 800, x: 40, y: 60);
      final loaded = await store.load();
      expect(loaded.windowWidth, 1200);
      expect(loaded.windowHeight, 800);
      expect(loaded.windowX, 40);
      expect(loaded.windowY, 60);
    });

    test('AppSettingsView exposes the accent colour', () {
      final c = makeContainer(settings: AppSettings(accentValue: 0xFF112233));
      expect(c.read(settingsProvider).accent, const Color(0xFF112233));
    });
  });

  group('history', () {
    test('refresh loads records and clear empties them', () async {
      final repo = await HistoryRepository.open(inMemoryDatabasePath);
      addTearDown(repo.close);
      await repo.add(
        TransferRecord(
          name: 'x.bin',
          sourcePath: 'Local:/x.bin',
          destPath: 's3://b/x.bin',
          session: 'b',
          sizeBytes: 1000,
          direction: 0,
          durationMs: 500,
          success: true,
          finishedAt: DateTime.now(),
        ),
      );
      final c = makeContainer(history: repo);
      final n = c.read(historyProvider.notifier);
      await n.refresh();
      expect(c.read(historyProvider).records, isNotEmpty);
      expect(c.read(historyProvider).hasDb, isTrue);
      await n.clear();
      expect(c.read(historyProvider).records, isEmpty);
      expect(c.read(historyProvider).stats.total, 0);
    });

    test(
      'without a repository, history is empty and flagged as unavailable',
      () {
        final c = makeContainer();
        expect(c.read(historyProvider).hasDb, isFalse);
        expect(c.read(historyProvider).records, isEmpty);
      },
    );

    test('a burst of records debounces into a single refresh', () async {
      final repo = await HistoryRepository.open(inMemoryDatabasePath);
      addTearDown(repo.close);
      final c = makeContainer(history: repo);
      final n = c.read(historyProvider.notifier)
        ..refreshDebounce = const Duration(milliseconds: 40);
      // Let build()'s initial refresh settle before counting emissions.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      var emissions = 0;
      c.listen(historyProvider, (_, _) => emissions++);

      Transfer done(String name) => Transfer(
        name: name,
        route: 'a → b',
        direction: TransferDirection.upload,
        sizeBytes: 10,
        session: 's',
        status: TransferStatus.done,
      );
      for (var i = 0; i < 5; i++) {
        await n.record(done('f$i.bin'));
      }
      // Every record is persisted immediately, but the dashboard reloads once,
      // after the trailing debounce — not once per completed file.
      expect(emissions, 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions, 1);
      expect(c.read(historyProvider).records.length, 5);
    });
  });

  group('sessions', () {
    test('backendFor caches per connection and evict drops the cache', () {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final conn = Connection(
        id: 'x',
        name: 's3',
        protocol: Protocol.s3,
        bucket: 'b',
      );
      final b1 = s.backendFor(conn);
      expect(identical(s.backendFor(conn), b1), isTrue);
      expect(s.backendFor(null), isA<LocalBackend>());
      s.evictBackend(conn);
      expect(identical(s.backendFor(conn), b1), isFalse);
    });

    test('focusPane switches the focused pane', () {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      expect(c.read(sessionsProvider).focusedLeft, isTrue);
      s.focusPane(false);
      expect(c.read(sessionsProvider).focusedLeft, isFalse);
      expect(identical(s.focusedPane, s.rightPane), isTrue);
    });

    test('switchSession ignores an unknown id', () {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final before = c.read(sessionsProvider).activeSessionId;
      s.switchSession(99999);
      expect(c.read(sessionsProvider).activeSessionId, before);
    });

    test('connect navigates to the browser screen', () async {
      final c = makeContainer(connections: sampleConnections());
      final sftp =
          c
              .read(connectionsProvider)
              .connections
              .firstWhere((x) => x.kind == EndpointKind.sftp)
            ..host = '127.0.0.1'
            ..port = 1;
      c.read(navProvider.notifier).go(AppScreen.connections);
      await c.read(sessionsProvider.notifier).connect(sftp);
      expect(c.read(navProvider), AppScreen.browser);
    });
  });

  group('connections', () {
    test('duplicate inserts after the original and selects the copy', () async {
      final c = makeContainer(connections: sampleConnections());
      final n = c.read(connectionsProvider.notifier);
      final original = c.read(connectionsProvider).connections.first;
      final copy = await n.duplicate(original);
      final list = c.read(connectionsProvider).connections;
      expect(list[list.indexOf(original) + 1], same(copy));
      expect(c.read(connectionsProvider).selected, same(copy));
    });

    test('deleting the last connection clears the selection', () async {
      final c = makeContainer(
        connections: [Connection(id: 'only', name: 'only')],
      );
      final n = c.read(connectionsProvider.notifier);
      await n.delete(c.read(connectionsProvider).connections.single);
      expect(c.read(connectionsProvider).connections, isEmpty);
      expect(c.read(connectionsProvider).selected, isNull);
    });
  });
}
