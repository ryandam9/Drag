import 'package:drag/data/connection_store.dart';
import 'package:drag/data/secret_store.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  group('Connection JSON', () {
    test('round-trips non-secret fields', () {
      final c = Connection(
        id: 'c1',
        name: 'prod',
        host: 'h',
        port: 2222,
        username: 'u',
        protocol: Protocol.s3,
        auth: AuthMethod.password,
        region: 'eu-west-1',
        bucket: 'bk',
        endpoint: 'minio:9000',
        useSsl: false,
      );
      final back = Connection.fromJson(c.toJson());
      expect(back.id, 'c1');
      expect(back.name, 'prod');
      expect(back.port, 2222);
      expect(back.protocol, Protocol.s3);
      expect(back.auth, AuthMethod.password);
      expect(back.region, 'eu-west-1');
      expect(back.bucket, 'bk');
      expect(back.endpoint, 'minio:9000');
      expect(back.useSsl, isFalse);
    });

    test('does NOT persist secrets', () {
      final c = Connection(
        id: 'c2',
        name: 's',
        accessKeyId: 'AKIA',
        secretAccessKey: 'SECRET',
        sessionToken: 'TOKEN',
        password: 'pw',
        passphrase: 'pp',
      );
      final json = c.toJson();
      expect(json.containsKey('secretAccessKey'), isFalse);
      expect(json.containsKey('sessionToken'), isFalse);
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('passphrase'), isFalse);
      expect(json['accessKeyId'], 'AKIA'); // non-secret id is kept

      final back = Connection.fromJson(json);
      expect(back.secretAccessKey, '');
      expect(back.password, '');
      expect(back.passphrase, '');
    });
  });

  group('ConnectionStore', () {
    late ConnectionStore store;
    setUp(() async => store = await ConnectionStore.open(inMemoryDatabasePath));
    tearDown(() => store.close());

    test('load returns empty on a fresh store (no seeding)', () async {
      expect(await store.load(), isEmpty);
    });

    test('replaceAll + load preserves order', () async {
      await store.replaceAll([
        Connection(id: 'a', name: 'A'),
        Connection(id: 'b', name: 'B'),
        Connection(id: 'c', name: 'C'),
      ]);
      final loaded = await store.load();
      expect(loaded.map((e) => e.name).toList(), ['A', 'B', 'C']);
    });

    test('upsert updates an existing row by id', () async {
      await store.replaceAll([Connection(id: 'x', name: 'X')]);
      await store.upsert(Connection(id: 'x', name: 'X2'), 0);
      final loaded = await store.load();
      expect(loaded.length, 1);
      expect(loaded.single.name, 'X2');
    });

    test('delete removes a row', () async {
      await store.replaceAll([
        Connection(id: 'a', name: 'A'),
        Connection(id: 'b', name: 'B'),
      ]);
      await store.delete('a');
      final loaded = await store.load();
      expect(loaded.map((e) => e.id), ['b']);
    });

    test('secrets never reach storage', () async {
      await store.replaceAll([
        Connection(
          id: 's',
          name: 'S',
          accessKeyId: 'AKIA',
          secretAccessKey: 'SECRET',
        ),
      ]);
      final loaded = (await store.load()).single;
      expect(loaded.accessKeyId, 'AKIA');
      expect(loaded.secretAccessKey, '');
    });
  });

  group('ConnectionsNotifier persistence', () {
    late ConnectionStore store;
    late ProviderContainer c;
    late ConnectionsNotifier conns;

    setUp(() async {
      store = await ConnectionStore.open(inMemoryDatabasePath);
      c = makeContainer(
        connectionStore: store,
        connections: [
          Connection(
            id: 's3',
            name: 's3-prod (Account A)',
            protocol: Protocol.s3,
            bucket: 'b',
          ),
          Connection(id: 'srv', name: 'server', host: 'h', username: 'u'),
        ],
      );
      conns = c.read(connectionsProvider.notifier);
    });
    tearDown(() async => store.close());

    List<Connection> list() => c.read(connectionsProvider).connections;

    test('create adds and persists', () async {
      final before = list().length;
      await conns.create();
      expect(list().length, before + 1);
      expect(
        identical(c.read(connectionsProvider).selected, list().last),
        isTrue,
      );
      expect((await store.load()).length, before + 1);
    });

    test('duplicate clones with a new id and persists', () async {
      final original = list().firstWhere((x) => x.isS3);
      final copy = await conns.duplicate(original);
      expect(copy.id == original.id, isFalse);
      expect(copy.name, contains('copy'));
      expect(copy.bucket, original.bucket);
      expect((await store.load()).any((x) => x.id == copy.id), isTrue);
    });

    test('delete removes and persists', () async {
      final victim = list().last;
      await conns.delete(victim);
      expect(list().contains(victim), isFalse);
      expect((await store.load()).any((x) => x.id == victim.id), isFalse);
    });

    test('save upserts edits', () async {
      final conn = list().first..name = 'renamed';
      await conns.save(conn);
      final stored = (await store.load()).firstWhere((x) => x.id == conn.id);
      expect(stored.name, 'renamed');
    });

    test(
      'remember persists secrets so they survive into a new session',
      () async {
        final secrets = MemorySecretStore();
        final db = await ConnectionStore.open(inMemoryDatabasePath);
        final conn = Connection(
          id: 'srv2',
          name: 'srv2',
          host: 'h',
          username: 'u',
          protocol: Protocol.sftp,
        )..password = 'hunter2';

        // Session 1: connecting/testing calls remember(), which writes the record
        // to SQLite and the password to the (keychain-backed) secret store.
        final c1 = makeContainer(
          connectionStore: db,
          connections: [conn],
          overrides: [secretStoreProvider.overrideWithValue(secrets)],
        );
        await c1.read(connectionsProvider.notifier).remember(conn);

        // The SQLite record never holds the secret (it lives in the keychain).
        final reloaded = await db.load();
        expect(reloaded.single.password, isEmpty);

        // Session 2: a fresh boot restores the password from the secret store.
        final c2 = makeContainer(
          connectionStore: db,
          connections: reloaded,
          overrides: [secretStoreProvider.overrideWithValue(secrets)],
        );
        c2.read(connectionsProvider); // triggers the secret-restore microtask
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(
          c2.read(connectionsProvider).connections.single.password,
          'hunter2',
        );

        await db.close();
      },
    );
  });
}
