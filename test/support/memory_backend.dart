import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';

/// An in-memory [StorageBackend] for widget tests. All operations complete via
/// microtasks (no real I/O), so they resolve under `testWidgets`' fake-async
/// zone — unlike [LocalBackend], whose disk I/O would hang there.
///
/// Paths are POSIX-like and rooted at '/'.
class MemoryBackend extends StorageBackend {
  MemoryBackend({Set<String>? dirs, Map<String, Uint8List>? files})
      : _dirs = dirs ?? {'/'},
        _files = files ?? {} {
    _dirs.add('/');
  }

  final Set<String> _dirs;
  final Map<String, Uint8List> _files;

  /// Convenience: a backend pre-seeded with a couple of files and a folder.
  factory MemoryBackend.sample() => MemoryBackend(
        dirs: {'/', '/nested'},
        files: {
          '/alpha.txt': Uint8List.fromList(List.filled(4, 1)),
          '/beta.bin': Uint8List.fromList(List.filled(2048, 2)),
          '/nested/inner.txt': Uint8List.fromList(List.filled(8, 3)),
        },
      );

  @override
  EndpointKind get kind => EndpointKind.local;
  @override
  String get badge => 'LOCAL';
  @override
  String get initialPath => '/';
  @override
  String displayPath(String path) => path;

  @override
  Future<List<FileItem>> list(String path) async {
    final base = path == '/' ? '/' : (path.endsWith('/') ? path.substring(0, path.length - 1) : path);
    final items = <FileItem>[];
    if (base != '/') items.add(const FileItem(name: '..', isDir: true));
    final seen = <String>{};
    void consider(String full, bool isDir) {
      final prefix = base == '/' ? '/' : '$base/';
      if (!full.startsWith(prefix) || full == base) return;
      final rest = full.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) return; // not a direct child
      if (!seen.add(rest)) return;
      items.add(FileItem(
        name: rest,
        isDir: isDir,
        sizeBytes: isDir ? null : _files[full]?.length,
        modified: '2025-01-01  00:00',
        perms: isDir ? 'drwxr-xr-x' : '-rw-r--r--',
      ));
    }

    for (final d in _dirs) {
      consider(d, true);
    }
    for (final f in _files.keys) {
      consider(f, false);
    }
    items.sort(StorageBackend.dirsFirst);
    return items;
  }

  @override
  Future<ReadHandle> openRead(String path) async {
    final bytes = _files[path] ?? Uint8List(0);
    return ReadHandle(Stream<Uint8List>.value(bytes), bytes.length);
  }

  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
      {void Function(int sent)? onProgress}) async {
    final out = <int>[];
    await for (final chunk in data) {
      out.addAll(chunk);
      onProgress?.call(out.length);
    }
    _files[path] = Uint8List.fromList(out);
  }

  @override
  Future<void> makeDir(String path) async =>
      _dirs.add(path.endsWith('/') ? path.substring(0, path.length - 1) : path);

  @override
  Future<void> rename(String fromPath, String toPath) async {
    if (_files.containsKey(fromPath)) {
      _files[toPath] = _files.remove(fromPath)!;
    } else if (_dirs.remove(fromPath)) {
      _dirs.add(toPath);
    }
  }

  @override
  Future<void> delete(String path, {required bool isDir}) async {
    if (isDir) {
      _dirs.remove(path);
      _files.removeWhere((k, _) => k == path || k.startsWith('$path/'));
    } else {
      _files.remove(path);
    }
  }

  @override
  String childPath(String path, String name, bool isDir) {
    final base = path == '/' ? '' : (path.endsWith('/') ? path.substring(0, path.length - 1) : path);
    return '$base/$name';
  }

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }
}
