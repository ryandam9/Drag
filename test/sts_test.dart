import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drag/fs/aws/s3_client.dart';
import 'package:drag/fs/aws/sigv4.dart';
import 'package:drag/fs/aws/sts_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _Req {
  final String body;
  _Req(this.body);
}

/// A tiny in-process STS server. Returns the canned response from [responder].
Future<(HttpServer, List<_Req>)> _startSts(
    FutureOr<void> Function(_Req req, HttpResponse res) responder) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final reqs = <_Req>[];
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    final r = _Req(body);
    reqs.add(r);
    await responder(r, req.response);
    await req.response.close();
  });
  return (server, reqs);
}

String _assumeXml({
  String ak = 'ASIAEXAMPLE',
  String sk = 'tempsecret',
  String token = 'tok',
  required String expiration,
}) =>
    '<AssumeRoleResponse><AssumeRoleResult><Credentials>'
    '<AccessKeyId>$ak</AccessKeyId><SecretAccessKey>$sk</SecretAccessKey>'
    '<SessionToken>$token</SessionToken><Expiration>$expiration</Expiration>'
    '</Credentials></AssumeRoleResult></AssumeRoleResponse>';

void main() {
  test('assumeRole posts AssumeRole and parses the temporary credentials', () async {
    final (server, reqs) = await _startSts((r, res) {
      res.headers.contentType = ContentType('text', 'xml');
      res.write(_assumeXml(expiration: '2030-01-01T00:00:00Z'));
    });
    addTearDown(() => server.close(force: true));

    final c = StsClient(region: 'us-east-1', endpoint: '127.0.0.1:${server.port}', useSsl: false);
    addTearDown(c.close);

    final assumed = await c.assumeRole(
      roleArn: 'arn:aws:iam::123456789012:role/Reader',
      sessionName: 'drag',
      baseCredentials: const AwsCredentials('AKIABASE', 'basesecret'),
    );

    expect(assumed.credentials.accessKeyId, 'ASIAEXAMPLE');
    expect(assumed.credentials.secretAccessKey, 'tempsecret');
    expect(assumed.credentials.sessionToken, 'tok');
    expect(assumed.expiration, DateTime.utc(2030, 1, 1));

    final body = reqs.single.body;
    expect(body, contains('Action=AssumeRole'));
    expect(body, contains('RoleArn=arn')); // form-encoded ARN
    expect(body, contains('RoleSessionName=drag'));
  });

  test('the credential provider caches, then re-assumes near expiry', () async {
    var calls = 0;
    final (server, _) = await _startSts((r, res) {
      calls++;
      res.write(_assumeXml(ak: 'ASIA$calls', expiration: '2030-01-01T01:00:00Z'));
    });
    addTearDown(() => server.close(force: true));

    final sts = StsClient(region: 'us-east-1', endpoint: '127.0.0.1:${server.port}', useSsl: false);
    addTearDown(sts.close);

    var now = DateTime.utc(2030, 1, 1, 0, 0, 0); // an hour before expiry
    final provider = AssumeRoleCredentialsProvider(
      sts: sts,
      roleArn: 'arn:aws:iam::1:role/R',
      sessionName: 'drag',
      baseCredentials: () => const AwsCredentials('AKIABASE', 'basesecret'),
      clock: () => now,
    );

    expect((await provider.resolve()).accessKeyId, 'ASIA1');
    // Still well within validity → served from cache, no new STS call.
    expect((await provider.resolve()).accessKeyId, 'ASIA1');
    expect(calls, 1);

    // Advance into the 5-minute refresh window (expiry 01:00) → re-assume.
    now = DateTime.utc(2030, 1, 1, 0, 56, 0);
    expect((await provider.resolve()).accessKeyId, 'ASIA2');
    expect(calls, 2);
  });

  test('an STS error surfaces a parsed S3Exception', () async {
    final (server, _) = await _startSts((r, res) {
      res.statusCode = 403;
      res.write('<ErrorResponse><Error><Code>AccessDenied</Code>'
          '<Message>not authorized to assume</Message></Error></ErrorResponse>');
    });
    addTearDown(() => server.close(force: true));

    final c = StsClient(region: 'us-east-1', endpoint: '127.0.0.1:${server.port}', useSsl: false);
    addTearDown(c.close);

    await expectLater(
      c.assumeRole(roleArn: 'arn', sessionName: 'drag', baseCredentials: const AwsCredentials('A', 'S')),
      throwsA(isA<S3Exception>().having((e) => e.message, 'message', 'not authorized to assume')),
    );
  });
}
