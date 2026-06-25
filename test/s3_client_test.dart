import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/aws/aws_profile.dart';
import 'package:drag/fs/aws/s3_client.dart';
import 'package:drag/fs/aws/sigv4.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// A captured inbound request (for assertions on what the client sent).
class Captured {
  final String method;
  final String path;
  final Map<String, String> query;
  final HttpHeaders headers;
  final List<int> body;
  Captured(this.method, this.path, this.query, this.headers, this.body);
}

/// A tiny in-process S3-compatible server. Each test supplies a [responder]
/// that inspects the request and writes a canned response.
class MockS3 {
  MockS3(this._server);
  final HttpServer _server;
  final List<Captured> requests = [];

  int get port => _server.port;
  String get endpoint => '127.0.0.1:$port';
  Captured get last => requests.last;

  static Future<MockS3> start(
      FutureOr<void> Function(Captured req, HttpResponse res) responder) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = MockS3(server);
    server.listen((req) async {
      final body = await _collect(req);
      final captured = Captured(req.method, req.uri.path, req.uri.queryParameters, req.headers, body);
      mock.requests.add(captured);
      await responder(captured, req.response);
      await req.response.close();
    });
    return mock;
  }

  static Future<List<int>> _collect(HttpRequest req) async {
    final out = <int>[];
    await for (final chunk in req) {
      out.addAll(chunk);
    }
    return out;
  }

  Future<void> stop() => _server.close(force: true);
}

void xml(HttpResponse res, String body, {int status = 200}) {
  res.statusCode = status;
  res.headers.contentType = ContentType('application', 'xml');
  res.write(body);
}

String listingXml({
  required List<({String key, int size})> contents,
  List<String> prefixes = const [],
  bool truncated = false,
  String? nextToken,
}) {
  final c = contents
      .map((o) =>
          '<Contents><Key>${o.key}</Key><Size>${o.size}</Size><LastModified>2025-01-02T03:04:05.000Z</LastModified></Contents>')
      .join();
  final p = prefixes.map((x) => '<CommonPrefixes><Prefix>$x</Prefix></CommonPrefixes>').join();
  final next = nextToken != null ? '<NextContinuationToken>$nextToken</NextContinuationToken>' : '';
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<ListBucketResult><Name>bk</Name>'
      '<IsTruncated>$truncated</IsTruncated>$next$c$p</ListBucketResult>';
}

S3Client client(MockS3 mock, {AwsCredentials Function()? credentials}) => S3Client(
      bucket: 'bk',
      region: 'us-east-1',
      endpoint: mock.endpoint,
      useSsl: false,
      credentials: credentials ?? () => const AwsCredentials('AKIA', 'secret'),
    );

