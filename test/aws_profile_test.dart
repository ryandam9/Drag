import 'dart:io';

import 'package:drag/fs/aws/aws_profile.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('awscfg'));
  tearDown(() async {
    debugAwsCredentialsPath = null;
    debugAwsConfigPath = null;
    await dir.delete(recursive: true);
  });

  File write(String name, String body) => File('${dir.path}/$name')..writeAsStringSync(body);

  test('loads default and named profiles, including the session token', () {
    final f = write('credentials', '''
# a comment
; another comment
[default]
aws_access_key_id = AKIADEFAULT
aws_secret_access_key = secretdef

[work]
aws_access_key_id = AKIAWORK
aws_secret_access_key = secretwork
aws_session_token = TOKEN123
''');
    final def = loadAwsCredentials('default', path: f.path)!;
    expect(def.accessKeyId, 'AKIADEFAULT');
    expect(def.secretAccessKey, 'secretdef');
    expect(def.sessionToken, isNull);

    final work = loadAwsCredentials('work', path: f.path)!;
    expect(work.accessKeyId, 'AKIAWORK');
    expect(work.sessionToken, 'TOKEN123');
  });

  test('returns null for a missing profile or missing file', () {
    final f = write('credentials', '[default]\naws_access_key_id=x\naws_secret_access_key=y\n');
    expect(loadAwsCredentials('nope', path: f.path), isNull);
    expect(loadAwsCredentials('default', path: '${dir.path}/missing'), isNull);
  });

  test('an incomplete profile (no secret) resolves to null', () {
    final f = write('credentials', '[default]\naws_access_key_id=x\n');
    expect(loadAwsCredentials('default', path: f.path), isNull);
  });

  test('reads region from config, handling [default] and [profile NAME]', () {
    final f = write('config', '''
[default]
region = us-east-1

[profile work]
region = eu-west-1
''');
    expect(loadAwsRegion('default', path: f.path), 'us-east-1');
    expect(loadAwsRegion('work', path: f.path), 'eu-west-1');
    expect(loadAwsRegion('absent', path: f.path), isNull);
  });

  test('resolveAwsProfile prefers the connection profile, else default', () {
    expect(resolveAwsProfile(Connection(name: 's', awsProfile: 'foo')), 'foo');
    // No connection profile → $AWS_PROFILE or 'default'; both are non-empty.
    expect(resolveAwsProfile(Connection(name: 's')), isNotEmpty);
  });
}
