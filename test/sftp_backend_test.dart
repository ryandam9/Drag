import 'dart:io';

import 'package:drag/fs/sftp_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

Connection _conn({
  String host = 'example.com',
  int port = 22,
  String user = 'deploy',
  String remotePath = '/srv',
  AuthMethod auth = AuthMethod.password,
  String keyFile = '',
}) =>
    Connection(
      name: 'h',
      protocol: Protocol.sftp,
      host: host,
      port: port,
      username: user,
      remotePath: remotePath,
      auth: auth,
      keyFile: keyFile,
    );

void main() {
  group('pure / sync surface', () {
    final b = SftpBackend(_conn());

    test('badge and kind', () {
      expect(b.badge, 'SFTP');
      expect(b.kind, EndpointKind.sftp);
    });

    test('supports mutation and transfer by default', () {
      expect(b.supportsMutation, isTrue);
      expect(b.supportsTransfer, isTrue);
    });

    test('isReady needs host and username', () {
      expect(SftpBackend(_conn()).isReady, isTrue);
      expect(SftpBackend(_conn(host: '')).isReady, isFalse);
      expect(SftpBackend(_conn(user: '')).isReady, isFalse);
    });

    test('initialPath uses remotePath, or / when empty', () {
      expect(SftpBackend(_conn(remotePath: '/var/www')).initialPath, '/var/www');
      expect(SftpBackend(_conn(remotePath: '')).initialPath, '/');
    });

    test('displayPath renders an sftp:// URI', () {
      expect(b.displayPath('/srv/app'), 'sftp://deploy@example.com/srv/app');
    });

    test('childPath joins POSIX paths', () {
      expect(b.childPath('/srv', 'file', false), '/srv/file');
      expect(b.childPath('/srv/', 'sub', true), '/srv/sub');
    });

    test('parentPath walks up, clamping at root', () {
      expect(b.parentPath('/a/b/c'), '/a/b');
      expect(b.parentPath('/a/b/'), '/a');
      expect(b.parentPath('/a'), '/');
      expect(b.parentPath('/'), '/');
    });
  });

  group('connection errors', () {
    test('missing private key file throws a clear error', () async {
      // A plain TCP listener lets SSHSocket.connect succeed so the key lookup
      // (which happens next) is the thing that fails.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((s) {/* accept and ignore */});

      final b = SftpBackend(_conn(
        host: '127.0.0.1',
        port: server.port,
        auth: AuthMethod.privateKey,
        keyFile: '/no/such/key_rsa',
      ));
      addTearDown(b.dispose);

      await expectLater(
        b.list('/'),
        throwsA(predicate((e) => e.toString().contains('Key file not found'))),
      );
    });

    test('a refused connection surfaces as an error and can be retried', () async {
      final b = SftpBackend(_conn(host: '127.0.0.1', port: 1));
      addTearDown(b.dispose);
      await expectLater(b.list('/'), throwsA(isA<Object>()));
      // The internal connect future was reset, so a second attempt also throws
      // (rather than hanging on a stale future).
      await expectLater(b.list('/'), throwsA(isA<Object>()));
    });
  });
}
