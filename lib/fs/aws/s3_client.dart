import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'sigv4.dart';

/// Splits an endpoint spec (`minio.local:9000`, `https://host`, bare host)
/// into host + optional port, tolerating a scheme prefix. Shared by [S3Client]
/// and `StsClient`, which accept the same endpoint syntax.
({String host, int? port}) parseAwsEndpoint(String endpoint) {
  var host = endpoint.replaceFirst(RegExp(r'^https?://'), '');
  int? port;
  final colon = host.indexOf(':');
  if (colon != -1) {
    port = int.tryParse(host.substring(colon + 1));
    host = host.substring(0, colon);
  }
  return (host: host, port: port);
}

/// Whether [error] is worth retrying: transient server-side failures (HTTP
/// 500/502/503/504, throttling 429, or the S3 error codes SlowDown /
/// RequestTimeout / InternalError) and socket-level trouble. Client errors
/// (403 AccessDenied, 404, 400 …) are permanent — retrying them just wastes
/// time and hides the real problem.
bool isRetryableS3Failure(Object error) {
  if (error is SocketException || error is HttpException || error is TimeoutException) {
    return true;
  }
  if (error is S3Exception) {
    if (const {429, 500, 502, 503, 504}.contains(error.statusCode)) return true;
    if (const {'SlowDown', 'RequestTimeout', 'InternalError'}.contains(error.code)) {
      return true;
    }
  }
  return false;
}

final Random _retryJitter = Random();

/// Default retry backoff: exponential (~0.4 s, 0.8 s, 1.6 s …) with full
/// jitter so concurrent clients don't retry in lockstep against a struggling
/// endpoint.
Duration defaultS3RetryBackoff(int attempt) {
  final baseMs = 200 * (1 << attempt); // attempt 1 → 400 ms, 2 → 800 ms …
  return Duration(milliseconds: baseMs + _retryJitter.nextInt(baseMs));
}

/// Runs [fn], retrying on failures [isRetryableS3Failure] classifies as
/// transient, up to [maxAttempts] total tries with [backoff] between them.
/// Anything non-retryable (or the final attempt's error) propagates as-is.
Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  required int maxAttempts,
  required Duration Function(int attempt) backoff,
}) async {
  for (var attempt = 1;; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt >= maxAttempts || !isRetryableS3Failure(e)) rethrow;
      await Future<void>.delayed(backoff(attempt));
    }
  }
}

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

/// Object metadata from a HeadObject call (no body transferred).
class S3Head {
  final int contentLength;
  final String? etag;
  const S3Head(this.contentLength, this.etag);
}

/// A failed S3 request. Beyond the HTTP [statusCode] and human [message], this
/// surfaces the fields AWS returns in the error XML — [code] (e.g.
/// `AccessDenied`), [requestId] and [hostId] — plus the [operation] and
/// [bucket] the client was acting on, so failures can actually be diagnosed
/// (and quoted in a support ticket) rather than guessed at.
class S3Exception implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final String? requestId;
  final String? hostId;
  final String? operation;
  final String? bucket;

  /// The object key the failed operation targeted, when it was object-level
  /// (get/put/copy/delete a specific key). Null for bucket/service-level calls.
  final String? key;
  const S3Exception(
    this.statusCode,
    this.message, {
    this.code,
    this.requestId,
    this.hostId,
    this.operation,
    this.bucket,
    this.key,
  });

  @override
  String toString() {
    final head = StringBuffer(operation != null ? '$operation failed' : 'S3 error');
    if (code != null && code!.isNotEmpty) head.write(': $code');
    final detail = <String>[
      'HTTP $statusCode',
      if (bucket != null && bucket!.isNotEmpty) 'bucket=$bucket',
      if (key != null && key!.isNotEmpty) 'key=$key',
      if (requestId != null && requestId!.isNotEmpty) 'requestId=$requestId',
      if (message.isNotEmpty) message,
    ].join(' · ');
    return '$head ($detail)';
  }
}

