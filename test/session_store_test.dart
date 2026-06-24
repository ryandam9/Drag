import 'package:drag/data/session_store.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  group('SessionStore (SQLite)', () {
    late SessionStore store;
    setUp(() async => store = await SessionStore.open(inMemoryDatabasePath));
    tearDown(() => store.close());

    test('load returns empty on a fresh store', () async {
      final layout = await store.load();
      expect(layout.sessions, isEmpty);
    });

    test('replaceAll + load round-trips records and the active index', () async {
      await store.replaceAll([
        const SessionRecord(leftConnId: null, leftPath: '/home', rightConnId: 's3a', rightPath: 'logs/'),
        const SessionRecord(leftConnId: null, leftPath: '/tmp', rightConnId: null, rightPath: '/var'),
      ], activeIndex: 1);
      final layout = await store.load();
      expect(layout.sessions.length, 2);
      expect(layout.activeIndex, 1);
      expect(layout.sessions.first.leftPath, '/home');
      expect(layout.sessions.first.rightConnId, 's3a');
      expect(layout.sessions.first.rightPath, 'logs/');
      expect(layout.sessions[1].rightConnId, isNull);
    });
  });

  group('session restore', () {
    test('rebuilds the persisted tabs and pane endpoints', () {
      final layout = SessionLayout(const [
        SessionRecord(leftConnId: null, leftPath: '/home/me', rightConnId: 's3a', rightPath: 'reports/'),
      ], 0);
      final c = makeContainer(connections: sampleConnections(), layout: layout);

      final state = c.read(sessionsProvider);
      expect(state.sessions.length, 1);

      final s = c.read(sessionsProvider.notifier);
      expect(s.leftPane.connection, isNull); // Local
      expect(s.leftPane.path, '/home/me');
      expect(s.rightPane.connection?.id, 's3a');
      expect(s.rightPane.kind, EndpointKind.s3);
      expect(s.rightPane.path, 'reports/');
    });

    test('falls back to one Local tab with no persisted layout', () {
      final c = makeContainer();
      final state = c.read(sessionsProvider);
      expect(state.sessions.length, 1);
      expect(c.read(sessionsProvider.notifier).leftPane.connection, isNull);
    });

    test('drops a tab whose connection id no longer exists (resolves to Local)', () {
      final layout = SessionLayout(const [
        SessionRecord(leftConnId: null, leftPath: '/a', rightConnId: 'gone', rightPath: 'x/'),
      ], 0);
      final c = makeContainer(connections: sampleConnections(), layout: layout);
      // Unknown id resolves to Local rather than crashing.
      expect(c.read(sessionsProvider.notifier).rightPane.connection, isNull);
    });
  });

  group('session persistence', () {
    test('opening a tab persists the layout', () async {
      final store = await SessionStore.open(inMemoryDatabasePath);
      addTearDown(store.close);
      final c = makeContainer(
        connections: sampleConnections(),
        sessionStore: store,
      );
      final s = c.read(sessionsProvider.notifier);
      s.openSession(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));

      // The save is debounced (~400ms); wait it out.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final layout = await store.load();
      expect(layout.sessions.length, 2);
      expect(layout.sessions.last.rightConnId, 's3a');
    });
  });
}
