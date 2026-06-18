import 'package:flutter/foundation.dart';

import '../fs/storage_backend.dart';
import '../models/connection.dart';
import '../models/file_item.dart';

/// Holds the live state of one browser pane: which endpoint/backend it points
/// at, the current directory, the listing, and selection — plus async
/// loading/error state for real backends (Local / S3).
class PaneController {
  PaneController({required this.backend, required this.onChanged, this.connection});

  StorageBackend backend;

  /// `null` means the Local endpoint; otherwise the saved connection in use.
  Connection? connection;

  final VoidCallback onChanged;

  late String path = backend.initialPath;
  List<FileItem> items = const [];
  bool loading = false;
  String? error;
  int? selectedIndex;

  String get badge => backend.badge;
  String get displayPath => backend.displayPath(path);
  EndpointKind get kind => backend.kind;
  bool get isReady => backend.isReady;

  String get endpointLabel => connection?.name ?? 'Local';

  /// List of path segments for the breadcrumb.
  List<String> get breadcrumb {
    final raw = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    final head = connection == null ? '~' : (connection!.isS3 ? connection!.bucket : '/');
    return [head, ...raw];
  }

  Future<void> switchTo(StorageBackend newBackend, Connection? newConnection) async {
    backend = newBackend;
    connection = newConnection;
    path = newBackend.initialPath;
    selectedIndex = null;
    error = null;
    await refresh();
  }

  Future<void> refresh() async {
    if (!backend.isReady) {
      items = const [];
      error = null;
      loading = false;
      onChanged();
      return;
    }
    loading = true;
    error = null;
    onChanged();
    try {
      items = await backend.list(path);
    } catch (e) {
      items = const [];
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      selectedIndex = null;
      onChanged();
    }
  }

  Future<void> open(FileItem item) async {
    if (item.isParent) {
      path = backend.parentPath(path);
    } else if (item.isDir) {
      path = backend.childPath(path, item.name, true);
    } else {
      return;
    }
    await refresh();
  }

  Future<void> goUp() async {
    path = backend.parentPath(path);
    await refresh();
  }

  void select(int index) {
    selectedIndex = index;
    onChanged();
  }
}

/// What gets carried during a drag from one pane to another.
class DragPayload {
  final FileItem item;
  final bool fromLeft;
  const DragPayload(this.item, this.fromLeft);
}
