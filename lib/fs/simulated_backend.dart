import 'dart:typed_data';

import '../data/mock_data.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import 'storage_backend.dart';

/// Stand-in backend for SFTP sessions. Browsing returns the mock listing and
/// transfers are simulated by the AppState ticker (no real network I/O) — this
/// preserves the original demo behaviour now that Local/S3 are real.
class SimulatedBackend extends StorageBackend {
  SimulatedBackend(this.connection);

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
  String get initialPath => connection.remotePath.isEmpty ? '/' : connection.remotePath;

  @override
  String displayPath(String path) =>
      '${connection.protocol.label.toLowerCase()}://${connection.username}@${connection.name}$path';

  @override
  Future<List<FileItem>> list(String path) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.of(remoteFiles);
  }

  @override
  Future<ReadHandle> openRead(String path) =>
      throw UnsupportedError('SFTP transfers are simulated');

  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
          {void Function(int sent)? onProgress}) =>
      throw UnsupportedError('SFTP transfers are simulated');

  @override
  String childPath(String path, String name, bool isDir) {
    final base = path.endsWith('/') ? path : '$path/';
    return '$base$name';
  }

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }
}
