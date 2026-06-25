import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/connection.dart';
import '../models/file_item.dart';
import 'aws/aws_profile.dart';
import 'aws/s3_client.dart';
import 'aws/sigv4.dart';
import 'aws/sts_client.dart';

/// A readable handle: the byte stream plus the total size (for progress/ETA).
class ReadHandle {
  final Stream<Uint8List> stream;
  final int length;
  const ReadHandle(this.stream, this.length);
}

/// Abstracts a place files live (local disk, an S3 bucket, a simulated SFTP
/// host). Both browser panes are driven by one of these, and transfers are
/// simply `source.openRead` piped into `dest.write` — so Local↔S3 and
/// S3↔S3 (cross-account) all work through the same code path.
abstract class StorageBackend {
  EndpointKind get kind;

  /// Short label shown in the pane badge (LOCAL / S3 / SFTP).
  String get badge;

  /// Path/URI shown in the pane's path field.
  String displayPath(String path);

  /// Where a freshly-opened pane starts.
  String get initialPath;

  /// Whether browsing/transfer can actually be attempted (e.g. S3 needs creds).
  bool get isReady => true;

  /// Whether this backend performs real byte transfers (false = demo/simulated).
  bool get supportsTransfer => true;

  /// Whether this backend supports create/rename/delete operations.
  bool get supportsMutation => true;

  Future<List<FileItem>> list(String path);

  /// Create a directory at [path].
  Future<void> makeDir(String path) =>
      throw UnsupportedError('makeDir not supported');

  /// Rename/move [fromPath] to [toPath].
  Future<void> rename(String fromPath, String toPath) =>
      throw UnsupportedError('rename not supported');

  /// Delete the entry at [path] ([isDir] selects recursive directory removal).
  Future<void> delete(String path, {required bool isDir}) =>
      throw UnsupportedError('delete not supported');

  Future<ReadHandle> openRead(String path);

  /// Whether this backend can resume a read from a byte offset (file seek /
  /// HTTP Range), so an interrupted download continues instead of restarting.
  bool get supportsResume => false;

  /// Whether a [write] publishes the destination atomically — the final path
  /// only becomes visible/complete when the write finishes (e.g. S3's single
  /// PUT and multipart upload). For atomic backends the transfer writes
  /// straight to the destination; for in-place backends (local file, SFTP)
  /// the transfer stages bytes in a temp sibling and renames on success, so a
  /// pause/cancel/crash can never truncate or delete a pre-existing file.
  bool get atomicWrite => false;

