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

  /// Anchor / primary selection (used for shift-range and single-item actions).
  int? selectedIndex;

  /// All selected row indices (multi-select).
  final Set<int> selection = {};

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

  final List<String> _back = [];
  final List<String> _forward = [];
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  Future<void> switchTo(StorageBackend newBackend, Connection? newConnection) async {
    backend = newBackend;
    connection = newConnection;
    path = newBackend.initialPath;
    selectedIndex = null;
    error = null;
    _back.clear();
    _forward.clear();
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
      selection.clear();
      onChanged();
    }
  }

  Future<void> open(FileItem item) async {
    if (item.isParent) {
      await _navigate(backend.parentPath(path));
    } else if (item.isDir) {
      await _navigate(backend.childPath(path, item.name, true));
    }
  }

  Future<void> goUp() => _navigate(backend.parentPath(path));

  Future<void> _navigate(String newPath) async {
    if (newPath == path) return;
    _back.add(path);
    _forward.clear();
    path = newPath;
    await refresh();
  }

  Future<void> goBack() async {
    if (_back.isEmpty) return;
    _forward.add(path);
    path = _back.removeLast();
    await refresh();
  }

  Future<void> goForward() async {
    if (_forward.isEmpty) return;
    _back.add(path);
    path = _forward.removeLast();
    await refresh();
  }

  /// Single selection (replaces any existing selection).
  void select(int index) {
    selection
      ..clear()
      ..add(index);
    selectedIndex = index;
    onChanged();
  }

  /// Toggle [index] in the selection (Ctrl/Cmd-click).
  void toggleSelect(int index) {
    if (!selection.remove(index)) selection.add(index);
    selectedIndex = index;
    onChanged();
  }

  /// Select the contiguous range from the anchor to [index] (Shift-click).
  void selectRange(int index) {
    final anchor = selectedIndex ?? index;
    final lo = anchor < index ? anchor : index;
    final hi = anchor < index ? index : anchor;
    selection
      ..clear()
      ..addAll([for (var k = lo; k <= hi; k++) k]);
    onChanged();
  }

  bool isSelected(int index) => selection.contains(index);

  /// The selected, non-parent entries (in listing order).
  List<FileItem> selectedItems() {
    final idx = selection.where((i) => i >= 0 && i < items.length).toList()..sort();
    return [for (final i in idx) if (!items[i].isParent) items[i]];
  }
}

/// What gets carried during a drag from one pane to another.
class DragPayload {
  final FileItem item;
  final bool fromLeft;
  const DragPayload(this.item, this.fromLeft);
}
