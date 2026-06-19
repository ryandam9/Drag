import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// AWS credentials for signing requests. [sessionToken] is set for temporary
/// (STS) credentials.
class AwsCredentials {
  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  const AwsCredentials(this.accessKeyId, this.secretAccessKey, {this.sessionToken});
}

/// SHA-256 hex of an empty body (used as the payload hash for GET requests).
const String emptyBodySha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Sentinel telling S3 the payload is not signed (valid for streamed uploads).
const String unsignedPayload = 'UNSIGNED-PAYLOAD';

/// Implements AWS Signature Version 4 (the scheme used by every official AWS
/// SDK) for the S3 REST API. This is a hand-written, dependency-free signer —
/// there is no official AWS SDK for Dart, so Drag ships its own.
///
/// Reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv4.html
class SigV4Signer {
  SigV4Signer({
    required this.credentials,
    required this.region,
    this.service = 's3',
  });

  final AwsCredentials credentials;
  final String region;
  final String service;

  /// Signs [headers] for a request and returns the full header set to send,
  /// including `Authorization`, `x-amz-date` and `x-amz-content-sha256`.
  ///
  /// [canonicalUri] must already be RFC-3986 URI-encoded (slashes preserved).
  /// [query] is the map of (decoded) query parameters.
  Map<String, String> sign({
    required String method,
    required String host,
    required String canonicalUri,
    required Map<String, String> query,
    required Map<String, String> headers,
    required String payloadHash,
    DateTime? now,
  }) {
    final time = (now ?? DateTime.now().toUtc()).toUtc();
    final amzDate = _amzDate(time);
    final dateStamp = amzDate.substring(0, 8);

    final signed = <String, String>{
      ...headers,
      'host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
    };
    if (credentials.sessionToken != null && credentials.sessionToken!.isNotEmpty) {
      signed['x-amz-security-token'] = credentials.sessionToken!;
    }

    // ── Canonical headers / signed-headers list ──
    final sortedKeys = signed.keys.map((k) => k.toLowerCase()).toList()..sort();
    final lower = {for (final e in signed.entries) e.key.toLowerCase(): e.value.trim()};
    final canonicalHeaders = sortedKeys.map((k) => '$k:${lower[k]}\n').join();
    final signedHeaders = sortedKeys.join(';');

    // ── Canonical query string (sorted, encoded) ──
    final canonicalQuery = (query.keys.toList()..sort())
        .map((k) => '${_uriEncode(k, true)}=${_uriEncode(query[k]!, true)}')
        .join('&');

    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final scope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _signingKey(dateStamp);
    final signature = _hex(_hmac(signingKey, utf8.encode(stringToSign)));

    signed['Authorization'] = 'AWS4-HMAC-SHA256 '
        'Credential=${credentials.accessKeyId}/$scope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';
    return signed;
  }

  List<int> _signingKey(String dateStamp) =>
      deriveSigningKey(credentials.secretAccessKey, dateStamp, region, service);

  /// Derives the SigV4 signing key (HMAC chain). Exposed so it can be checked
  /// against AWS's published test vectors.
  static List<int> deriveSigningKey(String secret, String dateStamp, String region, String service) {
    final kDate = _hmac(utf8.encode('AWS4$secret'), utf8.encode(dateStamp));
    final kRegion = _hmac(kDate, utf8.encode(region));
    final kService = _hmac(kRegion, utf8.encode(service));
    return _hmac(kService, utf8.encode('aws4_request'));
  }

  static List<int> _hmac(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String _amzDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }
}

/// RFC-3986 URI encoding as required by SigV4. Unreserved characters
/// (`A-Za-z0-9-._~`) pass through; everything else is percent-encoded.
/// When [encodeSlash] is false, `/` is preserved (used for object key paths).
String _uriEncode(String input, bool encodeSlash) {
  const unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final out = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final ch = String.fromCharCode(byte);
    if (unreserved.contains(ch)) {
      out.write(ch);
    } else if (ch == '/' && !encodeSlash) {
      out.write(ch);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// Public wrapper around the SigV4 path encoder for use by the HTTP layer.
String awsUriEncode(String input, {bool encodeSlash = false}) =>
    _uriEncode(input, encodeSlash);

/// Hex-encodes bytes (exposed for callers that pre-hash payloads).
String hexEncode(Uint8List bytes) => SigV4Signer._hex(bytes);
