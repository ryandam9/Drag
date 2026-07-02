import 'dart:io';

import 'package:drag/fs/aws/aws_profile.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('awscfg');
    debugClearCredentialProcessCache();
  });
  tearDown(() async {
    debugAwsCredentialsPath = null;
    debugAwsConfigPath = null;
    debugCredentialProcessRunner = null;
    debugAwsNow = null;
    debugClearCredentialProcessCache();
    await dir.delete(recursive: true);
  });

  File write(String name, String body) => File('${dir.path}/$name')..writeAsStringSync(body);

  test('loads default and named profiles, including the session token', () async {
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
    final def = (await loadAwsCredentials('default', path: f.path))!;
    expect(def.accessKeyId, 'AKIADEFAULT');
    expect(def.secretAccessKey, 'secretdef');
    expect(def.sessionToken, isNull);

    final work = (await loadAwsCredentials('work', path: f.path))!;
    expect(work.accessKeyId, 'AKIAWORK');
    expect(work.sessionToken, 'TOKEN123');
  });

  test('returns null for a missing profile or missing file', () async {
    final f = write('credentials', '[default]\naws_access_key_id=x\naws_secret_access_key=y\n');
    expect(await loadAwsCredentials('nope', path: f.path), isNull);
    expect(await loadAwsCredentials('default', path: '${dir.path}/missing'), isNull);
  });

  test('an incomplete profile (no secret) resolves to null', () async {
    final f = write('credentials', '[default]\naws_access_key_id=x\n');
    expect(await loadAwsCredentials('default', path: f.path), isNull);
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

  test('credential_process runs the helper and parses its JSON output', () async {
    final f = write('credentials', '''
[sso]
credential_process = printf '{"Version":1,"AccessKeyId":"AKIAPROC","SecretAccessKey":"procsecret","SessionToken":"PROCTOKEN"}'
''');
    final creds = await loadAwsCredentials('sso', path: f.path);
    expect(creds, isNotNull);
    expect(creds!.accessKeyId, 'AKIAPROC');
    expect(creds.secretAccessKey, 'procsecret');
    expect(creds.sessionToken, 'PROCTOKEN');
  }, skip: Platform.isWindows ? 'uses /bin/sh' : false);

  test('a failing credential_process yields no credentials', () async {
    final f = write('credentials', '''
[bad]
credential_process = sh -c 'exit 3'
''');
    expect(await loadAwsCredentials('bad', path: f.path), isNull);
  }, skip: Platform.isWindows ? 'uses /bin/sh' : false);

  test('a profile defined only in ~/.aws/config is honoured', () async {
    debugAwsCredentialsPath = '${dir.path}/credentials'; // absent
    final cfg = write('config', '''
[profile only-config]
aws_access_key_id = AKIACFG
aws_secret_access_key = cfgsecret
''');
    debugAwsConfigPath = cfg.path;
    final creds = await loadAwsCredentials('only-config');
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

  group('credential_process caching', () {
    File credFile() => write('credentials', '''
[sso]
credential_process = my-helper --profile sso
''');

    test('caches the result — the helper runs once, not per request', () async {
      var runs = 0;
      debugCredentialProcessRunner = (command) async {
        runs++;
        expect(command, 'my-helper --profile sso');
        return ProcessResult(0, 0,
            '{"Version":1,"AccessKeyId":"AKIA1","SecretAccessKey":"s1"}', '');
      };
      final f = credFile();
      final a = await loadAwsCredentials('sso', path: f.path);
      final b = await loadAwsCredentials('sso', path: f.path);
      expect(a!.accessKeyId, 'AKIA1');
      expect(b!.accessKeyId, 'AKIA1');
      expect(runs, 1, reason: 'second load must hit the cache');
    });

    test('without Expiration the cache lasts ~5 minutes', () async {
      var runs = 0;
      var now = DateTime.utc(2026, 7, 2, 12, 0, 0);
      debugAwsNow = () => now;
      debugCredentialProcessRunner = (command) async {
        runs++;
        return ProcessResult(0, 0,
            '{"Version":1,"AccessKeyId":"AKIA$runs","SecretAccessKey":"s"}', '');
      };
      final f = credFile();

      await loadAwsCredentials('sso', path: f.path);
      now = now.add(const Duration(minutes: 4));
      expect((await loadAwsCredentials('sso', path: f.path))!.accessKeyId, 'AKIA1');
      expect(runs, 1, reason: 'still inside the default TTL');

      now = now.add(const Duration(minutes: 2)); // 6 min total → expired
      expect((await loadAwsCredentials('sso', path: f.path))!.accessKeyId, 'AKIA2');
      expect(runs, 2, reason: 'the default TTL lapsed → helper re-run');
    });

    test('Expiration is honoured with a ~1 minute safety skew', () async {
      var runs = 0;
      var now = DateTime.utc(2026, 7, 2, 12, 0, 0);
      debugAwsNow = () => now;
      final expiration = now.add(const Duration(minutes: 10)).toIso8601String();
      debugCredentialProcessRunner = (command) async {
        runs++;
        return ProcessResult(0, 0,
            '{"Version":1,"AccessKeyId":"AKIA$runs","SecretAccessKey":"s",'
            '"SessionToken":"t","Expiration":"$expiration"}', '');
      };
      final f = credFile();

      await loadAwsCredentials('sso', path: f.path);
      // 8 min in: still comfortably before (Expiration − skew) → cached.
      now = now.add(const Duration(minutes: 8));
      await loadAwsCredentials('sso', path: f.path);
      expect(runs, 1);

      // 9.5 min in: within the 1-minute skew of the 10-minute expiry → re-run
      // (credentials would otherwise die mid-request).
      now = now.add(const Duration(minutes: 1, seconds: 30));
      await loadAwsCredentials('sso', path: f.path);
      expect(runs, 2, reason: 'refreshed before the reported Expiration');
    });

    test('a helper failure is not cached — the next request retries', () async {
      var runs = 0;
      debugCredentialProcessRunner = (command) async {
        runs++;
        return runs == 1
            ? ProcessResult(0, 3, '', 'boom') // transient failure
            : ProcessResult(0, 0, '{"Version":1,"AccessKeyId":"AKIAOK","SecretAccessKey":"s"}', '');
      };
      final f = credFile();
      expect(await loadAwsCredentials('sso', path: f.path), isNull);
      expect((await loadAwsCredentials('sso', path: f.path))!.accessKeyId, 'AKIAOK');
      expect(runs, 2);
    });

    test('the cache is per profile + command', () async {
      var runs = 0;
      debugCredentialProcessRunner = (command) async {
        runs++;
        return ProcessResult(0, 0,
            '{"Version":1,"AccessKeyId":"AKIA-${command.hashCode}","SecretAccessKey":"s"}', '');
      };
      final f = write('credentials', '''
[one]
credential_process = helper-one
[two]
credential_process = helper-two
''');
      await loadAwsCredentials('one', path: f.path);
      await loadAwsCredentials('two', path: f.path);
      expect(runs, 2, reason: 'distinct profiles must not share a cache entry');
    });

    test('static file-based credentials stay fresh per request (never cached)', () async {
      final f = write('credentials',
          '[default]\naws_access_key_id=AKIAONE\naws_secret_access_key=s1\n');
      expect((await loadAwsCredentials('default', path: f.path))!.accessKeyId, 'AKIAONE');
      // An external process rotates the file — the next load must see it.
      f.writeAsStringSync(
          '[default]\naws_access_key_id=AKIATWO\naws_secret_access_key=s2\n');
      expect((await loadAwsCredentials('default', path: f.path))!.accessKeyId, 'AKIATWO');
    });
  });
}
