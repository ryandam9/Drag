import 'dart:io';

import 'package:drag/data/known_hosts_store.dart';
import 'package:drag/fs/host_key_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KnownHostsStore store;

  setUp(() async {
    sqfliteFfiInit();
    store = await KnownHostsStore.open(inMemoryDatabasePath);
  });
  tearDown(() => store.close());

  group('HostKeyVerifier (trust-on-first-use)', () {
    test('a new host is remembered and accepted, then matches', () async {
      final v = HostKeyVerifier(store);
      expect(
        await v.check('h', 22, 'ssh-ed25519', 'SHA256:aaa'),
        HostKeyOutcome.trustedFirstUse,
      );
      expect((await store.find('h', 22))!.fingerprint, 'SHA256:aaa');
      expect(
        await v.check('h', 22, 'ssh-ed25519', 'SHA256:aaa'),
        HostKeyOutcome.matched,
      );
      expect(await v.verify('h', 22, 'ssh-ed25519', 'SHA256:aaa'), isTrue);
    });

    test(
      'a changed key is a mismatch, rejected, and not overwritten',
      () async {
        final v = HostKeyVerifier(store);
        await v.check('h', 22, 't', 'SHA256:aaa');
        expect(
          await v.check('h', 22, 't', 'SHA256:bbb'),
          HostKeyOutcome.mismatch,
        );
        expect(await v.verify('h', 22, 't', 'SHA256:bbb'), isFalse);
        // The originally-trusted key is still the one on file.
        expect((await store.find('h', 22))!.fingerprint, 'SHA256:aaa');
      },
    );

    test('forgetting a host re-prompts on the next connect', () async {
      final v = HostKeyVerifier(store);
      await v.check('h', 22, 't', 'SHA256:aaa');
      await store.forget('h', 22);
      expect(await store.find('h', 22), isNull);
      expect(
        await v.check('h', 22, 't', 'SHA256:ccc'),
        HostKeyOutcome.trustedFirstUse,
      );
    });

    test('host:port pairs are tracked independently', () async {
      final v = HostKeyVerifier(store);
      await v.check('h', 22, 't', 'SHA256:aaa');
      expect(
        await v.check('h', 2222, 't', 'SHA256:zzz'),
        HostKeyOutcome.trustedFirstUse,
      );
      expect((await store.load()).length, 2);
    });

    test('onOutcome observer reports each decision', () async {
      final seen = <HostKeyOutcome>[];
      final v = HostKeyVerifier(store, onOutcome: (o, h) => seen.add(o));
      await v.check('h', 22, 't', 'SHA256:aaa');
      await v.check('h', 22, 't', 'SHA256:aaa');
      await v.check('h', 22, 't', 'SHA256:bbb');
      expect(seen, [
        HostKeyOutcome.trustedFirstUse,
        HostKeyOutcome.matched,
        HostKeyOutcome.mismatch,
      ]);
    });
  });

  group('HostKeyVerifier first-use prompt', () {
    test('"trust & remember" accepts and persists the key', () async {
      final v = HostKeyVerifier(store)
        ..prompt = (_) async => HostKeyDecision.trustAndRemember;
      expect(
        await v.check('h', 22, 't', 'SHA256:aaa'),
        HostKeyOutcome.trustedFirstUse,
      );
      expect((await store.find('h', 22))!.fingerprint, 'SHA256:aaa');
    });

    test('"trust once" accepts but does not persist', () async {
      final v = HostKeyVerifier(store)
        ..prompt = (_) async => HostKeyDecision.trustOnce;
      expect(await v.verify('h', 22, 't', 'SHA256:aaa'), isTrue);
      expect(await store.find('h', 22), isNull); // not remembered
    });

    test('"cancel" rejects the connection', () async {
      final v = HostKeyVerifier(store)
        ..prompt = (_) async => HostKeyDecision.cancel;
      expect(
        await v.check('h', 22, 't', 'SHA256:aaa'),
        HostKeyOutcome.rejectedByUser,
      );
      expect(await v.verify('h', 22, 't', 'SHA256:aaa'), isFalse);
      expect(await store.find('h', 22), isNull);
    });

    test('the prompt receives the presented fingerprint', () async {
      HostKeyInfo? got;
      final v = HostKeyVerifier(store)
        ..prompt = (info) async {
          got = info;
          return HostKeyDecision.trustOnce;
        };
      await v.check('host.example', 2222, 'ssh-ed25519', 'SHA256:zzz');
      expect(got!.host, 'host.example');
      expect(got!.port, 2222);
      expect(got!.fingerprint, 'SHA256:zzz');
    });

    test('a remembered host never re-prompts', () async {
      var prompts = 0;
      final v = HostKeyVerifier(store)
        ..prompt = (_) async {
          prompts++;
          return HostKeyDecision.trustAndRemember;
        };
      await v.check('h', 22, 't', 'SHA256:aaa');
      await v.check('h', 22, 't', 'SHA256:aaa'); // matches → no prompt
      expect(prompts, 1);
    });
  });

  group('KnownHostsStore', () {
    test('load is sorted; remove and clear work', () async {
      await store.trust(
        const KnownHost(host: 'b', port: 22, type: 't', fingerprint: 'f2'),
      );
      await store.trust(
        const KnownHost(host: 'a', port: 22, type: 't', fingerprint: 'f1'),
      );
      final all = await store.load();
      expect(all.map((h) => h.host), ['a', 'b']); // host ASC
      await store.remove(all.first.id!);
      expect((await store.load()).map((h) => h.host), ['b']);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('endpoint label omits the default SSH port', () {
      expect(
        const KnownHost(
          host: 'h',
          port: 22,
          type: 't',
          fingerprint: 'f',
        ).endpoint,
        'h',
      );
      expect(
        const KnownHost(
          host: 'h',
          port: 2222,
          type: 't',
          fingerprint: 'f',
        ).endpoint,
        'h:2222',
      );
    });

    test('an in-memory store reports memoryOnly status', () {
      // The shared `store` is opened with inMemoryDatabasePath in setUp.
      expect(store.status, KnownHostsStoreStatus.memoryOnly);
    });

    test('an on-disk store reports persistent status', () async {
      final dir = await Directory.systemTemp.createTemp('known_hosts');
      addTearDown(() => dir.delete(recursive: true));
      final disk = await KnownHostsStore.open('${dir.path}/kh.db');
      addTearDown(disk.close);
      expect(disk.status, KnownHostsStoreStatus.persistent);
    });

    test(
      'trust upserts on (host,port) instead of inserting a duplicate',
      () async {
        await store.trust(
          const KnownHost(
            host: 'h',
            port: 22,
            type: 't',
            fingerprint: 'SHA256:aaa',
          ),
        );
        await store.trust(
          const KnownHost(
            host: 'h',
            port: 22,
            type: 't',
            fingerprint: 'SHA256:bbb',
          ),
        );
        final all = await store.load();
        expect(all.where((h) => h.host == 'h' && h.port == 22).length, 1);
        expect(
          (await store.find('h', 22))!.fingerprint,
          'SHA256:bbb',
        ); // latest wins
      },
    );

    test(
      'migrates a v1 database: dedups (host,port) and enforces uniqueness',
      () async {
        final dir = await Directory.systemTemp.createTemp('kh_mig');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/kh.db';

        // Build a v1-shaped database (no unique index) with duplicate rows.
        final raw = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => db.execute('''
            CREATE TABLE known_hosts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              host TEXT NOT NULL, port INTEGER NOT NULL,
              type TEXT NOT NULL, fingerprint TEXT NOT NULL, created_at TEXT NOT NULL)
          '''),
          ),
        );
        await raw.insert('known_hosts', {
          'host': 'h',
          'port': 22,
          'type': 't',
          'fingerprint': 'old',
          'created_at': 'a',
        });
        await raw.insert('known_hosts', {
          'host': 'h',
          'port': 22,
          'type': 't',
          'fingerprint': 'new',
          'created_at': 'b',
        });
        await raw.close();

        // Reopen through the store → runs the v2 migration.
        final migrated = await KnownHostsStore.open(path);
        addTearDown(migrated.close);
        final all = await migrated.load();
        expect(all.length, 1, reason: 'duplicate rows collapsed');
        expect(all.single.fingerprint, 'new', reason: 'kept the most recent');

        // The unique index now holds: re-trusting upserts rather than duplicating.
        await migrated.trust(
          const KnownHost(host: 'h', port: 22, type: 't', fingerprint: 'newer'),
        );
        expect((await migrated.load()).length, 1);
        expect((await migrated.find('h', 22))!.fingerprint, 'newer');
      },
    );
  });
}
