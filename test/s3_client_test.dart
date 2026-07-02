import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/aws/aws_profile.dart';
import 'package:drag/fs/aws/s3_client.dart';
import 'package:drag/fs/aws/sigv4.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_backend.dart';

/// A source whose reads report no size (like an SFTP server that omits it),
/// so the transfer can't declare a Content-Length up front.
class _UnsizedSource extends MemoryBackend {
  _UnsizedSource(Map<String, Uint8List> files) : super(files: files);
  @override
  Future<ReadHandle> openRead(String path) async {
    final h = await super.openRead(path);
    return ReadHandle(h.stream, null); // hide the length
  }
}

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
    FutureOr<void> Function(Captured req, HttpResponse res) responder,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = MockS3(server);
    server.listen((req) async {
      final body = await _collect(req);
      final captured = Captured(
        req.method,
        req.uri.path,
        req.uri.queryParameters,
        req.headers,
        body,
      );
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
      .map(
        (o) =>
            '<Contents><Key>${o.key}</Key><Size>${o.size}</Size><LastModified>2025-01-02T03:04:05.000Z</LastModified></Contents>',
      )
      .join();
  final p = prefixes
      .map((x) => '<CommonPrefixes><Prefix>$x</Prefix></CommonPrefixes>')
      .join();
  final next = nextToken != null
      ? '<NextContinuationToken>$nextToken</NextContinuationToken>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<ListBucketResult><Name>bk</Name>'
      '<IsTruncated>$truncated</IsTruncated>$next$c$p</ListBucketResult>';
}

S3Client client(MockS3 mock, {AwsCredentials Function()? credentials}) =>
    S3Client(
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
        xml(
          res,
          listingXml(
            contents: [(key: 'logs/a.txt', size: 12)],
            prefixes: ['logs/sub/'],
          ),
        );
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
          xml(
            res,
            listingXml(
              contents: [(key: 'a', size: 1)],
              truncated: true,
              nextToken: 'TOK2',
            ),
          );
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

    test(
      'listPages yields each page lazily, following continuation tokens',
      () async {
        final mock = await MockS3.start((req, res) {
          final token = req.query['continuation-token'];
          if (token == null) {
            xml(
              res,
              listingXml(
                contents: [(key: 'a', size: 1)],
                truncated: true,
                nextToken: 'T2',
              ),
            );
          } else {
            expect(token, 'T2');
            xml(res, listingXml(contents: [(key: 'b', size: 2)]));
          }
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        final pages = await c.listPages(prefix: '').toList();
        expect(pages.length, 2);
        expect(pages.first.objects.single.key, 'a');
        expect(pages.last.objects.single.key, 'b');
      },
    );

    test('pageSize is sent as max-keys', () async {
      final mock = await MockS3.start(
        (req, res) => xml(res, listingXml(contents: [])),
      );
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      await c.listPages(prefix: 'p/', pageSize: 250).toList();
      expect(mock.last.query['max-keys'], '250');
    });

    test('listAll with maxKeys stops early and flags truncation', () async {
      final mock = await MockS3.start((req, res) {
        final token = req.query['continuation-token'];
        if (token == null) {
          xml(
            res,
            listingXml(
              contents: [(key: 'a', size: 1), (key: 'b', size: 2)],
              truncated: true,
              nextToken: 'T2',
            ),
          );
        } else {
          xml(res, listingXml(contents: [(key: 'c', size: 3)]));
        }
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);

      final capped = await c.listAll(prefix: '', maxKeys: 2);
      expect(capped.objects.map((o) => o.key), [
        'a',
        'b',
      ]); // stopped after page 1
      expect(capped.isTruncated, isTrue); // signals more remain
      expect(mock.requests.length, 1, reason: 'did not fetch the second page');
    });

    test(
      'non-2xx with an XML error body throws a parsed S3Exception',
      () async {
        final mock = await MockS3.start((req, res) {
          xml(
            res,
            '<Error><Code>AccessDenied</Code><Message>nope</Message></Error>',
            status: 403,
          );
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        expect(
          () => c.listObjects(),
          throwsA(
            isA<S3Exception>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.message, 'message', 'nope'),
          ),
        );
      },
    );

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
        throwsA(
          isA<S3Exception>().having(
            (e) => e.message,
            'message',
            'internal boom',
          ),
        ),
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

    test(
      'putObject streams the body, sets length and reports progress',
      () async {
        final mock = await MockS3.start((req, res) => res.statusCode = 200);
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        final data = Uint8List.fromList(List.filled(2048, 7));
        final progress = <int>[];
        await c.putObject(
          'up.bin',
          Stream.value(data),
          data.length,
          onProgress: progress.add,
        );

        expect(mock.last.method, 'PUT');
        expect(mock.last.path, '/bk/up.bin');
        expect(mock.last.body.length, 2048);
        expect(
          mock.last.headers.value('x-amz-content-sha256'),
          unsignedPayload,
        );
        expect(progress.last, 2048);
      },
    );

    test(
      'a server that ignores Range (plain 200) still resumes correctly',
      () async {
        final full = List<int>.generate(100, (i) => i);
        final mock = await MockS3.start((req, res) {
          // Some S3-compatible servers ignore Range and return the whole object.
          expect(req.headers.value('range'), 'bytes=40-');
          res.statusCode = 200;
          res.contentLength = full.length;
          res.add(full);
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        final resp = await c.getObject('f.bin', rangeStart: 40);
        expect(
          resp.contentLength,
          60,
          reason: 'reports only the remaining bytes',
        );
        final got = <int>[];
        await for (final ch in resp.stream) {
          got.addAll(ch);
        }
        // The already-downloaded prefix is skipped, so appending stays correct.
        expect(got, full.sublist(40));
      },
    );

    test(
      'a 206 whose Content-Range starts at the wrong offset is rejected',
      () async {
        final full = List<int>.generate(100, (i) => i);
        final mock = await MockS3.start((req, res) {
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes 0-99/100'); // wrong offset
          res.contentLength = full.length;
          res.add(full);
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        await expectLater(
          c.getObject('f.bin', rangeStart: 40),
          throwsA(
            isA<S3Exception>().having(
              (e) => e.message,
              'message',
              contains('expected 40'),
            ),
          ),
        );
      },
    );

    test(
      'headObject returns content length + ETag from a HEAD request',
      () async {
        final mock = await MockS3.start((req, res) {
          res.statusCode = 200;
          res.contentLength = 1234;
          res.headers.set('ETag', '"abc123"');
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        final head = await c.headObject('dir/file.bin');
        expect(head.contentLength, 1234);
        expect(head.etag, '"abc123"');
        expect(mock.last.method, 'HEAD');
        expect(mock.last.path, '/bk/dir/file.bin');
        // A HEAD has no body, so it's signed with the empty-payload hash.
        expect(
          mock.last.headers.value('x-amz-content-sha256'),
          emptyBodySha256,
        );
      },
    );

    test(
      'headObject surfaces a 404 as an S3Exception without retrying',
      () async {
        final mock = await MockS3.start((req, res) => res.statusCode = 404);
        addTearDown(mock.stop);
        final c = client(mock)..retryBackoff = (_) => Duration.zero;
        addTearDown(c.close);
        await expectLater(
          c.headObject('nope.bin'),
          throwsA(
            isA<S3Exception>().having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
        expect(
          mock.requests.length,
          1,
          reason: 'a 404 is permanent — no retries',
        );
      },
    );

    test(
      'getObject sends a Range header and streams the tail when resuming',
      () async {
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
      },
    );

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
        throwsA(
          isA<S3Exception>().having((e) => e.message, 'message', 'denied'),
        ),
      );
    });
  });

  group('S3Client — multipart upload', () {
    test(
      'uploads parts and completes, round-tripping the bytes in order',
      () async {
        final partBodies = <int, List<int>>{};
        String? completeBody;
        final mock = await MockS3.start((req, res) {
          final q = req.query;
          if (req.method == 'POST' && q.containsKey('uploads')) {
            xml(
              res,
              '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
            );
          } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
            partBodies[int.parse(q['partNumber']!)] = req.body;
            res.headers.set('ETag', '"etag-${q['partNumber']}"');
            res.statusCode = 200;
          } else if (req.method == 'POST' && q.containsKey('uploadId')) {
            completeBody = utf8.decode(req.body);
            xml(
              res,
              '<CompleteMultipartUploadResult><ETag>"final"</ETag></CompleteMultipartUploadResult>',
            );
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        final payload = List<int>.generate(25, (i) => i);
        await c.putObjectMultipart(
          'big.bin',
          Stream.value(Uint8List.fromList(payload)),
          partSize: 10,
        );

        // 25 bytes / 10 ⇒ parts of 10, 10, 5.
        expect(partBodies.keys.toList()..sort(), [1, 2, 3]);
        expect(partBodies[1]!.length, 10);
        expect(partBodies[3]!.length, 5);
        final assembled = [for (var i = 1; i <= 3; i++) ...partBodies[i]!];
        expect(assembled, payload);
        // The Complete request lists every part + its ETag.
        expect(completeBody, contains('<PartNumber>1</PartNumber>'));
        expect(completeBody, contains('etag-3'));
      },
    );

    test(
      'an empty stream falls back to a zero-byte PutObject, not an empty part',
      () async {
        var parts = 0;
        var aborted = false;
        var plainPut = false;
        final mock = await MockS3.start((req, res) {
          final q = req.query;
          if (req.method == 'POST' && q.containsKey('uploads')) {
            xml(
              res,
              '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
            );
          } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
            parts++;
            res.headers.set('ETag', '"e"');
            res.statusCode = 200;
          } else if (req.method == 'DELETE' && q.containsKey('uploadId')) {
            aborted = true; // the unused multipart upload is cleaned up
            res.statusCode = 204;
          } else if (req.method == 'PUT') {
            plainPut = true;
            res.statusCode = 200;
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        await c.putObjectMultipart(
          'empty.bin',
          const Stream<Uint8List>.empty(),
          partSize: 10,
        );
        expect(parts, 0, reason: 'no zero-length part should be uploaded');
        expect(
          aborted,
          isTrue,
          reason: 'the empty multipart upload is aborted',
        );
        expect(
          plainPut,
          isTrue,
          reason: 'the empty object is written with a plain PUT',
        );
      },
    );

    test('aborts the upload when a part fails', () async {
      var aborted = false;
      final mock = await MockS3.start((req, res) {
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(
            res,
            '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
          );
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
        c.putObjectMultipart(
          'big.bin',
          Stream.value(Uint8List(25)),
          partSize: 10,
        ),
        throwsA(isA<S3Exception>()),
      );
      expect(aborted, isTrue, reason: 'a failed part must abort the upload');
    });

    test(
      'put picks multipart above the threshold and single PUT below it',
      () async {
        final seen = <String>[];
        final mock = await MockS3.start((req, res) {
          seen.add(
            '${req.method} ${req.query.containsKey('uploads')
                ? 'uploads'
                : req.query.containsKey('uploadId')
                ? 'uploadId'
                : req.query.containsKey('partNumber')
                ? 'part'
                : 'plain'}',
          );
          final q = req.query;
          if (req.method == 'POST' && q.containsKey('uploads')) {
            xml(
              res,
              '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
            );
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

        await c.put(
          'big.bin',
          Stream.value(Uint8List(25)),
          25,
        ); // > threshold ⇒ multipart
        expect(seen.where((s) => s.contains('uploads')), isNotEmpty);

        seen.clear();
        await c.put(
          'small.bin',
          Stream.value(Uint8List(5)),
          5,
        ); // ≤ threshold ⇒ single PUT
        expect(seen, ['PUT plain']);
      },
    );

    test(
      'an unknown-length source uploads via multipart, not Content-Length 0',
      () async {
        final partBodies = <int, List<int>>{};
        var singlePut = false;
        final mock = await MockS3.start((req, res) {
          final q = req.query;
          if (req.method == 'POST' && q.containsKey('uploads')) {
            xml(
              res,
              '<InitiateMultipartUploadResult><UploadId>U</UploadId></InitiateMultipartUploadResult>',
            );
          } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
            partBodies[int.parse(q['partNumber']!)] = req.body;
            res.headers.set('ETag', '"e${q['partNumber']}"');
            res.statusCode = 200;
          } else if (req.method == 'POST' && q.containsKey('uploadId')) {
            xml(
              res,
              '<CompleteMultipartUploadResult><ETag>"f"</ETag></CompleteMultipartUploadResult>',
            );
          } else if (req.method == 'PUT') {
            singlePut =
                true; // a plain PUT would carry the bogus Content-Length
            res.statusCode = 200;
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);

        final payload = Uint8List.fromList(List<int>.generate(40, (i) => i));
        final src = _UnsizedSource({'/f.bin': payload});
        final dst = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: 'bk',
            region: 'us-east-1',
            endpoint: mock.endpoint,
            useSsl: false,
            accessKeyId: 'AKIA',
            secretAccessKey: 's',
          ),
        );
        addTearDown(dst.dispose);

        final t = Transfer(
          name: 'f.bin',
          route: 'r',
          direction: TransferDirection.upload,
          sizeBytes: 0,
          session: 's',
        ); // size unknown to the queue too
        await TransferService().run(
          t: t,
          src: src,
          srcPath: '/f.bin',
          dst: dst,
          dstPath: 'f.bin',
          onStatus: () {},
        );

        expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
        expect(
          singlePut,
          isFalse,
          reason: 'must not fall back to a single PUT',
        );
        final assembled = [
          for (final k in (partBodies.keys.toList()..sort())) ...partBodies[k]!,
        ];
        expect(assembled, payload); // every byte arrived via multipart
      },
    );

    test('retries a transient part failure, then completes', () async {
      final attemptsByPart = <int, int>{};
      var completed = false;
      final mock = await MockS3.start((req, res) {
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(
            res,
            '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
          );
        } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
          final n = int.parse(q['partNumber']!);
          attemptsByPart[n] = (attemptsByPart[n] ?? 0) + 1;
          // Part 2 fails on its first attempt, succeeds on the retry.
          if (n == 2 && attemptsByPart[n] == 1) {
            xml(
              res,
              '<Error><Code>InternalError</Code><Message>blip</Message></Error>',
              status: 500,
            );
          } else {
            res.headers.set('ETag', '"e$n"');
            res.statusCode = 200;
          }
        } else if (req.method == 'POST' && q.containsKey('uploadId')) {
          completed = true;
          xml(
            res,
            '<CompleteMultipartUploadResult><ETag>"final"</ETag></CompleteMultipartUploadResult>',
          );
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final c = client(mock)..partBackoff = (_) => Duration.zero;
      addTearDown(c.close);

      await c.putObjectMultipart(
        'big.bin',
        Stream.value(Uint8List(25)),
        partSize: 10,
      );
      expect(attemptsByPart[2], 2, reason: 'part 2 retried once');
      expect(completed, isTrue);
    });

    test('aborts after exhausting part retries', () async {
      var attempts = 0;
      var aborted = false;
      final mock = await MockS3.start((req, res) {
        final q = req.query;
        if (req.method == 'POST' && q.containsKey('uploads')) {
          xml(
            res,
            '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
          );
        } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
          attempts++;
          xml(
            res,
            '<Error><Code>InternalError</Code><Message>down</Message></Error>',
            status: 500,
          );
        } else if (req.method == 'DELETE' && q.containsKey('uploadId')) {
          aborted = true;
          res.statusCode = 204;
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
        maxPartAttempts: 2,
      )..partBackoff = (_) => Duration.zero;
      addTearDown(c.close);

      await expectLater(
        c.putObjectMultipart(
          'big.bin',
          Stream.value(Uint8List(25)),
          partSize: 10,
        ),
        throwsA(isA<S3Exception>()),
      );
      expect(
        attempts,
        2,
        reason: 'tried exactly maxPartAttempts times before giving up',
      );
      expect(aborted, isTrue);
    });
  });

  group('S3Exception — rich error parsing', () {
    test(
      'parses Code/Message/RequestId/HostId and tags operation + bucket',
      () async {
        final mock = await MockS3.start((req, res) {
          xml(
            res,
            '<Error><Code>AccessDenied</Code><Message>Access Denied</Message>'
            '<RequestId>REQ123</RequestId><HostId>HOST456</HostId></Error>',
            status: 403,
          );
        });
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);

        await expectLater(
          c.putObject('data/file.csv', Stream.value(Uint8List(1)), 1),
          throwsA(
            isA<S3Exception>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.code, 'code', 'AccessDenied')
                .having((e) => e.message, 'message', 'Access Denied')
                .having((e) => e.requestId, 'requestId', 'REQ123')
                .having((e) => e.hostId, 'hostId', 'HOST456')
                .having((e) => e.operation, 'operation', 'PutObject')
                .having((e) => e.bucket, 'bucket', 'bk')
                .having((e) => e.key, 'key', 'data/file.csv'),
          ),
        );
      },
    );

    test('toString surfaces operation, code and diagnostics', () {
      const e = S3Exception(
        403,
        'Access Denied',
        code: 'AccessDenied',
        requestId: 'REQ123',
        operation: 'PutObject',
        bucket: 'bk',
        key: 'data/file.csv',
      );
      final s = e.toString();
      expect(s, contains('PutObject failed'));
      expect(s, contains('AccessDenied'));
      expect(s, contains('HTTP 403'));
      expect(s, contains('bucket=bk'));
      expect(s, contains('key=data/file.csv'));
      expect(s, contains('requestId=REQ123'));
    });
  });

  group('S3Client — credential refresh', () {
    test('re-resolves credentials on every request', () async {
      var current = const AwsCredentials('AKIAONE', 'secret');
      final mock = await MockS3.start(
        (req, res) => xml(res, listingXml(contents: [])),
      );
      addTearDown(mock.stop);
      final c = client(mock, credentials: () => current);
      addTearDown(c.close);

      await c.listObjects();
      expect(
        mock.last.headers.value('authorization'),
        contains('Credential=AKIAONE/'),
      );

      // Simulate a refreshed credentials file between requests.
      current = const AwsCredentials('AKIATWO', 'secret');
      await c.listObjects();
      expect(
        mock.last.headers.value('authorization'),
        contains('Credential=AKIATWO/'),
      );
    });
  });

  group('S3Backend — AWS profile mode', () {
    test(
      'reads ~/.aws credentials and picks up a refresh per request',
      () async {
        final dir = await Directory.systemTemp.createTemp('awsprof');
        addTearDown(() => dir.delete(recursive: true));
        final credFile = File('${dir.path}/credentials');
        credFile.writeAsStringSync(
          '[default]\naws_access_key_id=AKIAONE\naws_secret_access_key=s1\n',
        );
        debugAwsCredentialsPath = credFile.path;
        debugAwsEnv = {}; // isolate from any AWS_* vars in the test environment
        addTearDown(() {
          debugAwsCredentialsPath = null;
          debugAwsEnv = null;
        });

        final mock = await MockS3.start(
          (req, res) => xml(res, listingXml(contents: [])),
        );
        addTearDown(mock.stop);
        final b = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: 'bk',
            region: 'us-east-1',
            endpoint: mock.endpoint,
            useSsl: false,
            useAwsProfile: true,
          ),
        );
        addTearDown(b.dispose);
        expect(b.isReady, isTrue); // profile + bucket is enough

        await b.list('');
        expect(
          mock.last.headers.value('authorization'),
          contains('Credential=AKIAONE/'),
        );

        // External process refreshes the temporary credentials on disk.
        credFile.writeAsStringSync(
          '[default]\naws_access_key_id=AKIATWO\naws_secret_access_key=s2\n',
        );
        await b.list('');
        expect(
          mock.last.headers.value('authorization'),
          contains('Credential=AKIATWO/'),
        );
      },
    );

    test('loadAwsEnvCredentials reads the standard environment variables', () {
      debugAwsEnv = {
        'AWS_ACCESS_KEY_ID': 'AKIAENV',
        'AWS_SECRET_ACCESS_KEY': 'envsecret',
        'AWS_SESSION_TOKEN': 'envtoken',
      };
      addTearDown(() => debugAwsEnv = null);
      final c = loadAwsEnvCredentials()!;
      expect(c.accessKeyId, 'AKIAENV');
      expect(c.secretAccessKey, 'envsecret');
      expect(c.sessionToken, 'envtoken');

      // The secret is required — a lone key yields no credentials.
      debugAwsEnv = {'AWS_ACCESS_KEY_ID': 'AKIAENV'};
      expect(loadAwsEnvCredentials(), isNull);
    });

    test(
      'environment credentials take precedence over the shared profile',
      () async {
        // A profile on disk that should be ignored while env vars are present.
        final dir = await Directory.systemTemp.createTemp('awsenv');
        addTearDown(() => dir.delete(recursive: true));
        File('${dir.path}/credentials').writeAsStringSync(
          '[default]\naws_access_key_id=AKIAFILE\naws_secret_access_key=filesecret\n',
        );
        debugAwsCredentialsPath = '${dir.path}/credentials';
        debugAwsEnv = {
          'AWS_ACCESS_KEY_ID': 'AKIAENV',
          'AWS_SECRET_ACCESS_KEY': 'envsecret',
        };
        addTearDown(() {
          debugAwsCredentialsPath = null;
          debugAwsEnv = null;
        });

        final mock = await MockS3.start(
          (req, res) => xml(res, listingXml(contents: [])),
        );
        addTearDown(mock.stop);
        final b = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: 'bk',
            region: 'us-east-1',
            endpoint: mock.endpoint,
            useSsl: false,
            useAwsProfile: true,
          ),
        );
        addTearDown(b.dispose);

        await b.list('');
        expect(
          mock.last.headers.value('authorization'),
          contains('Credential=AKIAENV/'),
        );
      },
    );

    test('a missing profile surfaces a clear error', () async {
      final dir = await Directory.systemTemp.createTemp('awsprof2');
      addTearDown(() => dir.delete(recursive: true));
      debugAwsCredentialsPath = '${dir.path}/credentials'; // does not exist
      debugAwsEnv = {}; // isolate from any AWS_* vars in the test environment
      addTearDown(() {
        debugAwsCredentialsPath = null;
        debugAwsEnv = null;
      });

      final b = S3Backend(
        Connection(
          name: 's3',
          protocol: Protocol.s3,
          bucket: 'bk',
          region: 'us-east-1',
          endpoint: '127.0.0.1:1',
          useSsl: false,
          useAwsProfile: true,
          awsProfile: 'missing',
        ),
      );
      addTearDown(b.dispose);
      await expectLater(
        b.list(''),
        throwsA(
          isA<S3Exception>().having(
            (e) => e.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    });
  });

  group('S3Client — service ops', () {
    test('listBuckets parses bucket names + creation dates (GET /)', () async {
      final mock = await MockS3.start(
        (req, res) => xml(
          res,
          '<?xml version="1.0"?><ListAllMyBucketsResult><Buckets>'
          '<Bucket><Name>alpha</Name><CreationDate>2023-01-05T10:20:30.000Z</CreationDate></Bucket>'
          '<Bucket><Name>beta</Name></Bucket>'
          '</Buckets></ListAllMyBucketsResult>',
        ),
      );
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      final buckets = await c.listBuckets();
      expect(buckets.map((b) => b.name), ['alpha', 'beta']);
      expect(buckets[0].created, DateTime.parse('2023-01-05T10:20:30.000Z'));
      expect(buckets[1].created, isNull); // no CreationDate element
      expect(mock.last.path, '/');
    });

    test('getBucketLocation maps the region', () async {
      for (final pair in [
        ('eu-west-1', 'eu-west-1'),
        ('', 'us-east-1'),
        ('EU', 'eu-west-1'),
      ]) {
        final mock = await MockS3.start(
          (req, res) =>
              xml(res, '<LocationConstraint>${pair.$1}</LocationConstraint>'),
        );
        final c = client(mock);
        expect(
          await c.getBucketLocation('b'),
          pair.$2,
          reason: 'for "${pair.$1}"',
        );
        c.close();
        await mock.stop();
      }
    });
  });

  group('S3Backend — bucket discovery (no bucket configured)', () {
    test('lists the account buckets, then a bucket\'s objects', () async {
      final mock = await MockS3.start((req, res) {
        if (req.path == '/') {
          xml(
            res,
            '<?xml version="1.0"?><ListAllMyBucketsResult><Buckets>'
            '<Bucket><Name>alpha</Name><CreationDate>2023-01-05T10:20:30.000Z</CreationDate></Bucket>'
            '<Bucket><Name>beta</Name></Bucket>'
            '</Buckets></ListAllMyBucketsResult>',
          );
        } else if (req.query['list-type'] == '2') {
          xml(
            res,
            listingXml(
              contents: [(key: 'report.csv', size: 9)],
              prefixes: ['logs/'],
            ),
          );
        } else {
          res.statusCode = 200;
        }
      });
      addTearDown(mock.stop);
      final b = S3Backend(
        Connection(
          name: 's3',
          protocol: Protocol.s3,
          bucket: '', // ← discovery
          region: 'us-east-1',
          endpoint: mock.endpoint,
          useSsl: false,
          accessKeyId: 'AKIA',
          secretAccessKey: 's',
        ),
      );
      addTearDown(b.dispose);
      expect(b.isReady, isTrue); // creds present, bucket optional

      // Root → the account's buckets, as folders, annotated with their
      // creation date (region is skipped here since a custom endpoint is set).
      final root = await b.list('');
      expect(root.map((e) => e.name), containsAll(['alpha', 'beta']));
      expect(root.every((e) => e.isDir && !e.isParent), isTrue);
      final alpha = root.firstWhere((e) => e.name == 'alpha');
      expect(alpha.modified, isNotEmpty); // ListBuckets CreationDate surfaced
      expect(root.firstWhere((e) => e.name == 'beta').modified, isEmpty);

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
      final b = S3Backend(
        Connection(
          name: 's3',
          protocol: Protocol.s3,
          bucket: '',
          region: 'us-east-1',
          endpoint: mock.endpoint,
          useSsl: false,
          accessKeyId: 'AKIA',
          secretAccessKey: 's',
        ),
      );
      addTearDown(b.dispose);
      await expectLater(
        b.delete('alpha/', isDir: true),
        throwsUnsupportedError,
      );
    });

    test(
      'mutableAt is false at the bucket-list root, true inside a bucket',
      () {
        final discovery = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: '',
            region: 'us-east-1',
            accessKeyId: 'AKIA',
            secretAccessKey: 's',
          ),
        );
        addTearDown(discovery.dispose);
        // The account-level bucket list isn't a writable directory.
        expect(discovery.mutableAt(''), isFalse);
        // Inside a bucket, mutation is allowed again.
        expect(discovery.mutableAt('alpha/'), isTrue);
        expect(discovery.mutableAt('alpha/logs/'), isTrue);

        // A fixed-bucket connection has no read-only root.
        final fixed = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: 'bk',
            region: 'us-east-1',
            accessKeyId: 'AKIA',
            secretAccessKey: 's',
          ),
        );
        addTearDown(fixed.dispose);
        expect(fixed.mutableAt(''), isTrue);
        expect(fixed.mutableAt('any/prefix/'), isTrue);
      },
    );
  });

  group('S3Client — addressing', () {
    test(
      'omits the default port and uses the http scheme when useSsl is false',
      () async {
        // Bind a server, but assert on the Host header it receives.
        final mock = await MockS3.start(
          (req, res) => xml(res, listingXml(contents: [])),
        );
        addTearDown(mock.stop);
        final c = client(mock);
        addTearDown(c.close);
        await c.listObjects();
        // Custom (non-443/80) port → included in the Host header.
        expect(mock.last.headers.value('host'), '127.0.0.1:${mock.port}');
      },
    );
  });

  // ── S3Backend on top of the mock server (covers storage_backend.dart) ──
  group('S3Backend (via mock server)', () {
    S3Backend backend(MockS3 mock) => S3Backend(
      Connection(
        name: 's3',
        protocol: Protocol.s3,
        bucket: 'bk',
        region: 'us-east-1',
        endpoint: mock.endpoint,
        useSsl: false,
        accessKeyId: 'AKIA',
        secretAccessKey: 'secret',
      ),
    );

    test('listIncremental emits a growing snapshot per page', () async {
      final mock = await MockS3.start((req, res) {
        final token = req.query['continuation-token'];
        if (token == null) {
          xml(
            res,
            listingXml(
              contents: [(key: 'a.txt', size: 1)],
              truncated: true,
              nextToken: 'T2',
            ),
          );
        } else {
          xml(res, listingXml(contents: [(key: 'b.txt', size: 2)]));
        }
      });
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);

      final snapshots = await b.listIncremental('').toList();
      expect(snapshots.length, 2, reason: 'one emission per S3 page');
      // Each snapshot is cumulative: the first page's object is present in both.
      expect(snapshots.first.map((e) => e.name), ['a.txt']);
      expect(snapshots.last.map((e) => e.name), ['a.txt', 'b.txt']);
    });

    test(
      'list maps CommonPrefixes to folders and Contents to files, with ..',
      () async {
        final mock = await MockS3.start((req, res) {
          xml(
            res,
            listingXml(
              contents: [
                (key: 'logs/app.log', size: 5),
                (key: 'logs/', size: 0), // the prefix placeholder — skipped
              ],
              prefixes: ['logs/2025/'],
            ),
          );
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
      },
    );

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

    test(
      'a copy that 200s with an <Error> body fails rename without deleting the source',
      () async {
        var deleted = false;
        final mock = await MockS3.start((req, res) {
          if (req.method == 'DELETE') {
            deleted = true;
            res.statusCode = 204;
          } else {
            // CopyObject "succeeds" at the HTTP layer but reports an error body.
            xml(
              res,
              '<Error><Code>InternalError</Code><Message>copy failed</Message></Error>',
            );
          }
        });
        addTearDown(mock.stop);
        final b = backend(mock);
        addTearDown(b.dispose);

        await expectLater(
          b.rename('a.txt', 'b.txt'),
          throwsA(isA<S3Exception>()),
        );
        expect(
          deleted,
          isFalse,
          reason: 'the source must survive a failed copy',
        );
      },
    );

    test(
      'delete (recursive) lists the prefix and batch-deletes the keys',
      () async {
        var listed = false;
        var batchDeletes = 0;
        String? deleteBody;
        final mock = await MockS3.start((req, res) {
          if (req.query.containsKey('list-type')) {
            listed = true;
            xml(
              res,
              listingXml(
                contents: [(key: 'dir/a', size: 1), (key: 'dir/b', size: 1)],
              ),
            );
          } else if (req.method == 'POST' && req.query.containsKey('delete')) {
            batchDeletes++;
            deleteBody = utf8.decode(req.body);
            xml(
              res,
              '<?xml version="1.0"?><DeleteResult></DeleteResult>',
            ); // quiet: all ok
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);
        final b = backend(mock);
        addTearDown(b.dispose);
        await b.delete('dir/', isDir: true);
        expect(listed, isTrue);
        expect(
          batchDeletes,
          1,
          reason: 'one DeleteObjects call, not one DELETE per key',
        );
        expect(deleteBody, contains('<Key>dir/a</Key>'));
        expect(deleteBody, contains('<Key>dir/b</Key>'));
      },
    );

    test('deleteObjects returns the keys S3 reports as failed', () async {
      final mock = await MockS3.start((req, res) {
        xml(
          res,
          '<?xml version="1.0"?><DeleteResult>'
          '<Error><Key>dir/b</Key><Code>AccessDenied</Code></Error></DeleteResult>',
        );
      });
      addTearDown(mock.stop);
      final c = client(mock);
      addTearDown(c.close);
      final failed = await c.deleteObjects(['dir/a', 'dir/b']);
      expect(failed, ['dir/b']);
      // The request carried a Content-MD5 of the body (required by S3).
      expect(mock.last.headers.value('content-md5'), isNotNull);
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
      await b.write(
        'dst.bin',
        handle.stream.map(Uint8List.fromList),
        handle.length!,
      );
      expect(stored, payload);
    });

    test(
      'sizeOf issues one HEAD instead of listing the parent prefix',
      () async {
        final mock = await MockS3.start((req, res) {
          expect(req.method, 'HEAD', reason: 'must not fall back to a listing');
          res.statusCode = 200;
          res.contentLength = 4096;
          res.headers.set('ETag', '"e"');
        });
        addTearDown(mock.stop);
        final b = backend(mock);
        addTearDown(b.dispose);
        expect(await b.sizeOf('folder/file.bin'), 4096);
        expect(mock.requests.length, 1);
        expect(mock.last.path, '/bk/folder/file.bin');
      },
    );

    test('sizeOf returns null for a missing object (HEAD 404)', () async {
      final mock = await MockS3.start((req, res) => res.statusCode = 404);
      addTearDown(mock.stop);
      final b = backend(mock);
      addTearDown(b.dispose);
      expect(await b.sizeOf('nope.bin'), isNull);
    });
  });

  group('S3Client — retry classification', () {
    test('isRetryableS3Failure: transient failures yes, client errors no', () {
      // Retryable: throttling / server-side trouble / socket-level failures.
      expect(isRetryableS3Failure(const S3Exception(500, 'x')), isTrue);
      expect(isRetryableS3Failure(const S3Exception(502, 'x')), isTrue);
      expect(isRetryableS3Failure(const S3Exception(503, 'x')), isTrue);
      expect(isRetryableS3Failure(const S3Exception(504, 'x')), isTrue);
      expect(isRetryableS3Failure(const S3Exception(429, 'x')), isTrue);
      expect(
        isRetryableS3Failure(const S3Exception(200, 'x', code: 'SlowDown')),
        isTrue,
      );
      expect(
        isRetryableS3Failure(
          const S3Exception(400, 'x', code: 'RequestTimeout'),
        ),
        isTrue,
      );
      expect(
        isRetryableS3Failure(
          const S3Exception(200, 'x', code: 'InternalError'),
        ),
        isTrue,
      );
      expect(
        isRetryableS3Failure(const SocketException('connection reset')),
        isTrue,
      );
      expect(isRetryableS3Failure(TimeoutException('slow')), isTrue);
      // Permanent: auth/client errors must fail immediately.
      expect(
        isRetryableS3Failure(const S3Exception(403, 'x', code: 'AccessDenied')),
        isFalse,
      );
      expect(
        isRetryableS3Failure(const S3Exception(404, 'x', code: 'NoSuchKey')),
        isFalse,
      );
      expect(
        isRetryableS3Failure(
          const S3Exception(400, 'x', code: 'InvalidRequest'),
        ),
        isFalse,
      );
      expect(isRetryableS3Failure(ArgumentError('not s3')), isFalse);
    });

    test('an idempotent request retries a 503 and then succeeds', () async {
      var attempts = 0;
      final mock = await MockS3.start((req, res) {
        attempts++;
        if (attempts == 1) {
          xml(
            res,
            '<Error><Code>SlowDown</Code><Message>chill</Message></Error>',
            status: 503,
          );
        } else {
          xml(res, listingXml(contents: [(key: 'a', size: 1)]));
        }
      });
      addTearDown(mock.stop);
      final c = client(mock)..retryBackoff = (_) => Duration.zero;
      addTearDown(c.close);

      final page = await c.listObjects();
      expect(page.objects.single.key, 'a');
      expect(attempts, 2, reason: 'first attempt 503, second succeeded');
    });

    test('a 403 is never retried', () async {
      final mock = await MockS3.start((req, res) {
        xml(
          res,
          '<Error><Code>AccessDenied</Code><Message>nope</Message></Error>',
          status: 403,
        );
      });
      addTearDown(mock.stop);
      final c = client(mock)..retryBackoff = (_) => Duration.zero;
      addTearDown(c.close);

      await expectLater(c.listObjects(), throwsA(isA<S3Exception>()));
      expect(
        mock.requests.length,
        1,
        reason: '403 is permanent — one attempt only',
      );
    });

    test(
      'retries stop after maxRequestAttempts, surfacing the last error',
      () async {
        final mock = await MockS3.start((req, res) {
          xml(
            res,
            '<Error><Code>InternalError</Code><Message>down</Message></Error>',
            status: 500,
          );
        });
        addTearDown(mock.stop);
        final c = S3Client(
          bucket: 'bk',
          region: 'us-east-1',
          endpoint: mock.endpoint,
          useSsl: false,
          credentials: () => const AwsCredentials('AKIA', 'secret'),
          maxRequestAttempts: 2,
        )..retryBackoff = (_) => Duration.zero;
        addTearDown(c.close);

        await expectLater(c.deleteObject('x'), throwsA(isA<S3Exception>()));
        expect(mock.requests.length, 2);
      },
    );

    test(
      'a 403 part failure aborts immediately instead of burning retries',
      () async {
        var partAttempts = 0;
        var aborted = false;
        final mock = await MockS3.start((req, res) {
          final q = req.query;
          if (req.method == 'POST' && q.containsKey('uploads')) {
            xml(
              res,
              '<InitiateMultipartUploadResult><UploadId>UP1</UploadId></InitiateMultipartUploadResult>',
            );
          } else if (req.method == 'PUT' && q.containsKey('partNumber')) {
            partAttempts++;
            xml(
              res,
              '<Error><Code>AccessDenied</Code><Message>denied</Message></Error>',
              status: 403,
            );
          } else if (req.method == 'DELETE' && q.containsKey('uploadId')) {
            aborted = true;
            res.statusCode = 204;
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);
        final c = client(mock)..partBackoff = (_) => Duration.zero;
        addTearDown(c.close);

        await expectLater(
          c.putObjectMultipart(
            'big.bin',
            Stream.value(Uint8List(25)),
            partSize: 10,
          ),
          throwsA(
            isA<S3Exception>().having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
        expect(
          partAttempts,
          1,
          reason: 'a 403 would fail identically every time',
        );
        expect(aborted, isTrue);
      },
    );
  });

  group('S3Backend — incremental bucket discovery regions', () {
    test(
      'yields the bucket list promptly, then fills regions in bounded batches',
      () async {
        const bucketCount = 20;
        var inFlight = 0, maxInFlight = 0;
        final mock = await MockS3.start((req, res) async {
          if (req.path == '/') {
            final xmlBuckets = [
              for (var i = 0; i < bucketCount; i++)
                '<Bucket><Name>bucket-$i</Name></Bucket>',
            ].join();
            xml(
              res,
              '<?xml version="1.0"?><ListAllMyBucketsResult><Buckets>'
              '$xmlBuckets</Buckets></ListAllMyBucketsResult>',
            );
          } else if (req.query.containsKey('location')) {
            inFlight++;
            maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
            await Future<void>.delayed(const Duration(milliseconds: 15));
            inFlight--;
            xml(res, '<LocationConstraint>eu-west-1</LocationConstraint>');
          } else {
            res.statusCode = 200;
          }
        });
        addTearDown(mock.stop);
        final b = S3Backend(
          Connection(
            name: 's3',
            protocol: Protocol.s3,
            bucket: '',
            region: 'us-east-1',
            endpoint: mock.endpoint,
            useSsl: false,
            accessKeyId: 'AKIA',
            secretAccessKey: 's',
          ),
        )..debugResolveRegionsWithEndpoint = true;
        addTearDown(b.dispose);

        final snapshots = await b.listIncremental('').toList();
        // First snapshot arrives before any GetBucketLocation completes…
        expect(snapshots.first.length, bucketCount);
        expect(
          snapshots.first.every((e) => e.perms.isEmpty),
          isTrue,
          reason: 'regions start blank — the list must not block on them',
        );
        // …and the final one has every region filled in.
        expect(snapshots.last.every((e) => e.perms == 'eu-west-1'), isTrue);
        // 20 buckets in batches of 8 → 1 prompt snapshot + 3 region batches.
        expect(snapshots.length, 4);
        expect(
          maxInFlight,
          lessThanOrEqualTo(8),
          reason:
              'region lookups must be bounded, not one-per-bucket in parallel',
        );

        // The regions were cached: a re-list resolves nothing new.
        final before = mock.requests.length;
        final again = await b.listIncremental('').toList();
        expect(again.single.every((e) => e.perms == 'eu-west-1'), isTrue);
        expect(
          mock.requests.length,
          before + 1,
          reason: 'only ListBuckets again',
        );
      },
    );
  });
}
