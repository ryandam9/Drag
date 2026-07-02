import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';

/// A read-only, non-transferring [StorageBackend] used purely as a test
/// stand-in for a remote endpoint (e.g. SFTP) where exercising the real
/// network backend would be impractical. It is NOT shipped with the app —
/// production SFTP always uses the real [SftpBackend].
class FakeRemoteBackend extends StorageBackend {
  FakeRemoteBackend(this.connection);

  final Connection connection;

  @override
  EndpointKind get kind => EndpointKind.sftp;

  @override
  String get badge => 'REMOTE';

  @override
  bool get supportsTransfer => false;

  @override
  bool get supportsMutation => false;

  @override
  String get initialPath =>
      connection.remotePath.isEmpty ? '/' : connection.remotePath;

  @override
  String displayPath(String path) =>
      '${connection.protocol.label.toLowerCase()}://${connection.username}@${connection.name}$path';

  @override
  Future<List<FileItem>> list(String path) async {
    return const [
      FileItem(name: '..', isDir: true),
      FileItem(name: 'logs', isDir: true),
      FileItem(name: 'readme.txt', sizeBytes: 120),
    ];
  }

  @override
  Future<ReadHandle> openRead(String path) =>
      throw UnsupportedError('FakeRemoteBackend does not transfer bytes');

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  }) => throw UnsupportedError('FakeRemoteBackend does not transfer bytes');

  @override
  String childPath(String path, String name, bool isDir) {
    final base = path.endsWith('/') ? path : '$path/';
    return '$base$name';
  }

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }
}
