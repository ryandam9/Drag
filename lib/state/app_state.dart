import 'dart:async';
import 'package:flutter/material.dart';

import '../data/connection_store.dart';
import '../data/history_db.dart';
import '../data/mock_data.dart';
import '../fs/sftp_backend.dart';
import '../fs/storage_backend.dart';
import '../fs/transfer_service.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../theme.dart';
import 'pane_controller.dart';
import 'session.dart';

export 'pane_controller.dart' show DragPayload;
export 'session.dart' show Session;

enum AppScreen { browser, connections, queue, dashboard, settings }

class ToastMessage {
  final String title;
  final String subtitle;
  final String? detail;
  final ToastKind kind;
  final int id;
  ToastMessage(this.id, this.title, this.subtitle, this.kind, {this.detail});
}

enum ToastKind { success, error, info }

extension ToastKindStyle on ToastKind {
  String get icon => switch (this) {
        ToastKind.success => '✅',
        ToastKind.error => '❌',
        ToastKind.info => 'ℹ️',
      };

  Color get color => switch (this) {
        ToastKind.success => FsColors.green,
        ToastKind.error => FsColors.red,
        ToastKind.info => FsColors.accent,
      };

  Color get fg => switch (this) {
        ToastKind.success => FsColors.badgeDoneFg,
        ToastKind.error => FsColors.badgeErrorFg,
        ToastKind.info => FsColors.accentHi,
      };
}

/// Single source of truth for the app. Drives navigation, the two file panes
/// (each backed by Local / S3 / simulated-SFTP), the transfer queue and toasts.
class AppState extends ChangeNotifier {
  /// [tickEnabled] starts the demo ticker (disable for deterministic tests);
  /// [autoRefreshPanes] kicks off the initial pane listings (disable in tests
  /// that don't want real filesystem I/O).
  AppState({
    bool tickEnabled = true,
    bool autoRefreshPanes = true,
    HistoryRepository? history,
    ConnectionStore? connectionStore,
    List<Connection>? connections,
  }) {
    _history = history;
    _connectionStore = connectionStore;
    if (connections != null) {
      this.connections
        ..clear()
        ..addAll(connections);
    }
    selectedConnection = this.connections.first;
    // Start with one session: Local ⇄ the first S3 account (surfaces the feature).
    final firstS3 = this.connections.firstWhere((c) => c.isS3, orElse: () => this.connections.first);
    final initial = _buildSession(firstS3);
    sessions.add(initial);
    activeSessionId = initial.id;
    if (tickEnabled) {
      _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
    }
    if (autoRefreshPanes) {
      leftPane.refresh();
      rightPane.refresh();
    }
    if (_history != null) refreshHistory();
  }

  Timer? _ticker;
  bool _disposed = false;
  final TransferService _transfers = TransferService();
  final LocalBackend _localBackend = LocalBackend();
  final Map<Connection, StorageBackend> _backendCache = {};
  late final HistoryRepository? _history;
  late final ConnectionStore? _connectionStore;

  AppScreen screen = AppScreen.browser;

  final List<Connection> connections = buildConnections();
  final List<Transfer> transfers = buildTransfers();
  final List<ToastMessage> toasts = [];

  bool get hasConnectionStore => _connectionStore != null;

  // ── Transfer history (SQLite-backed) ──
  List<TransferRecord> history = const [];
  HistoryStats historyStats = const HistoryStats();
  bool get hasHistoryDb => _history != null;

  // ── Sessions (tabs) ──
  final List<Session> sessions = [];
  int _sessionSeq = 0;
  late int activeSessionId;

  Session get activeSession =>
      sessions.firstWhere((s) => s.id == activeSessionId, orElse: () => sessions.first);

  /// The active session's panes. Most of the app talks to these getters, so it
  /// transparently follows whichever tab is in front.
  PaneController get leftPane => activeSession.left;
  PaneController get rightPane => activeSession.right;

  late Connection selectedConnection;

  int maxThreads = 5;
  int _toastSeq = 0;

  // ── Settings (Appearance) ──
  String themeName = 'Dark (default)';
  Color accent = FsColors.accent;
  bool showHiddenFiles = true;
  bool showPermsColumn = true;
  bool showLogOnStartup = false;
  bool confirmOverwrite = true;

  void go(AppScreen s) {
    screen = s;
    notifyListeners();
  }

  void selectConnection(Connection c) {
    selectedConnection = c;
    notifyListeners();
  }

  void setMaxThreads(int v) {
    maxThreads = v.clamp(1, 16);
    notifyListeners();
  }

  // ── Saved connections (persisted) ─────────────────────────────────────

  Future<void> _persistConnections() async {
    await _connectionStore?.replaceAll(connections);
  }

  /// Create a blank connection, select it, and persist.
  Future<Connection> newConnection() async {
    final c = Connection(id: Connection.newId(), name: 'New connection', host: '');
    connections.add(c);
    selectedConnection = c;
    notifyListeners();
    await _persistConnections();
    return c;
  }