  /// Opens a read of [path] starting [start] bytes in. The returned handle's
  /// length is the *remaining* byte count. Only meaningful when
  /// [supportsResume]; the base default ignores [start] and reads from 0.
  Future<ReadHandle> openReadRange(String path, int start) => openRead(path);

  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  });

  /// Full path of a child entry (used for navigation and transfers).
  String childPath(String path, String name, bool isDir);

  /// Parent of [path] (for the "Up" / ".." actions).
  String parentPath(String path);

  /// The size in bytes of the file at [path], or null if it can't be
  /// determined. Used by post-transfer verification to confirm the
  /// destination received every byte. The default lists the parent directory
  /// and matches by basename; backends with a cheaper stat override this.
  Future<int?> sizeOf(String path) async {
    final name = childName(path);
    try {
      final entries = await list(parentPath(path));
      for (final e in entries) {
        if (e.name == name) return e.sizeBytes;
      }
    } catch (_) {
      // Treat an unlistable parent as "unknown size".
    }
    return null;
  }

  /// The trailing name component of [path] (basename), backend-aware so S3's
  /// trailing-slash folders and key prefixes resolve correctly.
  String childName(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx < 0 ? trimmed : trimmed.substring(idx + 1);
  }

  void dispose() {}

  static int dirsFirst(FileItem a, FileItem b) {
    if (a.isParent) return -1;
    if (b.isParent) return 1;
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Local filesystem (real)
// ─────────────────────────────────────────────────────────────────────────
class LocalBackend extends StorageBackend {
  @override
  EndpointKind get kind => EndpointKind.local;

  @override
  String get badge => 'LOCAL';

  @override
  String displayPath(String path) => path;

  @override
  String get initialPath {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
  }

  @override
  Future<List<FileItem>> list(String path) async {
    final dir = Directory(path);
    final items = <FileItem>[];
    final root = p.rootPrefix(path);
    if (p.normalize(path) != p.normalize(root)) {
      items.add(const FileItem(name: '..', isDir: true));
    }
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        final isDir = stat.type == FileSystemEntityType.directory;
        items.add(FileItem(
          name: p.basename(entity.path),
          isDir: isDir,
          sizeBytes: isDir ? null : stat.size,
          modified: formatModified(stat.modified),
          perms: stat.modeString(),
        ));
      } catch (_) {
        // Skip entries we can't stat (permissions, broken links).
      }
    }
    items.sort(StorageBackend.dirsFirst);
    return items;
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    final file = File(path);
    final length = await file.length();
    return ReadHandle(file.openRead().map(Uint8List.fromList), length);
  }

  @override
  bool get supportsResume => true;

  @override
  Future<ReadHandle> openReadRange(String path, int start) async {
    final file = File(path);
    final length = await file.length();
    if (start <= 0) return ReadHandle(file.openRead().map(Uint8List.fromList), length);
    final remaining = (length - start).clamp(0, length);
    return ReadHandle(file.openRead(start).map(Uint8List.fromList), remaining);
  }

  /// Append [data] to an existing partial file (used to resume a download from
  /// [from] bytes already on disk). [onProgress] reports the cumulative total.
  Future<void> writeResume(
    String path,
    Stream<Uint8List> data, {
    required int from,
    void Function(int sent)? onProgress,
  }) async {
    final sink = File(path).openWrite(mode: FileMode.writeOnlyAppend);
    var sent = from;
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final sink = File(path).openWrite();
    var sent = 0;
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> makeDir(String path) => Directory(path).create();

  @override
  Future<void> rename(String fromPath, String toPath) async {
    final type = await FileSystemEntity.type(fromPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(fromPath).rename(toPath);
    } else {
      await File(fromPath).rename(toPath);
    }
  }

  @override
  Future<void> delete(String path, {required bool isDir}) =>
      isDir ? Directory(path).delete(recursive: true) : File(path).delete();

  @override
  String childPath(String path, String name, bool isDir) => p.join(path, name);

  @override
  String parentPath(String path) => p.dirname(path);

  @override
  Future<int?> sizeOf(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return stat.size;
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Amazon S3 / S3-compatible (real, via our own SigV4 S3 client)
// ─────────────────────────────────────────────────────────────────────────
class S3Backend extends StorageBackend {
  S3Backend(this.connection);

  final Connection connection;

  /// With no bucket configured, the backend lists the account's buckets at the
  /// root and the first path segment becomes the bucket name. This supports
  /// accounts with many buckets across many regions.
  bool get _discovery => connection.bucket.isEmpty;

  // One client per bucket (built with that bucket's region), plus a service
  // client for ListBuckets / GetBucketLocation in discovery mode.
  final Map<String, S3Client> _bucketClients = {};
  final Map<String, String> _bucketRegions = {};
  S3Client? _service;

  @override
  EndpointKind get kind => EndpointKind.s3;

  @override
  String get badge => 'S3';

  @override
  bool get isReady => connection.hasS3Credentials;

  @override
  String get initialPath => ''; // bucket prefix, or the bucket list in discovery

  @override
  String displayPath(String path) =>
      's3://${_discovery ? path : '${connection.bucket}/$path'}';

  /// Splits a pane path into (bucket, key). In fixed-bucket mode the bucket is
  /// always the configured one and the whole path is the key.
  (String bucket, String key) _split(String path) {
    if (!_discovery) return (connection.bucket, path);
    if (path.isEmpty) return ('', '');
    final i = path.indexOf('/');
    return i < 0 ? (path, '') : (path.substring(0, i), path.substring(i + 1));
  }

  static String _defaultRegion(Connection c) => c.region.isNotEmpty
      ? c.region
      : (c.useAwsProfile ? (loadAwsRegion(resolveAwsProfile(c)) ?? 'us-east-1') : 'us-east-1');

  S3Client _build(Connection c, {required String bucket, required String region}) {
    return S3Client(
      bucket: bucket,
      region: region,
      endpoint: c.endpoint,
      useSsl: c.useSsl,
      // Resolved per request → a refreshed ~/.aws profile or assumed role's
      // temporary credentials are picked up live.
      credentials: _currentCredentials,
    );
  }

  // ── STS AssumeRole (optional) ──
  AssumeRoleCredentialsProvider? _roleProvider;
  AwsCredentials? _assumed;

  /// The credentials to sign the next request with: the cached assumed-role
  /// credentials when role mode is active, otherwise the base chain.
  AwsCredentials _currentCredentials() => _assumed ?? _resolveCredentials(connection);

  /// Ensures valid credentials are available before an operation: in
  /// assume-role mode this calls STS (cached + auto-refreshed); otherwise it's
  /// a no-op (the base chain is resolved per request when signing).
  Future<void> _ensureCredentials() async {
    if (connection.assumeRoleArn.isEmpty) return;
    _roleProvider ??= AssumeRoleCredentialsProvider(
      sts: StsClient(region: _defaultRegion(connection)),
      roleArn: connection.assumeRoleArn,
      sessionName: connection.roleSessionName.isEmpty ? 'drag' : connection.roleSessionName,
      externalId: connection.roleExternalId.isEmpty ? null : connection.roleExternalId,
      baseCredentials: () => _resolveCredentials(connection),
    );
    _assumed = await _roleProvider!.resolve();
  }

  /// The credentials to sign the next request with — either read fresh from the
  /// AWS shared-credentials profile, or the typed key/secret/token.
  static AwsCredentials _resolveCredentials(Connection c) {
    if (c.useAwsProfile) {
      // Standard AWS chain: environment variables take precedence, then the
      // shared credentials file profile. Both are re-read per request, so
      // refreshed temporary credentials are picked up automatically.
      final env = loadAwsEnvCredentials();
      if (env != null) return env;
      final name = resolveAwsProfile(c);
      final creds = loadAwsCredentials(name);
      if (creds == null) {
        throw S3Exception(0,
            'No AWS credentials in the environment or profile "$name" (${awsCredentialsPath()})');
      }
      return creds;
    }
    return AwsCredentials(
      c.accessKeyId,
      c.secretAccessKey,
      sessionToken: c.sessionToken.isEmpty ? null : c.sessionToken,
    );
  }

  S3Client _serviceClient() =>
      _service ??= _build(connection, bucket: '', region: _defaultRegion(connection));

  /// A client scoped to [bucket], built with that bucket's own region (resolved
  /// via GetBucketLocation and cached). With a custom endpoint (MinIO etc.)
  /// region routing doesn't apply, so the configured region is used as-is.
  Future<S3Client> _clientFor(String bucket) async {
    await _ensureCredentials();
    final existing = _bucketClients[bucket];
    if (existing != null) return existing;
    final String region;
    if (!_discovery || connection.endpoint.isNotEmpty) {
      region = _defaultRegion(connection);
    } else {
      region = _bucketRegions[bucket] ??= await _resolveRegion(bucket);
    }
    return _bucketClients[bucket] = _build(connection, bucket: bucket, region: region);
  }

  Future<String> _resolveRegion(String bucket) async {
    try {
      return await _serviceClient().getBucketLocation(bucket);
    } catch (_) {
      return _defaultRegion(connection); // fall back; object ops will surface errors
    }
  }

  @override
  Future<List<FileItem>> list(String path) async {
    await _ensureCredentials();
    final (bucket, key) = _split(path);

    // Root of a discovery connection → list the account's buckets.
    if (_discovery && bucket.isEmpty) {
      final names = await _serviceClient().listBuckets();
      return [for (final n in names) FileItem(name: n, isDir: true)]
        ..sort(StorageBackend.dirsFirst);
    }

    final client = await _clientFor(bucket);
    final items = <FileItem>[];
    if (path.isNotEmpty) items.add(const FileItem(name: '..', isDir: true));

    final result = await client.listAll(prefix: key, delimiter: '/');
    for (final prefix in result.commonPrefixes) {
      final name = prefix.substring(key.length).replaceAll(RegExp(r'/$'), '');
      if (name.isEmpty) continue;
      items.add(FileItem(name: name, isDir: true));
    }
    for (final obj in result.objects) {
      if (obj.key == key) continue; // the prefix placeholder object itself
      final name = obj.key.substring(key.length);
      if (name.isEmpty || name.endsWith('/')) continue;
      items.add(FileItem(
        name: name,
        sizeBytes: obj.size,
        modified: formatModified(obj.lastModified),
        perms: 's3',
      ));
    }
    items.sort(StorageBackend.dirsFirst);
    return items;
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    final (bucket, key) = _split(path);
    final client = await _clientFor(bucket);
    final resp = await client.getObject(key);
    return ReadHandle(resp.stream.map(Uint8List.fromList), resp.contentLength);
  }

  @override
  bool get supportsResume => true;

  // S3 publishes an object only when the PUT / multipart upload completes, so
  // an interrupted upload never leaves a partial or clobbers the prior object.
  @override
  bool get atomicWrite => true;

  @override
  Future<ReadHandle> openReadRange(String path, int start) async {
    if (start <= 0) return openRead(path);
    final (bucket, key) = _split(path);
    final client = await _clientFor(bucket);
    final resp = await client.getObject(key, rangeStart: start);
    return ReadHandle(resp.stream.map(Uint8List.fromList), resp.contentLength);
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final (bucket, key) = _split(path);
    final client = await _clientFor(bucket);
    // Picks a single PUT or a multipart upload based on the object size.
    await client.put(key, data, length, onProgress: onProgress);
  }

  @override
  Future<void> makeDir(String path) async {
    final (bucket, key) = _split(path);
    if (bucket.isEmpty) throw UnsupportedError('Select a bucket first');
    final client = await _clientFor(bucket);
    final folderKey = key.endsWith('/') ? key : '$key/';
    await client.putObject(folderKey, const Stream<Uint8List>.empty(), 0);
  }

  @override
  Future<void> rename(String fromPath, String toPath) async {
    if (fromPath.endsWith('/')) {
      throw UnsupportedError('Renaming S3 folders is not supported');
    }
    final (fromBucket, fromKey) = _split(fromPath);
    final (toBucket, toKey) = _split(toPath);
    if (fromBucket != toBucket) throw UnsupportedError('Cross-bucket rename is not supported');
    final client = await _clientFor(fromBucket);
    await client.copyObject(fromKey, toKey);
    await client.deleteObject(fromKey);
  }

  @override
  Future<void> delete(String path, {required bool isDir}) async {
    final (bucket, key) = _split(path);
    if (_discovery && key.isEmpty) {
      throw UnsupportedError('Deleting a bucket is not supported');
    }
    final client = await _clientFor(bucket);
    if (!isDir) {
      await client.deleteObject(key);
      return;
    }
    // Recursively delete everything under the prefix (and the placeholder).
    final prefix = key.endsWith('/') ? key : '$key/';
    final result = await client.listAll(prefix: prefix, delimiter: '');
    for (final obj in result.objects) {
      await client.deleteObject(obj.key);
    }
  }

  @override
  void dispose() {
    _service?.close();
    for (final c in _bucketClients.values) {
      c.close();
    }
    _roleProvider?.sts.close();
  }

  @override
  String childPath(String path, String name, bool isDir) => '$path$name${isDir ? '/' : ''}';

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx < 0 ? '' : trimmed.substring(0, idx + 1);
  }
}
