import 'package:flutter/material.dart';

import '../data/connection_store.dart';
import '../data/history_db.dart';
import '../data/settings_store.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import 'connections_controller.dart';
import 'pane_controller.dart';
import 'session.dart';
import 'sessions_controller.dart';
import 'settings_controller.dart';
import 'toast.dart';
import 'transfers_controller.dart';

export 'pane_controller.dart' show DragPayload;
export 'session.dart' show Session;
export 'toast.dart' show ToastMessage, ToastKind, ToastKindStyle, ToastSink;
export 'settings_controller.dart' show SettingsController;
export 'connections_controller.dart' show ConnectionsController;
export 'sessions_controller.dart' show SessionsController;
export 'transfers_controller.dart' show TransfersController;

enum AppScreen { browser, connections, queue, dashboard, settings }

/// Coordinator for the app. Owns four focused [ChangeNotifier] controllers —
/// [settingsController], [connectionsController], [sessionsController],
/// [transfersController] — plus the cross-cutting bits (navigation, toasts,
/// history). It forwards each controller's notifications so legacy [AppScope]
/// consumers keep working, while widgets that subscribe to a specific
/// controller scope only rebuild for their own slice.
class AppState extends ChangeNotifier {
  /// [tickEnabled] starts the demo ticker (disable for deterministic tests);
  /// [autoRefreshPanes] kicks off the initial pane listings (disable in tests
  /// that don't want real filesystem I/O).
  AppState({
    bool tickEnabled = true,
    bool autoRefreshPanes = true,
    HistoryRepository? history,
    ConnectionStore? connectionStore,
    SettingsStore? settingsStore,
    AppSettings? settings,
    List<Connection>? connections,
  }) {
    _history = history;

    _settings = SettingsController(
      store: settingsStore,
      initial: settings,
      onShowHiddenChanged: (v) => _sessions.applyShowHidden(v),
    );

    _connections = ConnectionsController(
      store: connectionStore,
      initial: connections,
      onRemoved: (c) => _sessions.evictBackend(c),
    );

    // Start with one session: Local ⇄ the first S3 account (surfaces the feature).
    final list = _connections.connections;
    final firstS3 = list.firstWhere((c) => c.isS3, orElse: () => list.first);
    _sessions = SessionsController(
      initialRemote: firstS3,
      showHidden: _settings.showHiddenFiles,
      autoRefresh: autoRefreshPanes,
      onToast: pushToast,
    );

    _transfers = TransfersController(
      tickEnabled: tickEnabled,
      onToast: pushToast,
      onRecord: _record,
    );

    // Forward sub-controller changes so global [AppScope] consumers still update.
    _settings.addListener(_safeNotify);
    _connections.addListener(_safeNotify);
    _sessions.addListener(_safeNotify);
    _transfers.addListener(_safeNotify);

    if (_history != null) refreshHistory();
  }

  late final SettingsController _settings;
  late final ConnectionsController _connections;
  late final SessionsController _sessions;
  late final TransfersController _transfers;
  late final HistoryRepository? _history;

  bool _disposed = false;

  /// The focused sub-controllers (for scoped subscriptions; see *_scope.dart).
  SettingsController get settingsController => _settings;
  ConnectionsController get connectionsController => _connections;
  SessionsController get sessionsController => _sessions;
  TransfersController get transfersController => _transfers;

  // ── Navigation ──
  AppScreen screen = AppScreen.browser;
  void go(AppScreen s) {
    screen = s;
    notifyListeners();
  }

  // ── Toasts ──
  final List<ToastMessage> toasts = [];
  int _toastSeq = 0;

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

  // ── Connections (facade → ConnectionsController) ──
  List<Connection> get connections => _connections.connections;
  Connection get selectedConnection => _connections.selected;
  bool get hasConnectionStore => _connections.hasStore;
  void selectConnection(Connection c) => _connections.select(c);
  Future<Connection> newConnection() => _connections.create();
  Future<void> saveConnection(Connection c) => _connections.save(c);
  Future<Connection> duplicateConnection(Connection c) => _connections.duplicate(c);
  Future<void> deleteConnection(Connection c) => _connections.delete(c);

  /// Connect to [c]: rebuild its backend (fresh credentials) and open/focus a
  /// tab for it. S3 connections need credentials first.
  Future<void> connect(Connection c) async {
    c.online = c.isS3 ? c.hasS3Credentials : true;
    _sessions.evictBackend(c); // pick up freshly entered credentials
    if (c.isS3 && !c.hasS3Credentials) {
      pushToast('Missing credentials', 'Enter Access Key, Secret & Bucket for ${c.name}', ToastKind.error);
      notifyListeners();
      return;
    }
    _sessions.openSession(c);
    pushToast('Session connected', '${c.name} · ${c.protocol.label}', ToastKind.info);
    go(AppScreen.browser);
  }

  // ── Sessions / panes (facade → SessionsController) ──
  List<Session> get sessions => _sessions.sessions;
  int get activeSessionId => _sessions.activeSessionId;
  Session get activeSession => _sessions.activeSession;
  PaneController get leftPane => _sessions.leftPane;
  PaneController get rightPane => _sessions.rightPane;
  bool get focusedLeft => _sessions.focusedLeft;
  PaneController get focusedPane => _sessions.focusedPane;

