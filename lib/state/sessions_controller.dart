import 'package:flutter/material.dart';

import '../fs/sftp_backend.dart';
import '../fs/storage_backend.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import 'pane_controller.dart';
import 'session.dart';
import 'toast.dart';

/// Owns the open session tabs and their two panes each, pane focus, endpoint
/// switching and the per-pane file operations. Backends are built and cached
/// here. File-op feedback is surfaced through [onToast].
class SessionsController extends ChangeNotifier {
  SessionsController({
    required Connection? initialRemote,
    required bool showHidden,
    bool autoRefresh = true,
    this.onToast,
  })
      // ignore: prefer_initializing_formals
      : _showHidden = showHidden {
    final initial = _buildSession(initialRemote);
    sessions.add(initial);
    activeSessionId = initial.id;
    if (autoRefresh) {
      leftPane.refresh();
      rightPane.refresh();
    }
  }

  final ToastSink? onToast;
  bool _showHidden;

  final LocalBackend _localBackend = LocalBackend();
  final Map<Connection, StorageBackend> _backendCache = {};

  final List<Session> sessions = [];
  int _sessionSeq = 0;
  late int activeSessionId;

  /// Which pane toolbar/keyboard actions target.
  bool focusedLeft = true;

  bool _disposed = false;

  Session get activeSession =>
      sessions.firstWhere((s) => s.id == activeSessionId, orElse: () => sessions.first);

  PaneController get leftPane => activeSession.left;
  PaneController get rightPane => activeSession.right;
  PaneController get focusedPane => focusedLeft ? leftPane : rightPane;

  // ── Backends ──
  /// Builds (and caches) the backend for a connection. `null` → Local.
  StorageBackend backendFor(Connection? c) {
    if (c == null) return _localBackend;
    return _backendCache.putIfAbsent(c, () => c.isS3 ? S3Backend(c) : SftpBackend(c));
  }

  /// Drop a cached backend (e.g. when a connection is deleted or reconnected).
  void evictBackend(Connection c) => _backendCache.remove(c);

  Session _buildSession(Connection? remote) {
    final left = PaneController(
        backend: _localBackend, onChanged: _notify, showHidden: _showHidden);
    final right = PaneController(
        backend: backendFor(remote),
        connection: remote,
        onChanged: _notify,
        showHidden: _showHidden);
    return Session(id: _sessionSeq++, left: left, right: right);
  }

  /// Open a new tab for [remote] (null = a Local-only tab), or focus the
  /// existing tab already connected to it. Keeps every server in its own tab.
  Session openSession(Connection? remote) {
    if (remote != null) {
      for (final s in sessions) {
        if (identical(s.connection, remote)) {
          activeSessionId = s.id;
          s.right.refresh();
          _notify();
          return s;
        }
      }
    }
    final s = _buildSession(remote);
    sessions.add(s);
    activeSessionId = s.id;
    s.left.refresh();
    s.right.refresh();
    _notify();
    return s;
  }

  void switchSession(int id) {
    if (sessions.any((s) => s.id == id) && id != activeSessionId) {
      activeSessionId = id;
      _notify();
    }
  }

  void closeSession(int id) {
    final idx = sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    sessions.removeAt(idx);
    if (sessions.isEmpty) {
      // Never leave zero tabs — drop back to a fresh Local workspace.
      final fresh = _buildSession(null);
      sessions.add(fresh);
      activeSessionId = fresh.id;
      fresh.left.refresh();
    } else if (activeSessionId == id) {
      activeSessionId = sessions[idx.clamp(0, sessions.length - 1)].id;
    }
    _notify();
  }

  void focusPane(bool left) {
    if (focusedLeft != left) {
      focusedLeft = left;
      _notify();
    }
  }

  /// Point the active session's pane at Local (`null`) or a saved connection.
  Future<void> setPaneEndpoint(bool left, Connection? c) async {
    final pane = left ? leftPane : rightPane;
    await pane.switchTo(backendFor(c), c);
  }

  /// Re-filter every pane after the "show hidden files" setting changes.
  void applyShowHidden(bool show) {
    _showHidden = show;
    for (final s in sessions) {
      s.left.setShowHidden(show);
      s.right.setShowHidden(show);
    }
  }

  // ── File operations ──
  Future<void> createFolder(PaneController pane, String name) async {
    if (name.trim().isEmpty) return;
    if (!pane.backend.supportsMutation) {
      onToast?.call('Not supported', '${pane.endpointLabel} is read-only here', ToastKind.error);
      return;
    }
    try {
      await pane.backend.makeDir(pane.backend.childPath(pane.path, name.trim(), true));
      await pane.refresh();
      onToast?.call('Folder created', name.trim(), ToastKind.success);
    } catch (e) {
      onToast?.call('Couldn\'t create folder', _short(e), ToastKind.error);
    }
  }

  Future<void> renameItem(PaneController pane, FileItem item, String newName) async {
    if (item.isParent || newName.trim().isEmpty || newName.trim() == item.name) return;
    try {
      final from = pane.backend.childPath(pane.path, item.name, item.isDir);
      final to = pane.backend.childPath(pane.path, newName.trim(), item.isDir);
      await pane.backend.rename(from, to);
      await pane.refresh();
      onToast?.call('Renamed', '${item.name} → ${newName.trim()}', ToastKind.success);
    } catch (e) {
      onToast?.call('Couldn\'t rename', _short(e), ToastKind.error);
    }
  }

  Future<void> deleteItem(PaneController pane, FileItem item) => deleteItems(pane, [item]);

  Future<void> deleteItems(PaneController pane, List<FileItem> items) async {
    final targets = items.where((i) => !i.isParent).toList();
    if (targets.isEmpty) return;
    var failed = 0;
    for (final item in targets) {
      try {
        await pane.backend.delete(pane.backend.childPath(pane.path, item.name, item.isDir),
            isDir: item.isDir);
      } catch (_) {
        failed++;
      }
    }
    await pane.refresh();
    if (failed == 0) {
      onToast?.call('Deleted', targets.length == 1 ? targets.first.name : '${targets.length} items',
          ToastKind.info);
    } else {
      onToast?.call('Delete incomplete', '$failed of ${targets.length} failed', ToastKind.error);
    }
  }

  String _short(Object e) {
    final m = e.toString().replaceFirst('Exception: ', '');
    return m.length > 80 ? '${m.substring(0, 80)}…' : m;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
