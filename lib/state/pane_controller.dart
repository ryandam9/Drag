import 'package:flutter/foundation.dart';

import '../fs/storage_backend.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import 'compare.dart';

/// Holds the live state of one browser pane: which endpoint/backend it points
/// at, the current directory, the listing, and selection — plus async
/// loading/error state for real backends (Local / S3).
class PaneController {
  PaneController(
      {required this.backend,
      required this.onChanged,
      this.connection,
      this.showHidden = true});

  StorageBackend backend;

  /// `null` means the Local endpoint; otherwise the saved connection in use.
  Connection? connection;

  final VoidCallback onChanged;

  /// When false, dot-files (names starting with `.`) are filtered out of the
  /// listing. Driven by the "Show hidden files" setting.
  bool showHidden;

  late String path = backend.initialPath;

  /// The unfiltered listing as returned by the backend.
  List<FileItem> _all = const [];

  /// The listing the UI sees (after the hidden-file filter). Selection indices
  /// are relative to this list.
  List<FileItem> items = const [];
  bool loading = false;
  String? error;

  /// Per-entry comparison marks from the last Compare (by name). Empty when no
  /// comparison is active; cleared automatically when the listing reloads.
  Map<String, CompareMark> compareMarks = const {};

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
    final head = connection == null
        ? '~'
        : (connection!.isS3 ? (connection!.bucket.isEmpty ? 's3' : connection!.bucket) : '/');
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
      _all = const [];
      items = const [];
      error = null;
      loading = false;
      onChanged();
      return;
    }
    loading = true;
    error = null;
    compareMarks = const {}; // a fresh listing invalidates any comparison
    onChanged();
    try {
      _all = await backend.list(path);
      _applyFilter();
    } catch (e) {
      _all = const [];
      items = const [];
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      selectedIndex = null;
      selection.clear();
      onChanged();
    }
  }

  void _applyFilter() {
    items = showHidden
        ? _all
        : _all.where((f) => f.isParent || !f.name.startsWith('.')).toList();
  }

  /// Toggle hidden-file visibility, re-filtering the current listing in place
  /// (clears selection, since indices shift).
  void setShowHidden(bool value) {
    if (showHidden == value) return;
    showHidden = value;
    selectedIndex = null;
    selection.clear();
    _applyFilter();
    onChanged();
  }

  Future<void> open(FileItem item) async {
    if (item.isParent) {
      await _navigate(backend.parentPath(path));
    } else if (item.isDir) {
      await _navigate(backend.childPath(path, item.name, true));
    }
  }

  Future<void> goUp() => _navigate(backend.parentPath(path));

  /// Jump straight to [newPath] (e.g. a bookmark) on the current backend.
  Future<void> navigateTo(String newPath) => _navigate(newPath);

  /// Recently visited paths on this backend (most recent first, deduped, and
  /// excluding the current path), for the quick-jump menu.
  List<String> get recentPaths {
    final seen = <String>{path};
    final out = <String>[];
    for (final p in _back.reversed) {
      if (seen.add(p)) out.add(p);
    }
    return out;
  }

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
