import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'sigv4.dart';

/// One object returned by a listing.
class S3Object {
  final String key;
  final int size;
  final DateTime? lastModified;
  const S3Object(this.key, this.size, this.lastModified);
}

/// Result of a single ListObjectsV2 page.
class S3Listing {
  final List<S3Object> objects;
  final List<String> commonPrefixes;
  final String? nextContinuationToken;
  const S3Listing(this.objects, this.commonPrefixes, this.nextContinuationToken);
  bool get isTruncated => nextContinuationToken != null;
}

/// A streamed GET response.
class S3GetResponse {
  final Stream<List<int>> stream;
  final int contentLength;
  const S3GetResponse(this.stream, this.contentLength);
}

class S3Exception implements Exception {
  final int statusCode;
  final String message;
  S3Exception(this.statusCode, this.message);
  @override
  String toString() => 'S3 error $statusCode: $message';
}

/// A minimal Amazon S3 client implementing exactly what Drag needs
/// (ListObjectsV2, GetObject, PutObject) over the S3 REST API, signed with
/// AWS Signature V4. Uses path-style addressing so it works against AWS as
/// well as S3-compatible servers (MinIO, etc.).
class S3Client {
  S3Client({
    required this.bucket,
    required this.region,
    required AwsCredentials Function() credentials,
    String endpoint = '',
    this.useSsl = true,
  })  : _resolveCredentials = credentials,
        _scheme = useSsl ? 'https' : 'http' {
    var host = endpoint.isNotEmpty
        ? endpoint
        : (region.isEmpty ? 's3.amazonaws.com' : 's3.$region.amazonaws.com');
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    final colon = host.indexOf(':');
    if (colon != -1) {
      _port = int.tryParse(host.substring(colon + 1));
      host = host.substring(0, colon);
    }
    _host = host;
  }

  final String bucket;
  final String region;
  final bool useSsl;

  /// Resolves the credentials to sign with. Called once per request, so a
  /// rotated ~/.aws profile / session token is picked up automatically.
  final AwsCredentials Function() _resolveCredentials;

  final String _scheme;
  late final String _host;
  int? _port;

  final HttpClient _http = HttpClient();

  /// A signer bound to the credentials current at call time.
  SigV4Signer get _signer =>
      SigV4Signer(credentials: _resolveCredentials(), region: region);

  /// Host header value (includes port when non-default).
  String get _hostHeader {
    final isDefault = _port == null || (useSsl && _port == 443) || (!useSsl && _port == 80);
    return isDefault ? _host : '$_host:$_port';
  }

  Uri _uri(String encodedPath, Map<String, String> query) {
    final qs = (query.keys.toList()..sort())
        .map((k) => '${awsUriEncode(k, encodeSlash: true)}=${awsUriEncode(query[k]!, encodeSlash: true)}')
        .join('&');
    final base = '$_scheme://$_hostHeader$encodedPath';
    return Uri.parse(qs.isEmpty ? base : '$base?$qs');
  }

  String _objectPath(String key) =>
      '/${awsUriEncode(bucket, encodeSlash: true)}/${awsUriEncode(key)}';

