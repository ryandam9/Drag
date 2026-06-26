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

  test('credential_process runs the helper and parses its JSON output', () {
    final f = write('credentials', '''
[sso]
credential_process = printf '{"Version":1,"AccessKeyId":"AKIAPROC","SecretAccessKey":"procsecret","SessionToken":"PROCTOKEN"}'
''');
    final creds = loadAwsCredentials('sso', path: f.path);
    expect(creds, isNotNull);
    expect(creds!.accessKeyId, 'AKIAPROC');
    expect(creds.secretAccessKey, 'procsecret');
    expect(creds.sessionToken, 'PROCTOKEN');
  }, skip: Platform.isWindows ? 'uses /bin/sh' : false);

  test('a failing credential_process yields no credentials', () {
    final f = write('credentials', '''
[bad]
credential_process = sh -c 'exit 3'
''');
    expect(loadAwsCredentials('bad', path: f.path), isNull);
  }, skip: Platform.isWindows ? 'uses /bin/sh' : false);

  test('a profile defined only in ~/.aws/config is honoured', () {
    debugAwsCredentialsPath = '${dir.path}/credentials'; // absent
    final cfg = write('config', '''
[profile only-config]
aws_access_key_id = AKIACFG
aws_secret_access_key = cfgsecret
''');
    debugAwsConfigPath = cfg.path;
    final creds = loadAwsCredentials('only-config');
    expect(creds, isNotNull);
    expect(creds!.accessKeyId, 'AKIACFG');
  });

  test('region is inherited from source_profile when absent', () {
    final f = write('config', '''
[profile base]
region = ap-south-1

[profile chained]
source_profile = base
role_arn = arn:aws:iam::123:role/x
''');
    expect(loadAwsRegion('chained', path: f.path), 'ap-south-1');
  });
}
