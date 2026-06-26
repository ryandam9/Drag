import 'dart:io';

import 'package:drag/models/connection.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// A one-request S3 stub that returns an empty (valid) ListBucketResult.
Future<HttpServer> _okS3() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('application', 'xml')
      ..write('<?xml version="1.0"?><ListBucketResult><Name>b</Name>'
          '<IsTruncated>false</IsTruncated></ListBucketResult>');
    await req.response.close();
  });
  return server;
}

void main() {
  group('testConnection validation', () {
    test('SFTP without a host reports an error', () async {
      final c = makeContainer();
      await c.read(sessionsProvider.notifier)
          .testConnection(Connection(name: 'srv', protocol: Protocol.sftp, username: 'u'));
      expect(c.read(toastsProvider).last.title, 'Missing details');
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
    });

    test('S3 without credentials reports an error', () async {
      final c = makeContainer();
      await c.read(sessionsProvider.notifier)
          .testConnection(Connection(name: 's3', protocol: Protocol.s3, bucket: 'b'));
      expect(c.read(toastsProvider).last.title, 'Missing credentials');
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
    });
  });

  group('testConnection (real handshake)', () {
    test('a reachable S3 endpoint reports success and marks it online', () async {
      final server = await _okS3();
      addTearDown(() => server.close(force: true));
      final c = makeContainer();
      final conn = Connection(
        name: 's3-ok',
        protocol: Protocol.s3,
        bucket: 'b',
        region: 'us-east-1',
        endpoint: '127.0.0.1:${server.port}',
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 'secret',
      );
      await c.read(sessionsProvider.notifier).testConnection(conn);
      expect(c.read(toastsProvider).last.title, 'Connection OK');
      expect(c.read(toastsProvider).last.kind, ToastKind.success);
      expect(conn.online, isTrue);
      // Richer status (#24): connected, with a last-tested timestamp, no error.
      expect(conn.status, ConnectionStatus.connected);
      expect(conn.lastTestedAt, isNotNull);
      expect(conn.lastError, isNull);

      // The connection log keeps a timestamped transcript that outlives toasts.
      final log = c.read(connectionLogProvider);
      expect(log.first.message, contains('Testing "s3-ok"'));
      expect(log.last.kind, ToastKind.success);
      expect(log.last.message, contains('connected'));
    });

    test('an unreachable S3 endpoint reports failure and marks it offline', () async {
      final c = makeContainer();
      final conn = Connection(
        name: 's3-bad',
        protocol: Protocol.s3,
        bucket: 'b',
        region: 'us-east-1',
        endpoint: '127.0.0.1:1', // closed port
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 'secret',
      )..status = ConnectionStatus.connected;
      await c.read(sessionsProvider.notifier).testConnection(conn);
      expect(c.read(toastsProvider).last.title, 'Connection failed');
      expect(c.read(toastsProvider).last.kind, ToastKind.error);
      expect(conn.online, isFalse);
      // Richer status (#24): failed, with the full error retained.
      expect(conn.status, ConnectionStatus.failed);
      expect(conn.lastError, isNotNull);
      expect(conn.lastError, isNotEmpty);

      final log = c.read(connectionLogProvider);
      expect(log.last.kind, ToastKind.error);
      expect(log.last.message, contains('s3-bad'));
    });

    test('connect() verifies a reachable S3 endpoint before reporting online', () async {
      final server = await _okS3();
      addTearDown(() => server.close(force: true));
      final c = makeContainer();
      final conn = Connection(
        name: 's3-connect',
        protocol: Protocol.s3,
        bucket: 'b',
        region: 'us-east-1',
        endpoint: '127.0.0.1:${server.port}',
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 'secret',
      );
      await c.read(sessionsProvider.notifier).connect(conn);
      expect(conn.online, isTrue);
      expect(c.read(toastsProvider).last.title, 'Session connected');
      expect(c.read(toastsProvider).last.kind, ToastKind.success);
    });

    test('connect() reports failure and stays offline for an unreachable endpoint', () async {
      final c = makeContainer();
      final conn = Connection(
        name: 's3-down',
        protocol: Protocol.s3,
        bucket: 'b',
        region: 'us-east-1',
        endpoint: '127.0.0.1:1',
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 'secret',
      )..status = ConnectionStatus.connected;
      await c.read(sessionsProvider.notifier).connect(conn);
      expect(conn.online, isFalse);
      expect(c.read(toastsProvider).last.title, 'Connection failed');
    });

    test('clear() empties the connection log', () async {
      final c = makeContainer();
      final log = c.read(connectionLogProvider.notifier);
      log.info('one');
      log.error('two');
      expect(c.read(connectionLogProvider), hasLength(2));
      log.clear();
      expect(c.read(connectionLogProvider), isEmpty);
    });
  });
}
