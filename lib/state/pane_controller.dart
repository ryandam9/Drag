import 'package:flutter/foundation.dart';

import '../fs/storage_backend.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import 'compare.dart';

/// A sortable file-table column.
enum SortKey { name, size, modified, perms }

/// Returns a new list sorted by [key] in [ascending] order. The `..` parent is
/// always pinned first and directories are always grouped before files; only
/// entries *within* a group are reordered by the column, so toggling direction
/// never scatters folders among files. Ties fall back to case-insensitive name.
List<FileItem> sortItems(List<FileItem> items, SortKey key, bool ascending) {
  int byKey(FileItem a, FileItem b) {
    switch (key) {
      case SortKey.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortKey.size:
        return (a.sizeBytes ?? -1).compareTo(b.sizeBytes ?? -1);
      case SortKey.modified:
        return a.modified.compareTo(b.modified);
      case SortKey.perms:
        return a.perms.compareTo(b.perms);
    }
  }

  final sorted = [...items];
  sorted.sort((a, b) {
    if (a.isParent != b.isParent) return a.isParent ? -1 : 1;
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    var c = byKey(a, b);
    if (c == 0) c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return ascending ? c : -c;
  });
  return sorted;
}

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

  /// The listing the UI sees (after the hidden-file filter, the in-pane name
  /// filter and the active sort). Selection indices are relative to this list.
  List<FileItem> items = const [];
  bool loading = false;
  String? error;

  /// In-pane name filter (substring, case-insensitive). Empty shows everything.
  String filterQuery = '';

  /// The active sort column and direction (default: name ascending).
  SortKey sortKey = SortKey.name;
  bool sortAscending = true;

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
      _applyView();
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

  /// Recomputes [items] from [_all] by applying, in order: the hidden-file
  /// filter, the in-pane name filter, and the active sort.
  void _applyView() {
    Iterable<FileItem> v = _all;
    if (!showHidden) v = v.where((f) => f.isParent || !f.name.startsWith('.'));
    final q = filterQuery.trim().toLowerCase();
    if (q.isNotEmpty) v = v.where((f) => f.isParent || f.name.toLowerCase().contains(q));
    items = sortItems(v.toList(), sortKey, sortAscending);
  }

  /// Toggle hidden-file visibility, re-filtering the current listing in place
  /// (clears selection, since indices shift).
  void setShowHidden(bool value) {
    if (showHidden == value) return;
    showHidden = value;
    _resetView();
  }

  /// Set the in-pane name filter and re-apply the view.
  void setFilter(String query) {
    if (filterQuery == query) return;
    filterQuery = query;
    _resetView();
  }

  /// Sort by [key]; selecting the active column flips the direction.
  void setSort(SortKey key) {
    if (sortKey == key) {
      sortAscending = !sortAscending;
    } else {
      sortKey = key;
      sortAscending = true;
    }
    _resetView();
  }

  /// Re-derive [items] and drop the (now index-shifted) selection.
  void _resetView() {
    selectedIndex = null;
    selection.clear();
    _applyView();
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

  /// Navigate up [levels] directories at once (for clickable breadcrumbs).
  /// Applies [StorageBackend.parentPath] repeatedly, so it works for every
  /// backend without per-backend path maths.
  Future<void> goUpLevels(int levels) async {
    if (levels <= 0) return;
    var target = path;
    for (var i = 0; i < levels; i++) {
      target = backend.parentPath(target);
    }
    await _navigate(target);
  }

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

  /// Move the single selection by [delta] rows (negative = up), clamped to the
  /// listing. Drives keyboard up/down and page navigation. With nothing
  /// selected, a downward move lands on the first row and an upward move on the
  /// last. No-op on an empty listing.
  void moveSelection(int delta) {
    if (items.isEmpty) return;
    final cur = selectedIndex ?? (delta >= 0 ? -1 : items.length);
    select((cur + delta).clamp(0, items.length - 1));
  }

  /// Select the first or last row (Home / End).
  void selectEdge({required bool last}) {
    if (items.isEmpty) return;
    select(last ? items.length - 1 : 0);
  }

  /// Type-ahead: select the next entry whose name starts with [prefix]
  /// (case-insensitive), wrapping around the listing. A single-character prefix
  /// advances past the current row so repeated presses cycle through matches;
  /// a longer prefix prefers to stay on the current row if it still matches.
  /// Returns true when a match was selected.
  bool typeAhead(String prefix) {
    if (prefix.isEmpty || items.isEmpty) return false;
    final q = prefix.toLowerCase();
    final anchor = selectedIndex ?? -1;
    final from = q.length <= 1 ? anchor + 1 : anchor;
    final base = from < 0 ? 0 : from;
    for (var k = 0; k < items.length; k++) {
      final i = (base + k) % items.length;
      final f = items[i];
      if (!f.isParent && f.name.toLowerCase().startsWith(q)) {
        select(i);
        return true;
      }
    }
    return false;
  }

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
