import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/connection.dart';
import '../models/file_item.dart';
import 'aws/s3_client.dart';
import 'aws/sigv4.dart';

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
}

// ─────────────────────────────────────────────────────────────────────────
// Amazon S3 / S3-compatible (real, via our own SigV4 S3 client)
// ─────────────────────────────────────────────────────────────────────────
class S3Backend extends StorageBackend {
  S3Backend(this.connection) {
    if (connection.hasS3Credentials) _client = _build(connection);
  }

  final Connection connection;
  S3Client? _client;

  String get bucket => connection.bucket;

  @override
  EndpointKind get kind => EndpointKind.s3;

  @override
  String get badge => 'S3';

  @override
  bool get isReady => _client != null;

  @override
  String get initialPath => ''; // bucket root prefix

  @override
  String displayPath(String path) => 's3://$bucket/$path';

  static S3Client _build(Connection c) {
    return S3Client(
      bucket: c.bucket,
      region: c.region,
      endpoint: c.endpoint,
      useSsl: c.useSsl,
      credentials: AwsCredentials(
        c.accessKeyId,
        c.secretAccessKey,
        sessionToken: c.sessionToken.isEmpty ? null : c.sessionToken,
      ),
    );
  }

  @override
  Future<List<FileItem>> list(String path) async {
    final client = _client;
    if (client == null) throw StateError('S3 connection has no credentials');

    final items = <FileItem>[];
    if (path.isNotEmpty) items.add(const FileItem(name: '..', isDir: true));

    final result = await client.listAll(prefix: path, delimiter: '/');
    // CommonPrefixes → folders.
    for (final prefix in result.commonPrefixes) {
      final name = prefix.substring(path.length).replaceAll(RegExp(r'/$'), '');
      if (name.isEmpty) continue;
      items.add(FileItem(name: name, isDir: true));
    }
    // Contents → objects.
    for (final obj in result.objects) {
      if (obj.key == path) continue; // the prefix placeholder object itself
      final name = obj.key.substring(path.length);
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
    final client = _client!;
    final resp = await client.getObject(path);
    return ReadHandle(resp.stream.map(Uint8List.fromList), resp.contentLength);
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final client = _client!;
    await client.putObject(path, data, length, onProgress: onProgress);
  }

  @override
  Future<void> makeDir(String path) async {
    // S3 has no real directories — represent one with a zero-byte key ending '/'.
    final key = path.endsWith('/') ? path : '$path/';
    await _client!.putObject(key, const Stream<Uint8List>.empty(), 0);
  }

  @override
  Future<void> rename(String fromPath, String toPath) async {
    if (fromPath.endsWith('/')) {
      throw UnsupportedError('Renaming S3 folders is not supported');
    }
    await _client!.copyObject(fromPath, toPath);
    await _client!.deleteObject(fromPath);
  }

  @override
  Future<void> delete(String path, {required bool isDir}) async {
    final client = _client!;
    if (!isDir) {
      await client.deleteObject(path);
      return;
    }
    // Recursively delete everything under the prefix (and the placeholder).
    final prefix = path.endsWith('/') ? path : '$path/';
    final result = await client.listAll(prefix: prefix, delimiter: '');
    for (final obj in result.objects) {
      await client.deleteObject(obj.key);
    }
  }

  @override
  void dispose() => _client?.close();

  @override
  String childPath(String path, String name, bool isDir) => '$path$name${isDir ? '/' : ''}';

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx < 0 ? '' : trimmed.substring(0, idx + 1);
  }
}
