import 'package:drag/data/secret_store.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemorySecretStore', () {
    test('round-trips the secret fields and nothing else', () async {
      final store = MemorySecretStore();
      final c = Connection(id: 'm1', name: 'srv')
        ..password = 'pw'
        ..passphrase = 'pp'
        ..secretAccessKey = 'sk'
        ..sessionToken = 'st';
      await store.save(c);

      final blank = Connection(id: 'm1', name: 'srv');
      await store.load(blank);
      expect(blank.password, 'pw');
      expect(blank.passphrase, 'pp');
      expect(blank.secretAccessKey, 'sk');
      expect(blank.sessionToken, 'st');
    });

    test('delete removes the stored secrets', () async {
      final store = MemorySecretStore();
      final c = Connection(id: 'm2', name: 'srv')..password = 'pw';
      await store.save(c);
      await store.delete('m2');
      final blank = Connection(id: 'm2', name: 'srv');
      await store.load(blank);
      expect(blank.password, '');
    });
  });

  group('KeychainSecretStore', () {
    test('degrades to memory when the platform keychain is unavailable', () async {
      // In a unit test there's no platform channel, so the secure backend
      // throws and the store must fall back to its in-memory map.
      final store = KeychainSecretStore();
      final c = Connection(id: 'k1', name: 'srv')..password = 'pw';
      await store.save(c);
      final blank = Connection(id: 'k1', name: 'srv');
      await store.load(blank);
      expect(blank.password, 'pw');
    });
  });

  group('ConnectionsNotifier ↔ keychain', () {
    test('save writes secrets to the keychain (not the plain store)', () async {
      final secrets = MemorySecretStore();
      final c = makeContainer(overrides: [secretStoreProvider.overrideWithValue(secrets)]);
      final n = c.read(connectionsProvider.notifier);
      final conn = await n.create();
      conn
        ..password = 'pw'
        ..secretAccessKey = 'sk';
      await n.save(conn);

      // toJson never carries secrets; the keychain does.
      expect(conn.toJson().containsKey('password'), isFalse);
      final probe = Connection(id: conn.id, name: 'x');
      await secrets.load(probe);
      expect(probe.password, 'pw');
      expect(probe.secretAccessKey, 'sk');
    });

    test('deleting a connection removes its secrets', () async {
      final secrets = MemorySecretStore();
      final c = makeContainer(overrides: [secretStoreProvider.overrideWithValue(secrets)]);
      final n = c.read(connectionsProvider.notifier);
      final conn = await n.create();
      conn.password = 'pw';
      await n.save(conn);
      await n.delete(conn);

      final probe = Connection(id: conn.id, name: 'x');
      await secrets.load(probe);
      expect(probe.password, '');
    });

    test('secrets are restored into connections on startup', () async {
      final secrets = MemorySecretStore();
      await secrets.save(Connection(id: 'r1', name: 'srv')
        ..password = 'pw'
        ..passphrase = 'pp');

      final c = makeContainer(
        connections: [Connection(id: 'r1', name: 'srv', protocol: Protocol.sftp)],
        overrides: [secretStoreProvider.overrideWithValue(secrets)],
      );
      // build() schedules a microtask to pull secrets from the keychain.
      c.read(connectionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final restored = c.read(connectionsProvider).connections.first;
      expect(restored.password, 'pw');
      expect(restored.passphrase, 'pp');
    });
  });
}