/// A minimal Amazon S3 client implementing exactly what Drag needs
/// (ListObjectsV2, GetObject, PutObject) over the S3 REST API, signed with
/// AWS Signature V4. Uses path-style addressing so it works against AWS as
/// well as S3-compatible servers (MinIO, etc.).
class S3Client {
  S3Client({
    required this.bucket,
    required this.region,
    required FutureOr<AwsCredentials> Function() credentials,
    String endpoint = '',
    this.useSsl = true,
    this.multipartThreshold = 16 * 1024 * 1024,
    this.partSize = 8 * 1024 * 1024,
    this.maxPartAttempts = 3,
    this.maxRequestAttempts = 3,
  })  : _resolveCredentials = credentials,
        _scheme = useSsl ? 'https' : 'http' {
    final parsed = parseAwsEndpoint(endpoint.isNotEmpty
        ? endpoint
        : (region.isEmpty ? 's3.amazonaws.com' : 's3.$region.amazonaws.com'));
    _host = parsed.host;
    _port = parsed.port;
  }

  final String bucket;
  final String region;
  final bool useSsl;

  /// Objects larger than this (bytes) are uploaded with multipart; smaller ones
  /// use a single PUT. Each part is [partSize] bytes (except the last).
  final int multipartThreshold;
  final int partSize;

  /// How many times to try uploading a single multipart part before giving up
  /// (and aborting the whole upload). A transient network blip on one part no
  /// longer dooms a large upload.
  final int maxPartAttempts;

  /// Backoff before retrying a failed part. Overridable in tests so they don't
  /// wait real seconds.
  Duration Function(int attempt) partBackoff = (attempt) => Duration(seconds: 1 << attempt);

  /// How many total tries an idempotent request (list/head/get/delete) gets
  /// before its failure propagates. Only transient failures are retried — see
  /// [isRetryableS3Failure].
  final int maxRequestAttempts;

  /// Backoff before retrying an idempotent request. Overridable in tests so
  /// they don't wait real seconds.
  Duration Function(int attempt) retryBackoff = defaultS3RetryBackoff;

  /// Resolves the credentials to sign with. Called once per request, so a
  /// rotated ~/.aws profile / session token is picked up automatically. May be
  /// async (credential_process helpers, STS role refresh).
  final FutureOr<AwsCredentials> Function() _resolveCredentials;

  final String _scheme;
  late final String _host;
  int? _port;

