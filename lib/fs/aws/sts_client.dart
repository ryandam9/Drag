import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 's3_client.dart' show S3Exception, parseAwsEndpoint;
import 'sigv4.dart';

/// Temporary credentials returned by STS `AssumeRole`, with their expiry.
class AssumedRole {
  final AwsCredentials credentials;
  final DateTime expiration;
  const AssumedRole(this.credentials, this.expiration);
}

/// A minimal AWS STS client implementing `AssumeRole` over the Query API,
/// signed with SigV4 (service `sts`). Path-style host so it also works against
/// a mock/STS-compatible endpoint.
class StsClient {
  StsClient({required String region, String endpoint = '', this.useSsl = true})
      : region = region.isEmpty ? 'us-east-1' : region,
        _scheme = useSsl ? 'https' : 'http' {
    final parsed = parseAwsEndpoint(endpoint.isNotEmpty
        ? endpoint
        : (region.isEmpty ? 'sts.amazonaws.com' : 'sts.$region.amazonaws.com'));
    _host = parsed.host;
    _port = parsed.port;
  }

  final String region;
  final bool useSsl;
  final String _scheme;
  late final String _host;
  int? _port;

  /// Same connect/idle timeouts as the S3 client, so a hung STS endpoint can't
  /// leave an AssumeRole (and every operation waiting on it) pending forever.
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);

  String get _hostHeader {
    final isDefault = _port == null || (useSsl && _port == 443) || (!useSsl && _port == 80);
    return isDefault ? _host : '$_host:$_port';
  }

  /// Exchanges [baseCredentials] for temporary credentials scoped to [roleArn].
  Future<AssumedRole> assumeRole({
    required String roleArn,
    required String sessionName,
    required AwsCredentials baseCredentials,
    String? externalId,
    int durationSeconds = 3600,
  }) async {
    final params = <String, String>{
      'Action': 'AssumeRole',
      'Version': '2011-06-15',
      'RoleArn': roleArn,
      'RoleSessionName': sessionName,
      'DurationSeconds': '$durationSeconds',
      if (externalId != null && externalId.isNotEmpty) 'ExternalId': externalId,
    };
    final body = (params.keys.toList()..sort())
        .map((k) => '${awsUriEncode(k, encodeSlash: true)}=${awsUriEncode(params[k]!, encodeSlash: true)}')
        .join('&');
    final bytes = utf8.encode(body);

    const contentType = 'application/x-www-form-urlencoded; charset=utf-8';
    final signer = SigV4Signer(credentials: baseCredentials, region: region, service: 'sts');
    final headers = signer.sign(
      method: 'POST',
      host: _hostHeader,
      canonicalUri: '/',
      query: const {},
      headers: const {'content-type': contentType},
      payloadHash: sha256.convert(bytes).toString(),
    );

    final req = await _http.postUrl(Uri.parse('$_scheme://$_hostHeader/'));
    headers.forEach(req.headers.set);
    req.headers.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, respBody);

    final result = XmlDocument.parse(respBody).rootElement;
    final creds = result.findAllElements('Credentials').firstOrNull;
    if (creds == null) throw S3Exception(resp.statusCode, 'AssumeRole returned no credentials');
    final ak = creds.getElement('AccessKeyId')?.innerText ?? '';
    final sk = creds.getElement('SecretAccessKey')?.innerText ?? '';
    final tok = creds.getElement('SessionToken')?.innerText ?? '';
    final expText = creds.getElement('Expiration')?.innerText;
    if (ak.isEmpty || sk.isEmpty) throw S3Exception(resp.statusCode, 'AssumeRole credentials incomplete');
    final exp = DateTime.tryParse(expText ?? '')?.toUtc() ??
        DateTime.now().toUtc().add(Duration(seconds: durationSeconds));
    return AssumedRole(AwsCredentials(ak, sk, sessionToken: tok), exp);
  }

  S3Exception _error(int status, String body) {
    String message = body;
    try {
      message = XmlDocument.parse(body).rootElement.getElement('Error')?.getElement('Message')?.innerText ?? body;
    } catch (_) {/* not XML */}
    return S3Exception(status, message.isEmpty ? 'AssumeRole failed' : message);
  }

  void close() => _http.close(force: true);
}

/// Resolves credentials for a role by calling STS `AssumeRole` and caching the
/// temporary credentials until shortly before they expire, then re-assuming.
/// The clock is injectable for deterministic tests.
class AssumeRoleCredentialsProvider {
  AssumeRoleCredentialsProvider({
    required this.sts,
    required this.roleArn,
    required this.sessionName,
    required this.baseCredentials,
    this.externalId,
    this.durationSeconds = 3600,
    this.refreshWindow = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  final StsClient sts;
  final String roleArn;
  final String sessionName;
  final String? externalId;
  final int durationSeconds;
  final Duration refreshWindow;

  /// Resolves the base (long-lived) credentials used to call AssumeRole. May
  /// be async (e.g. a profile whose credentials come from a helper process).
  final FutureOr<AwsCredentials> Function() baseCredentials;

  final DateTime Function() _now;
  AssumedRole? _cached;

  /// The current temporary credentials, re-assuming when missing or within
  /// [refreshWindow] of expiry.
  Future<AwsCredentials> resolve() async {
    final c = _cached;
    if (c != null && c.expiration.isAfter(_now().add(refreshWindow))) {
      return c.credentials;
    }
    final assumed = await sts.assumeRole(
      roleArn: roleArn,
      sessionName: sessionName,
      baseCredentials: await baseCredentials(),
      externalId: externalId,
      durationSeconds: durationSeconds,
    );
    _cached = assumed;
    return assumed.credentials;
  }
}