  /// Persist edits made to [c] (in place via the form).
  Future<void> saveConnection(Connection c) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    await _connectionStore?.upsert(c, connections.indexOf(c).clamp(0, connections.length));
    notifyListeners();
  }

  Future<Connection> duplicateConnection(Connection c) async {
    final copy = Connection.fromJson(c.toJson())
      ..id = Connection.newId()
      ..name = '${c.name} (copy)';
    final idx = connections.indexOf(c);
    connections.insert(idx < 0 ? connections.length : idx + 1, copy);
    selectedConnection = copy;
    notifyListeners();
    await _persistConnections();
    return copy;
  }

  Future<void> deleteConnection(Connection c) async {
    final idx = connections.indexOf(c);
    connections.remove(c);
    _backendCache.remove(c);
    if (connections.isEmpty) connections.add(Connection(id: Connection.newId(), name: 'New connection'));
    if (identical(selectedConnection, c)) {
      selectedConnection = connections[idx.clamp(0, connections.length - 1)];
    }
    notifyListeners();
    await _persistConnections();
  }

  // ── Endpoints / backends ──────────────────────────────────────────────

  /// Builds (and caches) the backend for a connection. `null` → Local.
  StorageBackend _backendFor(Connection? c) {
    if (c == null) return _localBackend;
    return _backendCache.putIfAbsent(
        c, () => c.isS3 ? S3Backend(c) : SftpBackend(c));
  }

  /// Point the active session's pane at Local (`null`) or a saved connection.
  Future<void> setPaneEndpoint(bool left, Connection? c) async {
    final pane = left ? leftPane : rightPane;
    await pane.switchTo(_backendFor(c), c);
  }

  // ── Sessions / tabs ───────────────────────────────────────────────────

  Session _buildSession(Connection? remote) {
    final left = PaneController(backend: _localBackend, onChanged: _safeNotify);
    final right =
        PaneController(backend: _backendFor(remote), connection: remote, onChanged: _safeNotify);
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
          notifyListeners();
          return s;
        }
      }
    }
    final s = _buildSession(remote);
    sessions.add(s);
    activeSessionId = s.id;
    s.left.refresh();
    s.right.refresh();
    notifyListeners();
    return s;
  }

  void switchSession(int id) {
    if (sessions.any((s) => s.id == id) && id != activeSessionId) {
      activeSessionId = id;
      notifyListeners();
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
    notifyListeners();
  }

  /// Connect to [c]: rebuild its backend (fresh credentials) and open/focus a
  /// tab for it. S3 connections need credentials first.
  Future<void> connect(Connection c) async {
    c.online = c.isS3 ? c.hasS3Credentials : true;
    _backendCache.remove(c); // pick up freshly entered credentials
    if (c.isS3 && !c.hasS3Credentials) {
      pushToast('Missing credentials', 'Enter Access Key, Secret & Bucket for ${c.name}', ToastKind.error);
      notifyListeners();
      return;
    }
    openSession(c);
    pushToast('Session connected', '${c.name} · ${c.protocol.label}', ToastKind.info);
    go(AppScreen.browser);
  }

  // ── Transfers ─────────────────────────────────────────────────────────

  int get activeCount => transfers.where((t) => t.status == TransferStatus.active).length;
  int get queuedCount => transfers.where((t) => t.status == TransferStatus.queued).length;
  int get doneCount => transfers.where((t) => t.status == TransferStatus.done).length;
  int get errorCount => transfers.where((t) => t.status == TransferStatus.error).length;
  int get pausedCount => transfers.where((t) => t.status == TransferStatus.paused).length;

  /// Handle a drag from one pane dropped onto another → start a transfer.
  void dropTransfer(DragPayload payload, bool ontoLeft) {
    if (payload.fromLeft == ontoLeft) return; // dropped on its own pane
    final src = payload.fromLeft ? leftPane : rightPane;
    final dst = ontoLeft ? leftPane : rightPane;
    final item = payload.item;

    if (item.isDir || item.isParent) {
      pushToast('Not supported', 'Folder transfers aren\'t supported yet — drag files', ToastKind.info);
      return;
    }
    if (!src.isReady || !dst.isReady) {
      pushToast('Not connected', 'Connect the S3 endpoint (add credentials) first', ToastKind.error);
      return;
    }

    final srcPath = src.backend.childPath(src.path, item.name, false);
    final dstPath = dst.backend.childPath(dst.path, item.name, false);
    // Real transfer unless one side can't actually move bytes (demo backend).
    final simulated = !src.backend.supportsTransfer || !dst.backend.supportsTransfer;
    final direction =
        dst.kind == EndpointKind.local ? TransferDirection.download : TransferDirection.upload;

    final t = Transfer(
      name: item.name,
      route: '${src.endpointLabel} → ${dst.displayPath}',
      direction: direction,
      sizeBytes: item.sizeBytes ?? 0,
      session: dst.endpointLabel,
      status: TransferStatus.queued,
      live: !simulated,
      sourcePath: '${src.endpointLabel}:$srcPath',
      destPath: dst.displayPath,
    );
    transfers.insert(0, t);
    notifyListeners();

    if (simulated) {
      pushToast('Queued', '${item.name} → ${dst.endpointLabel}', ToastKind.info);
      return;
    }

    // Real, streamed transfer (Local↔S3 or S3↔S3).
    pushToast('Transfer started', '${item.name} → ${dst.endpointLabel}', ToastKind.info);
    _transfers
        .run(
      t: t,
      src: src.backend,
      srcPath: srcPath,
      dst: dst.backend,
      dstPath: dstPath,
      onChange: _safeNotify,
    )
        .then((_) {
      if (_disposed) return;
      _record(t);
      if (t.status == TransferStatus.done) {
        _completionToast(t);
        if (identical(dst, rightPane) || identical(dst, leftPane)) dst.refresh();
      } else if (t.status == TransferStatus.error) {
        pushToast('Transfer failed', '${item.name}: ${t.errorMessage ?? 'error'}', ToastKind.error);
      }
    });
  }

  void pauseAll() {
    for (final t in transfers) {
      if (t.status == TransferStatus.active || t.status == TransferStatus.queued) {
        t.status = TransferStatus.paused;
        t.speed = '—';
        t.eta = '—';
      }
    }
    notifyListeners();
  }

  void resumeAll() {
    for (final t in transfers) {
      if (t.status == TransferStatus.paused) t.status = TransferStatus.queued;
    }
    notifyListeners();
  }

  void clearDone() {
    transfers.removeWhere((t) => t.status == TransferStatus.done);
    notifyListeners();
  }

  void togglePause(Transfer t) {
    switch (t.status) {
      case TransferStatus.active:
      case TransferStatus.queued:
        t.status = TransferStatus.paused;
        t.speed = '—';
        t.eta = '—';
      case TransferStatus.paused:
        t.status = TransferStatus.queued;
      default:
        break;
    }
    notifyListeners();
  }

  void retry(Transfer t) {
    t.status = TransferStatus.queued;
    t.errorMessage = null;
    t.progress = 0;
    notifyListeners();
  }

  void pushToast(String title, String sub, ToastKind kind, {String? detail}) {
    if (_disposed) return;
    final msg = ToastMessage(_toastSeq++, title, sub, kind, detail: detail);
    toasts.add(msg);
    notifyListeners();
    Future.delayed(const Duration(seconds: 5), () {
      toasts.removeWhere((m) => m.id == msg.id);
      _safeNotify();
    });
  }

  /// Rich "transfer completed" notification: destination path, size, time.
  void _completionToast(Transfer t) {
    final dest = t.destPath.isNotEmpty ? t.destPath : '${t.session} · ${t.name}';
    pushToast(
      'File transfer completed',
      dest,
      ToastKind.success,
      detail: '${formatBytes(t.sizeBytes)} · ${t.elapsedLabel}'
          '${t.speed != '—' ? ' · ${t.speed}' : ''}',
    );
  }

  /// Persist a finished transfer to history and refresh the dashboard data.
  Future<void> _record(Transfer t) async {
    final repo = _history;
    if (repo == null) return;
    try {
      await repo.add(TransferRecord.fromTransfer(t));
      await refreshHistory();
    } catch (_) {/* history is best-effort */}
  }

  Future<void> refreshHistory() async {
    final repo = _history;
    if (repo == null) return;
    history = await repo.recent();
    historyStats = await repo.stats();
    _safeNotify();
  }

  Future<void> clearHistory() async {
    await _history?.clear();
    await refreshHistory();
  }

  /// Notify only while still mounted — async callbacks (toasts, live
  /// transfers) may resolve after the AppState has been disposed.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Advances *simulated* transfers only (real ones are driven by
  /// [TransferService]). Keeps the demo queue feeling alive.
  void _tick() {
    var changed = false;
    for (final t in transfers) {
      if (t.live) continue;
      if (t.status == TransferStatus.active) {
        changed = true;
        t.startedAt ??= DateTime.now();
        final step = t.sizeBytes > 10 * mB ? 0.015 : 0.18;
        t.progress = (t.progress + step).clamp(0, 1);
        if (t.progress >= 1) {
          t.status = TransferStatus.done;
          t.eta = 'Done';
          t.speed = t.speed == '—' ? '1.0 MB/s' : t.speed;
          t.finishedAt = DateTime.now();
          _completionToast(t);
          _record(t);
        } else {
          final remaining = ((1 - t.progress) * (t.sizeBytes > 10 * mB ? 90 : 4)).round();
          t.eta = '0:${remaining.toString().padLeft(2, '0')}';
        }
      }
    }

    final simActive = transfers.where((t) => !t.live && t.status == TransferStatus.active).length;
    if (simActive < maxThreads) {
      for (final t in transfers) {
        if (!t.live && t.status == TransferStatus.queued) {
          t.status = TransferStatus.active;
          t.startedAt = DateTime.now();
          t.speed = t.sizeBytes > 10 * mB ? '1.4 MB/s' : '210 KB/s';
          changed = true;
          break;
        }
      }
    }

    if (changed) notifyListeners();
  }

  /// Advances the simulated transfer ticker once (for deterministic tests).
  @visibleForTesting
  void debugTick() => _tick();

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}

/// Lightweight DI: exposes [AppState] to the widget tree and rebuilds listeners.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }
}
