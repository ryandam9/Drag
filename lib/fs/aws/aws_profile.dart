import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/connection.dart';
import 'sigv4.dart';

/// Reads AWS credentials from the shared credentials file
/// (`~/.aws/credentials`) and region from the config file (`~/.aws/config`),
/// mirroring the AWS CLI/SDK layout. The credentials file is re-read on every
/// call, so rotated temporary credentials (refreshed `aws_session_token`) are
/// picked up automatically.
///
/// Only the file-based shared-credentials provider is implemented (no SSO/role
/// assumption); the assumption is that some external process keeps
/// `~/.aws/credentials` fresh.

/// Test seam — when set, overrides the credentials-file path.
@visibleForTesting
String? debugAwsCredentialsPath;

/// Test seam — when set, overrides the config-file path.
@visibleForTesting
String? debugAwsConfigPath;

/// Test seam — when set, overrides the process environment used by the
/// environment-variable credential provider.
@visibleForTesting
Map<String, String>? debugAwsEnv;

Map<String, String> _env() => debugAwsEnv ?? Platform.environment;

String _home() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

String awsCredentialsPath() =>
    debugAwsCredentialsPath ??
    Platform.environment['AWS_SHARED_CREDENTIALS_FILE'] ??
    '${_home()}/.aws/credentials';

String awsConfigPath() =>
    debugAwsConfigPath ??
    Platform.environment['AWS_CONFIG_FILE'] ??
    '${_home()}/.aws/config';

/// The effective profile name: the connection's, else `$AWS_PROFILE`, else
/// `default`.
String resolveAwsProfile(Connection c) => c.awsProfile.isNotEmpty
    ? c.awsProfile
    : (_env()['AWS_PROFILE'] ?? 'default');

/// Minimal INI parser → `{section: {key: value}}`. Tolerates comments
/// (`#` / `;`) and surrounding whitespace.
Map<String, Map<String, String>> _parseIni(String text) {
  final out = <String, Map<String, String>>{};
  String? section;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim();
      out.putIfAbsent(section, () => {});
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0 || section == null) continue;
    out[section]![line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return out;
}

/// The settings for [profile], looked up first in the shared credentials file
/// and then in `~/.aws/config` (where it's `[profile NAME]`, except default).
Map<String, String>? _profileSection(String profile, {String? credPath, String? cfgPath}) {
  final cred = File(credPath ?? awsCredentialsPath());
  if (cred.existsSync()) {
    final s = _parseIni(cred.readAsStringSync())[profile];
    if (s != null) return s;
  }
  final cfg = File(cfgPath ?? awsConfigPath());
  if (cfg.existsSync()) {
    final ini = _parseIni(cfg.readAsStringSync());
    return ini[profile] ?? ini['profile $profile'];
  }
  return null;
}

/// Loads credentials for [profile], or null if none can be resolved. Resolution
/// order within the profile: static `aws_access_key_id`/`aws_secret_access_key`,
/// then a `credential_process` command (the path AWS SSO / external helpers use
/// — its JSON output is parsed). Profiles in `~/.aws/config` are also honoured.
AwsCredentials? loadAwsCredentials(String profile, {String? path}) {
  final section = _profileSection(profile, credPath: path);
  if (section == null) return null;
  final key = section['aws_access_key_id'] ?? '';
  final secret = section['aws_secret_access_key'] ?? '';
  if (key.isNotEmpty && secret.isNotEmpty) {
    final token = section['aws_session_token'] ?? section['aws_security_token'] ?? '';
    return AwsCredentials(key, secret, sessionToken: token.isEmpty ? null : token);
  }
  final process = section['credential_process'];
  if (process != null && process.isNotEmpty) return _runCredentialProcess(process);
  return null;
}

/// Runs a `credential_process` command and parses its JSON output
/// (`AccessKeyId` / `SecretAccessKey` / `SessionToken`), as the AWS SDKs do.
/// Returns null on any failure so callers fall through to other providers.
AwsCredentials? _runCredentialProcess(String command) {
  try {
    final result = Platform.isWindows
        ? Process.runSync('cmd', ['/c', command])
        : Process.runSync('/bin/sh', ['-c', command]);
    if (result.exitCode != 0) return null;
    final out = result.stdout is String ? result.stdout as String : utf8.decode(result.stdout as List<int>);
    final json = jsonDecode(out) as Map<String, dynamic>;
    final key = (json['AccessKeyId'] as String?) ?? '';
    final secret = (json['SecretAccessKey'] as String?) ?? '';
    if (key.isEmpty || secret.isEmpty) return null;
    final token = json['SessionToken'] as String?;
    return AwsCredentials(key, secret, sessionToken: (token != null && token.isNotEmpty) ? token : null);
  } catch (_) {
    return null; // missing helper, non-JSON output, bad exit — treat as "no creds"
  }
}

/// Credentials from the standard AWS environment variables
/// (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`), or
/// null if the access key and secret aren't both present.
AwsCredentials? loadAwsEnvCredentials() {
  final env = _env();
  final key = env['AWS_ACCESS_KEY_ID'] ?? '';
  final secret = env['AWS_SECRET_ACCESS_KEY'] ?? '';
  if (key.isEmpty || secret.isEmpty) return null;
  final token = env['AWS_SESSION_TOKEN'] ?? env['AWS_SECURITY_TOKEN'] ?? '';
  return AwsCredentials(key, secret, sessionToken: token.isEmpty ? null : token);
}

/// Region for [profile] from `~/.aws/config` (sections are `[profile NAME]`,
/// except `[default]`). Null if absent.
String? loadAwsRegion(String profile, {String? path}) {
  final file = File(path ?? awsConfigPath());
  if (!file.existsSync()) return null;
  final ini = _parseIni(file.readAsStringSync());
  final section = ini[profile] ?? ini['profile $profile'];
  final region = section?['region'];
  if (region != null && region.isNotEmpty) return region;
  // Inherit the region from the source profile when this one chains off it.
  final source = section?['source_profile'];
  if (source != null && source.isNotEmpty && source != profile) {
    final inherited = (ini[source] ?? ini['profile $source'])?['region'];
    if (inherited != null && inherited.isNotEmpty) return inherited;
  }
  return null;
}