  // ── ListBuckets (service-level; ignores [bucket]) ──
  Future<List<String>> listBuckets() async {
    const canonicalUri = '/';
    final headers = _signer.sign(
      method: 'GET',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.getUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body);

    return XmlDocument.parse(body)
        .rootElement
        .findAllElements('Bucket')
        .map((b) => b.getElement('Name')?.innerText ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// The region a bucket lives in (via GetBucketLocation). Empty location
  /// constraint → us-east-1; the legacy `EU` value → eu-west-1.
  Future<String> getBucketLocation(String bucket) async {
    final canonicalUri = '/${awsUriEncode(bucket, encodeSlash: true)}';
    const query = {'location': ''};
    final headers = _signer.sign(
      method: 'GET',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.getUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body);
    final loc = XmlDocument.parse(body).rootElement.innerText.trim();
    if (loc.isEmpty) return 'us-east-1';
    if (loc == 'EU') return 'eu-west-1';
    return loc;
  }

  // ── ListObjectsV2 (one page) ──
  Future<S3Listing> listObjects({
    String prefix = '',
    String delimiter = '/',
    String? continuationToken,
  }) async {
    final query = <String, String>{
      'list-type': '2',
      'prefix': prefix,
      'delimiter': delimiter,
    };
    if (continuationToken != null) query['continuation-token'] = continuationToken;

    final canonicalUri = '/${awsUriEncode(bucket, encodeSlash: true)}';
    final headers = _signer.sign(
      method: 'GET',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: emptyBodySha256,
    );

    final req = await _http.getUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body);

    final doc = XmlDocument.parse(body);
    final root = doc.rootElement;

    final objects = root.findElements('Contents').map((c) {
      final key = c.getElement('Key')?.innerText ?? '';
      final size = int.tryParse(c.getElement('Size')?.innerText ?? '0') ?? 0;
      final lm = c.getElement('LastModified')?.innerText;
      return S3Object(key, size, lm == null ? null : DateTime.tryParse(lm));
    }).toList();

    final prefixes = root
        .findElements('CommonPrefixes')
        .map((p) => p.getElement('Prefix')?.innerText ?? '')
        .where((p) => p.isNotEmpty)
        .toList();

    final truncated = (root.getElement('IsTruncated')?.innerText ?? 'false') == 'true';
    final next = truncated ? root.getElement('NextContinuationToken')?.innerText : null;

    return S3Listing(objects, prefixes, next);
  }

  /// Lists every page and merges the results.
  Future<S3Listing> listAll({String prefix = '', String delimiter = '/'}) async {
    final objects = <S3Object>[];
    final prefixes = <String>[];
    String? token;
    do {
      final page = await listObjects(prefix: prefix, delimiter: delimiter, continuationToken: token);
      objects.addAll(page.objects);
      prefixes.addAll(page.commonPrefixes);
      token = page.nextContinuationToken;
    } while (token != null);
    return S3Listing(objects, prefixes, null);
  }

  // ── GetObject (streamed) ──
  Future<S3GetResponse> getObject(String key) async {
    final canonicalUri = _objectPath(key);
    final headers = _signer.sign(
      method: 'GET',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.getUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body);
    }
    final len = resp.contentLength < 0 ? 0 : resp.contentLength;
    return S3GetResponse(resp, len);
  }

  // ── PutObject (streamed, UNSIGNED-PAYLOAD) ──
  Future<void> putObject(
    String key,
    Stream<List<int>> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final canonicalUri = _objectPath(key);
    final headers = _signer.sign(
      method: 'PUT',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: const {},
      payloadHash: unsignedPayload,
    );

    final req = await _http.putUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    req.headers.contentLength = length;

    var sent = 0;
    await req.addStream(data.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent);
      return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    }));
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body);
    }
    await resp.drain<void>();
  }

  // ── DeleteObject ──
  Future<void> deleteObject(String key) async {
    final canonicalUri = _objectPath(key);
    final headers = _signer.sign(
      method: 'DELETE',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.deleteUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body);
    }
    await resp.drain<void>();
  }

  // ── CopyObject (server-side copy within the bucket) ──
  Future<void> copyObject(String srcKey, String dstKey) async {
    final canonicalUri = _objectPath(dstKey);
    final copySource =
        '/${awsUriEncode(bucket, encodeSlash: true)}/${awsUriEncode(srcKey)}';
    final headers = _signer.sign(
      method: 'PUT',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: {'x-amz-copy-source': copySource},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.putUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    req.headers.contentLength = 0;
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body);
    }
    await resp.drain<void>();
  }

  S3Exception _error(int status, String body) {
    String message = body;
    try {
      message = XmlDocument.parse(body).rootElement.getElement('Message')?.innerText ?? body;
    } catch (_) {/* not XML */}
    return S3Exception(status, message.isEmpty ? 'request failed' : message);
  }

  void close() => _http.close(force: true);
}
