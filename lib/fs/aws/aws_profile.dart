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
    : (Platform.environment['AWS_PROFILE'] ?? 'default');

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

/// Loads credentials for [profile] from the shared credentials file, or null if
/// the file/profile is missing or incomplete.
AwsCredentials? loadAwsCredentials(String profile, {String? path}) {
  final file = File(path ?? awsCredentialsPath());
  if (!file.existsSync()) return null;
  final section = _parseIni(file.readAsStringSync())[profile];
  if (section == null) return null;
  final key = section['aws_access_key_id'] ?? '';
  final secret = section['aws_secret_access_key'] ?? '';
  if (key.isEmpty || secret.isEmpty) return null;
  final token = section['aws_session_token'] ?? section['aws_security_token'] ?? '';
  return AwsCredentials(key, secret, sessionToken: token.isEmpty ? null : token);
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
  final region = (ini[profile] ?? ini['profile $profile'])?['region'];
  return (region != null && region.isNotEmpty) ? region : null;
}
