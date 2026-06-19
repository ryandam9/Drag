import 'package:drag/data/connection_store.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

    test('loadOrSeed seeds on first run, then returns persisted', () async {
      final seeded = await store.loadOrSeed();
      expect(seeded, isNotEmpty);
      final again = await store.loadOrSeed();
      expect(again.length, seeded.length);
      expect(again.first.name, seeded.first.name);
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
      await store.replaceAll([Connection(id: 'a', name: 'A'), Connection(id: 'b', name: 'B')]);
      await store.delete('a');
      final loaded = await store.load();
      expect(loaded.map((e) => e.id), ['b']);
    });

    test('secrets never reach storage', () async {
      await store.replaceAll([
        Connection(id: 's', name: 'S', accessKeyId: 'AKIA', secretAccessKey: 'SECRET'),
      ]);
      final loaded = (await store.load()).single;
      expect(loaded.accessKeyId, 'AKIA');
      expect(loaded.secretAccessKey, '');
    });
  });

  group('AppState persistence', () {
    late ConnectionStore store;
    late AppState app;

    setUp(() async {
      store = await ConnectionStore.open(inMemoryDatabasePath);
      app = AppState(
        tickEnabled: false,
        autoRefreshPanes: false,
        connectionStore: store,
        connections: [
          Connection(id: 's3', name: 's3-prod (Account A)', protocol: Protocol.s3, bucket: 'b'),
          Connection(id: 'srv', name: 'server', host: 'h', username: 'u'),
        ],
      );
    });
    tearDown(() async {
      app.dispose();
      await store.close();
    });

    test('newConnection adds and persists', () async {
      final before = app.connections.length;
      await app.newConnection();
      expect(app.connections.length, before + 1);
      expect(identical(app.selectedConnection, app.connections.last), isTrue);
      expect((await store.load()).length, before + 1);
    });

    test('duplicateConnection clones with a new id and persists', () async {
      final original = app.connections.firstWhere((c) => c.isS3);
      final copy = await app.duplicateConnection(original);
      expect(copy.id == original.id, isFalse);
      expect(copy.name, contains('copy'));
      expect(copy.bucket, original.bucket);
      expect((await store.load()).any((c) => c.id == copy.id), isTrue);
    });

    test('deleteConnection removes and persists', () async {
      final victim = app.connections.last;
      await app.deleteConnection(victim);
      expect(app.connections.contains(victim), isFalse);
      expect((await store.load()).any((c) => c.id == victim.id), isFalse);
    });

    test('saveConnection upserts edits', () async {
      final c = app.connections.first..name = 'renamed';
      await app.saveConnection(c);
      final stored = (await store.load()).firstWhere((x) => x.id == c.id);
      expect(stored.name, 'renamed');
    });
  });
}