  void focusPane(bool left) => _sessions.focusPane(left);
  Session openSession(Connection? remote) => _sessions.openSession(remote);
  void switchSession(int id) => _sessions.switchSession(id);
  void closeSession(int id) => _sessions.closeSession(id);
  Future<void> setPaneEndpoint(bool left, Connection? c) => _sessions.setPaneEndpoint(left, c);
  Future<void> createFolder(PaneController pane, String name) => _sessions.createFolder(pane, name);
  Future<void> renameItem(PaneController pane, FileItem item, String newName) =>
      _sessions.renameItem(pane, item, newName);
  Future<void> deleteItem(PaneController pane, FileItem item) => _sessions.deleteItem(pane, item);
  Future<void> deleteItems(PaneController pane, List<FileItem> items) =>
      _sessions.deleteItems(pane, items);

  // ── Transfers (facade → TransfersController) ──
  List<Transfer> get transfers => _transfers.transfers;
  int get maxThreads => _transfers.maxThreads;
  int get activeCount => _transfers.activeCount;
  int get queuedCount => _transfers.queuedCount;
  int get doneCount => _transfers.doneCount;
  int get errorCount => _transfers.errorCount;
  int get pausedCount => _transfers.pausedCount;

  void setMaxThreads(int v) => _transfers.setMaxThreads(v);
  void pauseAll() => _transfers.pauseAll();
  void resumeAll() => _transfers.resumeAll();
  void clearDone() => _transfers.clearDone();
  void togglePause(Transfer t) => _transfers.togglePause(t);
  void retry(Transfer t) => _transfers.retry(t);

  @visibleForTesting
  void debugTick() => _transfers.debugTick();

  /// Handle a drag from one pane dropped onto another → start transfer(s).
  /// Transfers the source pane's whole selection (the dragged row is included).
  void dropTransfer(DragPayload payload, bool ontoLeft) {
    if (payload.fromLeft == ontoLeft) return; // dropped on its own pane
    final src = payload.fromLeft ? leftPane : rightPane;
    final dst = ontoLeft ? leftPane : rightPane;

    final selected = src.selectedItems();
    final candidates = selected.isNotEmpty ? selected : [payload.item];
    final files = candidates.where((f) => !f.isDir && !f.isParent).toList();

    if (files.isEmpty) {
      pushToast('Not supported', 'Folder transfers aren\'t supported yet — drag files', ToastKind.info);
      return;
    }
    if (!src.isReady || !dst.isReady) {
      pushToast('Not connected', 'Connect the S3 endpoint (add credentials) first', ToastKind.error);
      return;
    }

    for (final item in files) {
      _transfers.enqueue(src, dst, item, announce: files.length == 1);
    }
    if (files.length > 1) {
      pushToast('Transferring', '${files.length} files → ${dst.endpointLabel}', ToastKind.info);
    }
  }

  // ── Settings (facade → SettingsController) ──
  String get themeName => _settings.themeName;
  Color get accent => _settings.accent;
  double get uiFontSize => _settings.uiFontSize;
  String get monospaceFont => _settings.monospaceFont;
  bool get showHiddenFiles => _settings.showHiddenFiles;
  bool get showPermsColumn => _settings.showPermsColumn;
  bool get showLogOnStartup => _settings.showLogOnStartup;
  bool get confirmOverwrite => _settings.confirmOverwrite;
  bool get hasSettingsStore => _settings.hasStore;
  AppSettings get currentSettings => _settings.current;

  void setThemeName(String v) => _settings.setThemeName(v);
  void setAccent(Color c) => _settings.setAccent(c);
  void setUiFontSize(double v) => _settings.setUiFontSize(v);
  void setMonospaceFont(String v) => _settings.setMonospaceFont(v);
  void setShowHiddenFiles(bool v) => _settings.setShowHiddenFiles(v);
  void setShowPermsColumn(bool v) => _settings.setShowPermsColumn(v);
  void setShowLogOnStartup(bool v) => _settings.setShowLogOnStartup(v);
  void setConfirmOverwrite(bool v) => _settings.setConfirmOverwrite(v);
  void resetSettings() => _settings.resetSettings();
  Future<void> saveWindowState({
    required double width,
    required double height,
    required double x,
    required double y,
  }) =>
      _settings.saveWindowState(width: width, height: height, x: x, y: y);

  // ── Transfer history (SQLite-backed) ──
  List<TransferRecord> history = const [];
  HistoryStats historyStats = const HistoryStats();
  bool get hasHistoryDb => _history != null;

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

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_safeNotify);
    _connections.removeListener(_safeNotify);
    _sessions.removeListener(_safeNotify);
    _transfers.removeListener(_safeNotify);
    _settings.dispose();
    _connections.dispose();
    _sessions.dispose();
    _transfers.dispose();
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

  /// Read [AppState] without subscribing to rebuilds — for action-only access
  /// from widgets that subscribe to a narrower controller scope instead.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }
}