  /// Caps how long a request may take to establish a TCP connection and how
  /// long an idle (stalled) connection is kept, so a hung S3 endpoint can't
  /// leave a list/get/put/delete pending indefinitely.
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);

  /// A signer bound to the credentials current at call time (awaited, since
  /// the provider may need to run a helper process or call STS).
  Future<SigV4Signer> _signer() async =>
      SigV4Signer(credentials: await _resolveCredentials(), region: region);

  /// Retry wrapper for idempotent requests, wired to this client's
  /// [maxRequestAttempts] / [retryBackoff].
  Future<T> _withRetry<T>(Future<T> Function() fn) =>
      retryWithBackoff(fn, maxAttempts: maxRequestAttempts, backoff: (a) => retryBackoff(a));

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
  /// The account's buckets with their creation dates (the latter comes free in
  /// the ListBuckets response — no extra request).
  Future<List<({String name, DateTime? created})>> listBuckets() =>
      _withRetry(() async {
    const canonicalUri = '/';
    final headers = (await _signer()).sign(
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
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body, op: 'ListBuckets');

    return XmlDocument.parse(body)
        .rootElement
        .findAllElements('Bucket')
        .map((b) {
          final name = b.getElement('Name')?.innerText ?? '';
          final cd = b.getElement('CreationDate')?.innerText;
          return (name: name, created: cd == null ? null : DateTime.tryParse(cd));
        })
        .where((e) => e.name.isNotEmpty)
        .toList();
  });

  /// The region a bucket lives in (via GetBucketLocation). Empty location
  /// constraint → us-east-1; the legacy `EU` value → eu-west-1.
  Future<String> getBucketLocation(String bucket) => _withRetry(() async {
    final canonicalUri = '/${awsUriEncode(bucket, encodeSlash: true)}';
    const query = {'location': ''};
    final headers = (await _signer()).sign(
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
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body, op: 'GetBucketLocation');
    final loc = XmlDocument.parse(body).rootElement.innerText.trim();
    if (loc.isEmpty) return 'us-east-1';
    if (loc == 'EU') return 'eu-west-1';
    return loc;
  });

  // ── ListObjectsV2 (one page) ──
  Future<S3Listing> listObjects({
    String prefix = '',
    String delimiter = '/',
    String? continuationToken,
    int? maxKeys,
  }) => _withRetry(() async {
    final query = <String, String>{
      'list-type': '2',
      'prefix': prefix,
      'delimiter': delimiter,
    };
    if (continuationToken != null) query['continuation-token'] = continuationToken;
    if (maxKeys != null) query['max-keys'] = '$maxKeys';

    final canonicalUri = '/${awsUriEncode(bucket, encodeSlash: true)}';
    final headers = (await _signer()).sign(
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
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body, op: 'ListObjectsV2');

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
  });

  /// Lazily yields each page of a listing as it arrives, following
  /// continuation tokens. Lets callers render the first page immediately and
  /// keep streaming, instead of buffering a whole (possibly huge) prefix before
  /// showing anything. [pageSize] maps to S3's `max-keys` (≤ 1000).
  Stream<S3Listing> listPages({
    String prefix = '',
    String delimiter = '/',
    int? pageSize,
  }) async* {
    String? token;
    do {
      final page = await listObjects(
        prefix: prefix,
        delimiter: delimiter,
        continuationToken: token,
        maxKeys: pageSize,
      );
      yield page;
      token = page.nextContinuationToken;
    } while (token != null);
  }

  /// Lists every page and merges the results. Pass [maxKeys] to stop early once
  /// that many objects have been collected (the result's `isTruncated` is true
  /// when more remain), so a caller can bound work on a huge prefix.
  Future<S3Listing> listAll({String prefix = '', String delimiter = '/', int? maxKeys}) async {
    final objects = <S3Object>[];
    final prefixes = <String>[];
    var more = false;
    await for (final page in listPages(prefix: prefix, delimiter: delimiter)) {
      objects.addAll(page.objects);
      prefixes.addAll(page.commonPrefixes);
      if (maxKeys != null && objects.length >= maxKeys) {
        more = page.nextContinuationToken != null || objects.length > maxKeys;
        break;
      }
    }
    return S3Listing(objects, prefixes, more ? '' : null);
  }

  // ── GetObject (streamed; optional Range for resume) ──
  /// Only the request setup (connect, sign, status) is retried here — once the
  /// body stream is handed to the caller, a mid-transfer failure is the
  /// transfer layer's to handle (it owns resume/restart semantics).
  Future<S3GetResponse> getObject(String key, {int rangeStart = 0}) =>
      _withRetry(() => _getObjectOnce(key, rangeStart: rangeStart));

  Future<S3GetResponse> _getObjectOnce(String key, {int rangeStart = 0}) async {
    final canonicalUri = _objectPath(key);
    // A Range header is signed like any other header (lower-cased name).
    final extra = rangeStart > 0 ? {'range': 'bytes=$rangeStart-'} : const <String, String>{};
    final headers = (await _signer()).sign(
      method: 'GET',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: extra,
      payloadHash: emptyBodySha256,
    );
    final req = await _http.getUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body, op: 'GetObject', key: key);
    }
    final len = resp.contentLength < 0 ? 0 : resp.contentLength;
    if (rangeStart > 0) {
      if (resp.statusCode == HttpStatus.partialContent) {
        // Sanity-check the offset the server actually honoured: a Content-Range
        // starting anywhere but [rangeStart] would silently corrupt a resume.
        final start = _contentRangeStart(resp.headers.value('content-range'));
        if (start != null && start != rangeStart) {
          await resp.drain<void>();
          throw S3Exception(
            resp.statusCode,
            'server honoured Range from byte $start, expected $rangeStart',
            operation: 'GetObject',
            bucket: bucket,
            key: key,
          );
        }
      } else {
        // The server ignored the Range header and sent the whole object as a
        // plain 200. Handing that stream through as if it began at
        // [rangeStart] would corrupt a resumed download (the appended bytes
        // would duplicate the prefix already on disk), so transparently skip
        // the already-held prefix and report only the remaining length.
        return S3GetResponse(_skipBytes(resp, rangeStart), (len - rangeStart).clamp(0, len));
      }
    }
    // For a 206 the content length is the remaining (ranged) byte count.
    return S3GetResponse(resp, len);
  }

  /// The byte offset a `Content-Range: bytes 40-99/100` header starts at, or
  /// null when the header is absent or unparseable.
  static int? _contentRangeStart(String? header) {
    if (header == null) return null;
    final m = RegExp(r'bytes\s+(\d+)-').firstMatch(header);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// [stream] minus its first [count] bytes (chunk boundaries past the cut are
  /// preserved).
  static Stream<List<int>> _skipBytes(Stream<List<int>> stream, int count) async* {
    var remaining = count;
    await for (final chunk in stream) {
      if (remaining == 0) {
        yield chunk;
      } else if (chunk.length <= remaining) {
        remaining -= chunk.length;
      } else {
        yield chunk.sublist(remaining);
        remaining = 0;
      }
    }
  }

  // ── HeadObject (metadata only) ──
  /// Fetches an object's size + ETag with a single HEAD request — no listing,
  /// no body transfer. Note SigV4 for a HEAD uses the empty-payload hash (the
  /// request has no body). Throws an [S3Exception] (statusCode 404) for a
  /// missing key; HEAD responses carry no error XML, so only the status is
  /// available.
  Future<S3Head> headObject(String key) => _withRetry(() async {
    final canonicalUri = _objectPath(key);
    final headers = (await _signer()).sign(
      method: 'HEAD',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: const {},
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.headUrl(_uri(canonicalUri, const {}));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    await resp.drain<void>();
    if (resp.statusCode ~/ 100 != 2) {
      throw _error(resp.statusCode, '', op: 'HeadObject', key: key);
    }
    final etag = resp.headers.value('etag') ?? resp.headers.value('ETag');
    return S3Head(resp.contentLength < 0 ? 0 : resp.contentLength, etag);
  });

  // ── PutObject (streamed, UNSIGNED-PAYLOAD) ──
  Future<void> putObject(
    String key,
    Stream<List<int>> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final canonicalUri = _objectPath(key);
    final headers = (await _signer()).sign(
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
      throw _error(resp.statusCode, body, op: 'PutObject', key: key);
    }
    await resp.drain<void>();
  }

  /// Upload [data] to [key], choosing a single PUT for small objects and a
  /// multipart upload above [multipartThreshold] (which can exceed the 5 GB
  /// single-PUT limit and retries per part rather than restarting the whole
  /// object).
  Future<void> put(
    String key,
    Stream<List<int>> data,
    int length, {
    void Function(int sent)? onProgress,
  }) {
    if (length > multipartThreshold) {
      return putObjectMultipart(key, data, onProgress: onProgress);
    }
    return putObject(key, data, length, onProgress: onProgress);
  }

  // ── Multipart upload (CreateMultipartUpload → UploadPart* → Complete) ──

  /// Streams [data] to [key] as a multipart upload of [partSize]-byte parts.
  /// On any failure the upload is aborted so no orphaned parts are billed.
  Future<void> putObjectMultipart(
    String key,
    Stream<List<int>> data, {
    void Function(int sent)? onProgress,
    int? partSize,
  }) async {
    final size = partSize ?? this.partSize;
    final uploadId = await createMultipartUpload(key);
    final parts = <({int part, String etag})>[];
    var uploaded = 0;
    final buf = BytesBuilder(copy: false);

    Future<void> flush(Uint8List bytes) async {
      final n = parts.length + 1;
      final etag = await _uploadPartWithRetry(key, uploadId, n, bytes);
      parts.add((part: n, etag: etag));
      uploaded += bytes.length;
      onProgress?.call(uploaded);
    }

    try {
      await for (final chunk in data) {
        buf.add(chunk);
        while (buf.length >= size) {
          final all = buf.takeBytes();
          await flush(Uint8List.sublistView(all, 0, size));
          if (all.length > size) buf.add(Uint8List.sublistView(all, size));
        }
      }
      // A completely empty stream: a multipart upload of zero parts (or a
      // zero-length part) is rejected by S3/MinIO. Abort it and write the empty
      // object with a plain zero-byte PutObject instead.
      if (parts.isEmpty && buf.length == 0) {
        await _safeAbort(key, uploadId);
        await putObject(key, const Stream<Uint8List>.empty(), 0, onProgress: onProgress);
        return;
      }
      // The final (possibly only) part — flush whatever bytes remain.
      if (buf.length > 0 || parts.isEmpty) {
        await flush(buf.takeBytes());
      }
      await completeMultipartUpload(key, uploadId, parts);
    } catch (_) {
      await _safeAbort(key, uploadId);
      rethrow;
    }
  }

  Future<String> createMultipartUpload(String key) async {
    final canonicalUri = _objectPath(key);
    const query = {'uploads': ''};
    final headers = (await _signer()).sign(
      method: 'POST',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.postUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    req.headers.contentLength = 0;
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, body, op: 'CreateMultipartUpload', key: key);
    final id = XmlDocument.parse(body).rootElement.getElement('UploadId')?.innerText;
    if (id == null || id.isEmpty) throw S3Exception(resp.statusCode, 'missing UploadId', bucket: bucket, key: key);
    return id;
  }

  Future<String> uploadPart(String key, String uploadId, int partNumber, Uint8List data) async {
    final canonicalUri = _objectPath(key);
    final query = {'partNumber': '$partNumber', 'uploadId': uploadId};
    final headers = (await _signer()).sign(
      method: 'PUT',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: unsignedPayload,
    );
    final req = await _http.putUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    req.headers.contentLength = data.length;
    req.add(data);
    final resp = await req.close();
    if (resp.statusCode ~/ 100 != 2) {
      final body = await resp.transform(utf8.decoder).join();
      throw _error(resp.statusCode, body, op: 'UploadPart', key: key);
    }
    final etag = resp.headers.value('etag') ?? resp.headers.value('ETag');
    await resp.drain<void>();
    if (etag == null || etag.isEmpty) {
      throw S3Exception(resp.statusCode, 'missing ETag for part $partNumber', bucket: bucket, key: key);
    }
    return etag;
  }

  /// [uploadPart] with bounded retry + backoff. Retries up to [maxPartAttempts]
  /// times; the final failure propagates (and the caller aborts the upload).
  /// Only transient failures are retried — a 403/400 would fail identically
  /// every time, so it propagates immediately instead of burning retries.
  Future<String> _uploadPartWithRetry(String key, String uploadId, int partNumber, Uint8List data) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await uploadPart(key, uploadId, partNumber, data);
      } catch (e) {
        if (attempt >= maxPartAttempts || !isRetryableS3Failure(e)) rethrow;
        await Future<void>.delayed(partBackoff(attempt));
      }
    }
  }

  Future<void> completeMultipartUpload(
      String key, String uploadId, List<({int part, String etag})> parts) async {
    final canonicalUri = _objectPath(key);
    final query = {'uploadId': uploadId};
    final body = StringBuffer('<CompleteMultipartUpload>');
    for (final p in parts) {
      body.write('<Part><PartNumber>${p.part}</PartNumber><ETag>${p.etag}</ETag></Part>');
    }
    body.write('</CompleteMultipartUpload>');
    final bytes = utf8.encode(body.toString());

    final headers = (await _signer()).sign(
      method: 'POST',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: sha256.convert(bytes).toString(),
    );
    final req = await _http.postUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    req.headers.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, respBody, op: 'CompleteMultipartUpload', key: key);
    // S3 can return 200 with an <Error> body if completion fails mid-stream.
    if (respBody.contains('<Error')) throw _error(resp.statusCode, respBody, op: 'CompleteMultipartUpload', key: key);
  }

  Future<void> abortMultipartUpload(String key, String uploadId) async {
    final canonicalUri = _objectPath(key);
    final query = {'uploadId': uploadId};
    final headers = (await _signer()).sign(
      method: 'DELETE',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: const {},
      payloadHash: emptyBodySha256,
    );
    final req = await _http.deleteUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    await resp.drain<void>();
  }

  Future<void> _safeAbort(String key, String uploadId) async {
    try {
      await abortMultipartUpload(key, uploadId);
    } catch (_) {
      // Best-effort cleanup; the original error is what matters.
    }
  }

  // ── DeleteObject ──
  Future<void> deleteObject(String key) => _withRetry(() async {
    final canonicalUri = _objectPath(key);
    final headers = (await _signer()).sign(
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
      throw _error(resp.statusCode, body, op: 'DeleteObject', key: key);
    }
    await resp.drain<void>();
  });

  // ── DeleteObjects (batch — up to 1000 keys per request) ──
  /// Deletes [keys] in one DeleteObjects call and returns the keys that failed
  /// (empty on full success). At most 1000 keys per AWS limits; the caller
  /// pages larger sets. Far cheaper than one DeleteObject per key.
  /// (Idempotent — deleting an already-deleted key succeeds — so retried.)
  Future<List<String>> deleteObjects(List<String> keys) => _withRetry(() async {
    if (keys.isEmpty) return const <String>[];
    final body = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><Delete>');
    for (final k in keys) {
      body.write('<Object><Key>${_xmlEscape(k)}</Key></Object>');
    }
    body.write('<Quiet>true</Quiet></Delete>'); // quiet ⇒ response carries only errors
    final bytes = utf8.encode(body.toString());
    // DeleteObjects requires a Content-MD5 of the body (it's signed too).
    final contentMd5 = base64.encode(md5.convert(bytes).bytes);

    final canonicalUri = '/${awsUriEncode(bucket, encodeSlash: true)}';
    const query = {'delete': ''};
    final headers = (await _signer()).sign(
      method: 'POST',
      host: _hostHeader,
      canonicalUri: canonicalUri,
      query: query,
      headers: {'content-md5': contentMd5},
      payloadHash: sha256.convert(bytes).toString(),
    );
    final req = await _http.postUrl(_uri(canonicalUri, query));
    headers.forEach(req.headers.set);
    req.headers.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) throw _error(resp.statusCode, respBody, op: 'DeleteObjects');

    final failed = <String>[];
    try {
      final root = XmlDocument.parse(respBody).rootElement;
      for (final e in root.findElements('Error')) {
        final k = e.getElement('Key')?.innerText;
        if (k != null) failed.add(k);
      }
    } catch (_) {/* empty/quiet success body */}
    return failed;
  });

  static String _xmlEscape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  // ── CopyObject (server-side copy within the bucket) ──
  Future<void> copyObject(String srcKey, String dstKey) async {
    final canonicalUri = _objectPath(dstKey);
    final copySource =
        '/${awsUriEncode(bucket, encodeSlash: true)}/${awsUriEncode(srcKey)}';
    final headers = (await _signer()).sign(
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
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode ~/ 100 != 2) {
      throw _error(resp.statusCode, body, op: 'CopyObject', key: dstKey);
    }
    // S3 can return HTTP 200 with an <Error> in the body for a failed copy
    // (the status reflects "request received", not "copy succeeded"). Treat
    // that as failure so a rename built on copy+delete never deletes the
    // source after a copy that didn't actually complete.
    if (body.contains('<Error')) {
      throw _error(resp.statusCode, body, op: 'CopyObject', key: dstKey);
    }
  }

  S3Exception _error(int status, String body, {String? op, String? key}) {
    String? code, message, requestId, hostId;
    try {
      final root = XmlDocument.parse(body).rootElement;
      code = root.getElement('Code')?.innerText;
      message = root.getElement('Message')?.innerText;
      requestId = root.getElement('RequestId')?.innerText;
      hostId = root.getElement('HostId')?.innerText;
    } catch (_) {/* not XML — keep the raw body as the message */}
    final msg = (message != null && message.isNotEmpty)
        ? message
        : (body.trim().isEmpty ? 'request failed' : body.trim());
    return S3Exception(
      status,
      msg,
      code: code,
      requestId: requestId,
      hostId: hostId,
      operation: op,
      bucket: bucket,
      key: key,
    );
  }

  void close() => _http.close(force: true);
}