void main() {
  group('S3Client — ListObjectsV2', () {
    test('parses Contents, CommonPrefixes and metadata', () async {
      final mock = await MockS3.start((req, res) {
        xml(res, listingXml(contents: [(key: 'logs/a.txt', size: 12)], prefixes: ['logs/sub/']));
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final page = await c.listObjects(prefix: 'logs/');
      expect(page.objects.single.key, 'logs/a.txt');
      expect(page.objects.single.size, 12);
      expect(page.objects.single.lastModified, isNotNull);
      expect(page.commonPrefixes, ['logs/sub/']);
      expect(page.isTruncated, isFalse);

      // The request carried the ListObjectsV2 query.
      expect(mock.last.method, 'GET');
      expect(mock.last.query['list-type'], '2');
      expect(mock.last.query['prefix'], 'logs/');
      expect(mock.last.query['delimiter'], '/');
    });

    test('listAll follows continuation tokens across pages', () async {
      final mock = await MockS3.start((req, res) {
        final token = req.query['continuation-token'];
        if (token == null) {
          xml(res, listingXml(contents: [(key: 'a', size: 1)], truncated: true, nextToken: 'TOK2'));
        } else {
          expect(token, 'TOK2');
          xml(res, listingXml(contents: [(key: 'b', size: 2)]));
        }
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final all = await c.listAll(prefix: '');
      expect(all.objects.map((o) => o.key), ['a', 'b']);
      expect(all.isTruncated, isFalse);
      expect(mock.requests.length, 2);
    });

    test('non-2xx with an XML error body throws a parsed S3Exception', () async {
      final mock = await MockS3.start((req, res) {
        xml(res, '<Error><Code>AccessDenied</Code><Message>nope</Message></Error>', status: 403);
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      expect(
        () => c.listObjects(),
        throwsA(isA<S3Exception>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'nope')),
      );
    });

    test('non-XML error body falls back to the raw text', () async {
      final mock = await MockS3.start((req, res) {
        res.statusCode = 500;
        res.write('internal boom');
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      expect(
        () => c.listObjects(),
        throwsA(isA<S3Exception>().having((e) => e.message, 'message', 'internal boom')),
      );
    });
  });

  group('S3Client — objects', () {
    test('getObject streams bytes and reports content length', () async {
      final payload = List<int>.generate(256, (i) => i % 256);
      final mock = await MockS3.start((req, res) {
        res.statusCode = 200;
        res.contentLength = payload.length;
        res.add(payload);
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final resp = await c.getObject('folder/file.bin');
      expect(resp.contentLength, payload.length);
      final got = <int>[];
      await for (final chunk in resp.stream) {
        got.addAll(chunk);
      }
      expect(got, payload);
      expect(mock.last.path, '/bk/folder/file.bin');
    });

    test('putObject streams the body, sets length and reports progress', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 200);
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final data = Uint8List.fromList(List.filled(2048, 7));
      final progress = <int>[];
      await c.putObject('up.bin', Stream.value(data), data.length, onProgress: progress.add);

      expect(mock.last.method, 'PUT');
      expect(mock.last.path, '/bk/up.bin');
      expect(mock.last.body.length, 2048);
      expect(mock.last.headers.value('x-amz-content-sha256'), unsignedPayload);
      expect(progress.last, 2048);
    });

    test('getObject sends a Range header and streams the tail when resuming', () async {
      final full = List<int>.generate(100, (i) => i);
      final mock = await MockS3.start((req, res) {
        final range = req.headers.value('range');
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          final tail = full.sublist(start);
          res.statusCode = 206;
          res.contentLength = tail.length;
          res.add(tail);
        } else {
          res.contentLength = full.length;
          res.add(full);
        }
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final resp = await c.getObject('f.bin', rangeStart: 40);
      expect(mock.last.headers.value('range'), 'bytes=40-');
      expect(resp.contentLength, 60);
      final got = <int>[];
      await for (final ch in resp.stream) {
        got.addAll(ch);
      }
      expect(got, full.sublist(40));
    });

    test('deleteObject issues a DELETE', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 204);
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      await c.deleteObject('gone.txt');
      expect(mock.last.method, 'DELETE');
      expect(mock.last.path, '/bk/gone.txt');
    });

    test('copyObject sends the x-amz-copy-source header', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 200);
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      await c.copyObject('a/x.txt', 'b/y.txt');
      expect(mock.last.method, 'PUT');
      expect(mock.last.path, '/bk/b/y.txt');
      expect(mock.last.headers.value('x-amz-copy-source'), '/bk/a/x.txt');
    });

    test('putObject failure surfaces an S3Exception', () async {
      final mock = await MockS3.start((req, res) {
        xml(res, '<Error><Message>denied</Message></Error>', status: 403);
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      expect(
        () => c.putObject('x', Stream.value(Uint8List(1)), 1),
        throwsA(isA<S3Exception>().having((e) => e.message, 'message', 'denied')),
      );
    });
  });

  group('S3Client — multipart upload', () {
    test('uploads parts and completes, round-tripping the bytes in order', () async {
      final partBodies = <int, List<int>>{};
      String? completeBody;
      final mock = await MockS3.start((req, res) {
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(res, '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>');
        } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
          partBodies[int.parse(q['partNumber']!)] = req.body;
          res.headers.set('ETag', '"etag-${q['partNumber']}"');
          res.statusCode = 200;
        } else if (req.method == 'POST' && q.containsKey('uploadId')) {
          completeBody = utf8.decode(req.body);
          xml(res, '<CompleteMultipartUploadResult><ETag>"final"</ETag></CompleteMultipartUploadResult>');
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final payload = List<int>.generate(25, (i) => i);
      await c.putObjectMultipart('big.bin', Stream.value(Uint8List.fromList(payload)), partSize: 10);

      // 25 bytes / 10 ⇒ parts of 10, 10, 5.
      expect(partBodies.keys.toList()..sort(), [1, 2, 3]);
      expect(partBodies[1]!.length, 10);
      expect(partBodies[3]!.length, 5);
      final assembled = [for (var i = 1; i <= 3; i++) ...partBodies[i]!];
      expect(assembled, payload);
      // The Complete request lists every part + its ETag.
      expect(completeBody, contains('<PartNumber>1</PartNumber>'));
      expect(completeBody, contains('etag-3'));
    });

    test('aborts the upload when a part fails', () async {
      var aborted = false;
      final mock = await MockS3.start((req, res) {
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(res, '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>');
        } else if (req.method == 'PUT' && q['partNumber'] == '2') {
          xml(res, '<Error><Message>part boom</Message></Error>', status: 500);
        } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
          res.headers.set('ETag', '"e"');
          res.statusCode = 200;
        } else if (req.method == 'DELETE' && q.containsKey('uploadId')) {
          aborted = true;
          res.statusCode = 204;
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      await expectLater(
        c.putObjectMultipart('big.bin', Stream.value(Uint8List(25)), partSize: 10),
        throwsA(isA<S3Exception>()),
      );
      expect(aborted, isTrue, reason: 'a failed part must abort the upload');
    });

    test('put picks multipart above the threshold and single PUT below it', () async {
      final seen = <String>[];
      final mock = await MockS3.start((req, res) {
        seen.add('${req.method} ${req.query.containsKey('uploads') ? 'uploads' : req.query.containsKey('uploadId') ? 'uploadId' : req.query.containsKey('partNumber') ? 'part' : 'plain'}');
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(res, '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>');
        } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
          res.headers.set('ETag', '"e"');
          res.statusCode = 200;
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final c = S3Client(
        bucket: 'bk',
        region: 'us-east-1',
        endpoint: mock.endpoint,
        useSsl: false,
        credentials: () => const AwsCredentials('AKIA', 'secret'),
        multipartThreshold: 10,
        partSize: 10,
      );
      addTearDown(c.close);

      await c.put('big.bin', Stream.value(Uint8List(25)), 25); // > threshold ⇒ multipart
      expect(seen.where((s) => s.contains('uploads')), isNotEmpty);

      seen.clear();
      await c.put('small.bin', Stream.value(Uint8List(5)), 5); // ≤ threshold ⇒ single PUT
      expect(seen, ['PUT plain']);
    });
  });

  group('S3Client — credential refresh', () {
    test('re-resolves credentials on every request', () async {
      var current = const AwsCredentials('AKIAONE', 'secret');
      final mock = await MockS3.start((req, res) => xml(res, listingXml(contents: [])));
      addTearDown(mock.stop);
      final c = client(mock, credentials: () => current);
      addTearDown(c.close);

      await c.listObjects();
      expect(mock.last.headers.value('authorization'), contains('Credential=AKIAONE/'));

      // Simulate a refreshed credentials file between requests.
      current = const AwsCredentials('AKIATWO', 'secret');
      await c.listObjects();
      expect(mock.last.headers.value('authorization'), contains('Credential=AKIATWO/'));
    });
  });

  group('S3Backend — AWS profile mode', () {
    test('reads ~/.aws credentials and picks up a refresh per request', () async {
      final dir = await Directory.systemTemp.createTemp('awsprof');
      addTearDown(() => dir.delete(recursive: true));
      final credFile = File('${dir.path}/credentials');
      credFile.writeAsStringSync('[default]\naws_access_key_id=AKIAONE\naws_secret_access_key=s1\n');
      debugAwsCredentialsPath = credFile.path;
      addTearDown(() => debugAwsCredentialsPath = null);

      final mock = await MockS3.start((req, res) => xml(res, listingXml(contents: [])));
      addTearDown(mock.stop);
      final b = S3Backend(Connection(
        name: 's3',
        protocol: Protocol.s3,
        bucket: 'bk',
        region: 'us-east-1',
        endpoint: mock.endpoint,
        useSsl: false,
        useAwsProfile: true,
      ));
      addTearDown(b.dispose);
      expect(b.isReady, isTrue); // profile + bucket is enough

      await b.list('');
      expect(mock.last.headers.value('authorization'), contains('Credential=AKIAONE/'));

      // External process refreshes the temporary credentials on disk.
      credFile.writeAsStringSync('[default]\naws_access_key_id=AKIATWO\naws_secret_access_key=s2\n');
      await b.list('');
      expect(mock.last.headers.value('authorization'), contains('Credential=AKIATWO/'));
    });

    test('a missing profile surfaces a clear error', () async {
      final dir = await Directory.systemTemp.createTemp('awsprof2');
      addTearDown(() => dir.delete(recursive: true));
      debugAwsCredentialsPath = '${dir.path}/credentials'; // does not exist
      addTearDown(() => debugAwsCredentialsPath = null);

      final b = S3Backend(Connection(
        name: 's3',
        protocol: Protocol.s3,
        bucket: 'bk',
        region: 'us-east-1',
        endpoint: '127.0.0.1:1',
        useSsl: false,
        useAwsProfile: true,
        awsProfile: 'missing',
      ));
      addTearDown(b.dispose);
      await expectLater(
        b.list(''),
        throwsA(isA<S3Exception>().having((e) => e.message, 'message', contains('missing'))),
      );
    });
  });

  group('S3Client — service ops', () {
    test('listBuckets parses bucket names (GET /)', () async {
      final mock = await MockS3.start((req, res) => xml(res,
          '<?xml version="1.0"?><ListAllMyBucketsResult><Buckets>'
          '<Bucket><Name>alpha</Name></Bucket><Bucket><Name>beta</Name></Bucket>'
          '</Buckets></ListAllMyBucketsResult>'));
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      expect(await c.listBuckets(), ['alpha', 'beta']);
      expect(mock.last.path, '/');
    });

    test('getBucketLocation maps the region', () async {
      for (final pair in [('eu-west-1', 'eu-west-1'), ('', 'us-east-1'), ('EU', 'eu-west-1')]) {
        final mock = await MockS3.start(
            (req, res) => xml(res, '<LocationConstraint>${pair.$1}</LocationConstraint>'));
        final c = client(mock);
        expect(await c.getBucketLocation('b'), pair.$2, reason: 'for "${pair.$1}"');
        c.close();
        await mock.stop();
      }
    });
  });

  group('S3Backend — bucket discovery (no bucket configured)', () {
    test('lists the account buckets, then a bucket\'s objects', () async {
      final mock = await MockS3.start((req, res) {
        if (req.path == '/') {
          xml(res,
              '<?xml version="1.0"?><ListAllMyBucketsResult><Buckets>'
              '<Bucket><Name>alpha</Name></Bucket><Bucket><Name>beta</Name></Bucket>'
              '</Buckets></ListAllMyBucketsResult>');
        } else if (req.query['list-type'] == '2') {
          xml(res, listingXml(contents: [(key: 'report.csv', size: 9)], prefixes: ['logs/']));
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final b = S3Backend(Connection(
        name: 's3',
        protocol: Protocol.s3,
        bucket: '', // ← discovery
        region: 'us-east-1',
        endpoint: mock.endpoint,
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 's',
      ));
      addTearDown(b.dispose);
      expect(b.isReady, isTrue); // creds present, bucket optional

      // Root → the account's buckets, as folders.
      final root = await b.list('');
      expect(root.map((e) => e.name), containsAll(['alpha', 'beta']));
      expect(root.every((e) => e.isDir && !e.isParent), isTrue);

      // Enter a bucket → its objects/prefixes, with a '..' back to the list.
      final inside = await b.list(b.childPath('', 'alpha', true)); // 'alpha/'
      expect(inside.any((e) => e.isParent), isTrue);
      expect(inside.any((e) => e.name == 'logs' && e.isDir), isTrue);
      expect(inside.any((e) => e.name == 'report.csv'), isTrue);
      expect(b.displayPath('alpha/'), 's3://alpha/');
      expect(b.parentPath('alpha/'), ''); // back to the bucket list
    });

    test('refuses to delete a bucket from the root listing', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 200);
      addTearDown(mock.stop);
      final b = S3Backend(Connection(
        name: 's3', protocol: Protocol.s3, bucket: '', region: 'us-east-1',
        endpoint: mock.endpoint, useSsl: false, accessKeyId: 'AKIA', secretAccessKey: 's'));
      addTearDown(b.dispose);
      await expectLater(b.delete('alpha/', isDir: true), throwsUnsupportedError);
    });
  });

  group('S3Client — addressing', () {
    test('omits the default port and uses the http scheme when useSsl is false', () async {
      // Bind a server, but assert on the Host header it receives.
      final mock = await MockS3.start((req, res) => xml(res, listingXml(contents: [])));
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      await c.listObjects();
      // Custom (non-443/80) port → included in the Host header.
      expect(mock.last.headers.value('host'), '127.0.0.1:${mock.port}');
    });
  });

  // ── S3Backend on top of the mock server (covers storage_backend.dart) ──
  group('S3Backend (via mock server)', () {
    S3Backend backend(MockS3 mock) => S3Backend(Connection(
          name: 's3',
          protocol: Protocol.s3,
          bucket: 'bk',
          region: 'us-east-1',
          endpoint: mock.endpoint,
          useSsl: false,
          accessKeyId: 'AKIA',
          secretAccessKey: 'secret',
        ));

    test('list maps CommonPrefixes to folders and Contents to files, with ..', () async {
      final mock = await MockS3.start((req, res) {
        xml(res, listingXml(
          contents: [
            (key: 'logs/app.log', size: 5),
            (key: 'logs/', size: 0), // the prefix placeholder — skipped
          ],
          prefixes: ['logs/2025/'],
        ));
      });
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);

      final items = await b.list('logs/');
      expect(items.first.isParent, isTrue); // '..' because prefix non-empty
      final names = items.map((e) => e.name).toList();
      expect(names, contains('2025')); // folder from CommonPrefix
      expect(names, contains('app.log')); // file
      expect(names, isNot(contains(''))); // placeholder skipped
      final folder = items.firstWhere((e) => e.name == '2025');
      expect(folder.isDir, isTrue);
    });

    test('makeDir writes a zero-byte key ending in /', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 200);
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);
      await b.makeDir('newdir/');
      expect(mock.last.method, 'PUT');
      expect(mock.last.path, '/bk/newdir/');
      expect(mock.last.headers.contentLength, 0);
    });

    test('rename copies then deletes the source', () async {
      final methods = <String>[];
      final mock = await MockS3.start((req, res) {
        methods.add('${req.method} ${req.path}');
        res.statusCode = 200;
      });
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);
      await b.rename('a.txt', 'b.txt');
      expect(methods, ['PUT /bk/b.txt', 'DELETE /bk/a.txt']);
    });

    test('delete (recursive) lists the prefix and deletes each object', () async {
      var listed = false;
      final deleted = <String>[];
      final mock = await MockS3.start((req, res) {
        if (req.query.containsKey('list-type')) {
          listed = true;
          xml(res, listingXml(contents: [(key: 'dir/a', size: 1), (key: 'dir/b', size: 1)]));
        } else if (req.method == 'DELETE') {
          deleted.add(req.path);
          res.statusCode = 204;
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);
      await b.delete('dir/', isDir: true);
      expect(listed, isTrue);
      expect(deleted, containsAll(['/bk/dir/a', '/bk/dir/b']));
    });

    test('openRead → write round-trips bytes through the server', () async {
      final stored = <int>[];
      final payload = List<int>.generate(512, (i) => (i * 3) % 256);
      final mock = await MockS3.start((req, res) {
        if (req.method == 'GET') {
          res.contentLength = payload.length;
          res.add(payload);
        } else if (req.method == 'PUT') {
          stored.addAll(req.body);
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);

      final handle = await b.openRead('src.bin');
      expect(handle.length, payload.length);
      await b.write('dst.bin', handle.stream.map(Uint8List.fromList), handle.length);
      expect(stored, payload);
    });
  });
}
