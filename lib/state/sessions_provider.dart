import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_store.dart';
import '../fs/sftp_backend.dart';
import '../fs/storage_backend.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import 'compare.dart';
import 'connection_log_provider.dart';
import 'connections_provider.dart';
import 'navigation_provider.dart';
import 'pane_controller.dart';
import 'providers.dart';
import 'session.dart';
import 'settings_provider.dart';
import 'toasts_provider.dart';
import 'transfers_provider.dart';

export 'session.dart' show Session;
export 'pane_controller.dart' show DragPayload;

/// The open browser tabs and which pane is focused. [rev] is bumped on every
/// in-place pane change (listing, selection, navigation) so watchers rebuild
/// even though [Session]/[PaneController] objects are reused.
class SessionsState {
  final List<Session> sessions;
  final int activeSessionId;
  final bool focusedLeft;
  final int rev;
  const SessionsState(this.sessions, this.activeSessionId, this.focusedLeft, this.rev);
}

/// Owns the session tabs (Local ⇄ remote dual-pane views), pane focus,
/// endpoint switching, file operations and backend caching. The open tabs and
/// their pane endpoints/paths are persisted to [SessionStore] and restored on
/// next launch.
class SessionsNotifier extends Notifier<SessionsState> {
  final LocalBackend _localBackend = LocalBackend();
  final Map<Connection, StorageBackend> _backendCache = {};

  int _seq = 0;
  bool _disposed = false;
  Timer? _saveTimer;
  String? _lastSaved;

  @override
  SessionsState build() {
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
    });

    // React to the "show hidden files" setting without rebuilding this notifier.
    ref.listen<bool>(settingsProvider.select((s) => s.showHiddenFiles),
        (_, show) => applyShowHidden(show));

    final showHidden = ref.read(settingsProvider).showHiddenFiles;
    final autoRefresh = ref.read(autoRefreshPanesProvider);
    final layout = ref.read(initialSessionLayoutProvider);
    final connById = {
      for (final c in ref.read(connectionsProvider).connections)
        if (c.id.isNotEmpty) c.id: c
    };

    final sessions = <Session>[];
    var activeIndex = 0;
    if (layout != null && layout.sessions.isNotEmpty) {
      for (final r in layout.sessions) {
        sessions.add(_buildSession(
          showHidden,
          leftConn: connById[r.leftConnId],
          leftPath: r.leftPath,
          rightConn: connById[r.rightConnId],
          rightPath: r.rightPath,
        ));
      }
      activeIndex = layout.activeIndex.clamp(0, sessions.length - 1);
    } else {
      sessions.add(_buildSession(showHidden));
    }

    if (autoRefresh) {
      Future.microtask(() {
        for (final s in sessions) {
          s.left.refresh();
          s.right.refresh();
        }
      });
    }
    return SessionsState(sessions, sessions[activeIndex].id, true, 0);
  }

  // ── Accessors ──
  Session get activeSession => state.sessions.firstWhere(
      (s) => s.id == state.activeSessionId,
      orElse: () => state.sessions.first);
  PaneController get leftPane => activeSession.left;
  PaneController get rightPane => activeSession.right;
  PaneController get focusedPane => state.focusedLeft ? leftPane : rightPane;

  // ── Backends ──
  StorageBackend backendFor(Connection? c) {
    if (c == null) return _localBackend;
    return _backendCache.putIfAbsent(c, () => c.isS3 ? S3Backend(c) : SftpBackend(c));
  }

  void evictBackend(Connection c) => _backendCache.remove(c);

  // ── State plumbing ──
  void _emit({List<Session>? sessions, int? activeSessionId, bool? focusedLeft}) {
    if (_disposed) return;
    state = SessionsState(
      sessions ?? state.sessions,
      activeSessionId ?? state.activeSessionId,
      focusedLeft ?? state.focusedLeft,
      state.rev + 1,
    );
  }

  /// Called by panes after any in-place change.
  void _onPaneChanged() {
    _emit();
    _scheduleSave();
  }

  Session _buildSession(
    bool showHidden, {
    Connection? leftConn,
    String? leftPath,
    Connection? rightConn,
    String? rightPath,
  }) {
    final left = PaneController(
        backend: backendFor(leftConn),
        connection: leftConn,
        onChanged: _onPaneChanged,
        showHidden: showHidden);
    if (leftPath != null && leftPath.isNotEmpty) left.path = leftPath;
    final right = PaneController(
        backend: backendFor(rightConn),
        connection: rightConn,
        onChanged: _onPaneChanged,
        showHidden: showHidden);
    if (rightPath != null && rightPath.isNotEmpty) right.path = rightPath;
    return Session(id: _seq++, left: left, right: right);
  }

  // ── Tabs ──
  Session openSession(Connection? remote) {
    if (remote != null) {
      for (final s in state.sessions) {
        if (identical(s.connection, remote)) {
          s.right.refresh();
          _emit(activeSessionId: s.id);
          _scheduleSave();
          return s;
        }
      }
    }
    final showHidden = ref.read(settingsProvider).showHiddenFiles;
    final s = _buildSession(showHidden, rightConn: remote);
    final sessions = [...state.sessions, s];
    if (ref.read(autoRefreshPanesProvider)) {
      s.left.refresh();
      s.right.refresh();
    }
    _emit(sessions: sessions, activeSessionId: s.id);
    _scheduleSave();
    return s;
  }

  void switchSession(int id) {
    if (state.sessions.any((s) => s.id == id) && id != state.activeSessionId) {
      _emit(activeSessionId: id);
      _scheduleSave();
    }
  }

  void closeSession(int id) {
    final idx = state.sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final sessions = [...state.sessions]..removeAt(idx);
    if (sessions.isEmpty) {
      final fresh = _buildSession(ref.read(settingsProvider).showHiddenFiles);
      sessions.add(fresh);
      if (ref.read(autoRefreshPanesProvider)) fresh.left.refresh();
      _emit(sessions: sessions, activeSessionId: fresh.id);
    } else {
      final active = state.activeSessionId == id
          ? sessions[idx.clamp(0, sessions.length - 1)].id
          : state.activeSessionId;
      _emit(sessions: sessions, activeSessionId: active);
    }
    _scheduleSave();
  }

  void focusPane(bool left) {
    if (state.focusedLeft != left) _emit(focusedLeft: left);
  }

  /// Point the active session's pane at Local (`null`) or a saved connection.
  Future<void> setPaneEndpoint(bool left, Connection? c) async {
    final pane = left ? leftPane : rightPane;
    await pane.switchTo(backendFor(c), c);
    _scheduleSave();
  }

  /// Connect to [c]: rebuild its backend with fresh credentials and open/focus
  /// a tab. S3 connections need credentials first.
  Future<void> connect(Connection c) async {
    c.online = c.isS3 ? c.hasS3Credentials : true;
    evictBackend(c); // pick up freshly entered credentials
    ref.read(connectionsProvider.notifier).touch();
    final toast = ref.read(toastsProvider.notifier);
    final log = ref.read(connectionLogProvider.notifier);
    if (c.isS3 && !c.hasS3Credentials) {
      toast.push('Missing credentials',
          'Enter Access Key, Secret & Bucket for ${c.name}', ToastKind.error);
      log.error('${c.name}: missing AWS credentials (set a profile or access key/secret)');
      return;
    }
    openSession(c);
    toast.push('Session connected', '${c.name} · ${c.protocol.label}', ToastKind.info);
    log.success('Opened session for "${c.name}" — ${_target(c)}');
    ref.read(navProvider.notifier).go(AppScreen.browser);
  }

  /// Handle a drag from one pane dropped onto another → start transfer(s).
  /// Transfers the source pane's whole selection (the dragged row is included).
  /// Folders are walked recursively; their tree is recreated on the destination.
  void dropTransfer(DragPayload payload, bool ontoLeft) {
    if (payload.fromLeft == ontoLeft) return; // dropped on its own pane
    final src = payload.fromLeft ? leftPane : rightPane;
    final dst = ontoLeft ? leftPane : rightPane;

    final selected = src.selectedItems();
    final candidates = selected.isNotEmpty ? selected : [payload.item];
    final entries = candidates.where((f) => !f.isParent).toList();

    final toasts = ref.read(toastsProvider.notifier);
    if (entries.isEmpty) return;
    if (!src.isReady || !dst.isReady) {
      toasts.push('Not connected', 'Connect the S3 endpoint (add credentials) first', ToastKind.error);
      return;
    }

    // Files transfer immediately; folders are walked recursively. Destination
    // name clashes are resolved by the transfers layer (Skip/Overwrite/Rename).
    ref.read(transfersProvider.notifier).transferSelection(src, dst, entries);
  }

  /// Actually verify a connection: open a fresh backend with the current
  /// credentials and perform a real listing (SFTP login + listdir, or S3
  /// ListObjects). Reports success or the real failure reason, and updates the
  /// connection's online flag accordingly. Does not open a tab.
  Future<void> testConnection(Connection c) async {
    final toasts = ref.read(toastsProvider.notifier);
    final log = ref.read(connectionLogProvider.notifier);
    if (c.isS3 && !c.hasS3Credentials) {
      toasts.push('Missing credentials', 'Enter Access Key, Secret & Bucket for ${c.name}', ToastKind.error);
      log.error('${c.name}: missing AWS credentials (set a profile or access key/secret)');
      return;
    }
    if (!c.isS3 && (c.host.isEmpty || c.username.isEmpty)) {
      toasts.push('Missing details', 'Enter a host and username for ${c.name}', ToastKind.error);
      log.error('${c.name}: missing host or username');
      return;
    }
    toasts.push('Testing connection…', 'Reaching ${c.name}', ToastKind.info);
    log.info('Testing "${c.name}" — ${_target(c)}');
    final backend = c.isS3 ? S3Backend(c) : SftpBackend(c);
    try {
      final items = await backend.list(backend.initialPath);
      c.online = true;
      ref.read(connectionsProvider.notifier).touch();
      toasts.push('Connection OK', '${c.name} is reachable', ToastKind.success);
      log.success('${c.name}: connected — listed ${items.length} '
          '${items.length == 1 ? 'entry' : 'entries'} at "${backend.initialPath}"');
    } catch (e) {
      c.online = false;
      ref.read(connectionsProvider.notifier).touch();
      toasts.push('Connection failed', _short(e), ToastKind.error);
      log.error('${c.name}: failed — ${_short(e)}');
    } finally {
      backend.dispose();
    }
  }

  /// A short human description of where a connection points, for the log.
  String _target(Connection c) {
    if (c.isS3) {
      final where = c.bucket.isNotEmpty ? 's3://${c.bucket}' : 'all buckets';
      final auth = c.useAwsProfile
          ? 'AWS profile "${c.awsProfile.isEmpty ? 'default' : c.awsProfile}"'
          : 'access key';
      return '$where · $auth';
    }
    final port = c.port == 0 ? 22 : c.port;
    final auth = c.auth == AuthMethod.privateKey ? 'key' : 'password';
    return 'sftp://${c.username}@${c.host}:$port · $auth';
  }

  // ── Compare & sync ──

  /// Compare the two panes' current listings and mark each entry (only-here /
  /// differs / same) so the UI can highlight the differences.
  PaneDiff compareActivePanes() {
    final l = leftPane, r = rightPane;
    final diff = comparePanes(l.items, r.items);
    l.compareMarks = diff.left;
    r.compareMarks = diff.right;
    _emit();
    final toasts = ref.read(toastsProvider.notifier);
    if (diff.isIdentical) {
      toasts.push('Panes match', 'No differences in the current folders', ToastKind.success);
    } else {
      toasts.push('Compared',
          '${diff.onlyLeft} only left · ${diff.differing} differ · ${diff.onlyRight} only right',
          ToastKind.info);
    }
    return diff;
  }

  /// Compute (but don't run) a mirror of one pane onto the other.
  MirrorPlan mirrorPlan({required bool leftToRight, required bool deleteExtras}) {
    final src = leftToRight ? leftPane : rightPane;
    final dst = leftToRight ? rightPane : leftPane;
    return planMirror(src.items, dst.items, leftToRight: leftToRight, deleteExtras: deleteExtras);
  }

  /// Run a previously-computed [plan]: copy the missing/different entries
  /// (recursively for folders, overwriting on the destination) and optionally
  /// delete the destination-only extras.
  Future<void> runMirror(MirrorPlan plan) async {
    final src = plan.leftToRight ? leftPane : rightPane;
    final dst = plan.leftToRight ? rightPane : leftPane;
    final toasts = ref.read(toastsProvider.notifier);
    if (!src.isReady || !dst.isReady) {
      toasts.push('Not connected', 'Connect both endpoints first', ToastKind.error);
      return;
    }
    final transfers = ref.read(transfersProvider.notifier);
    for (final item in plan.copy) {
      if (item.isDir) {
        transfers.enqueueTree(src, dst, item); // recursive, overwrites
      } else {
        transfers.enqueue(src, dst, item, announce: false);
      }
    }
    var deleted = 0;
    for (final d in plan.delete) {
      try {
        await dst.backend.delete(dst.backend.childPath(dst.path, d.name, d.isDir), isDir: d.isDir);
        deleted++;
      } catch (_) {/* best-effort */}
    }
    if (plan.delete.isNotEmpty) await dst.refresh();
    toasts.push('Mirroring',
        '${plan.copy.length} copied · $deleted deleted → ${dst.endpointLabel}', ToastKind.info);
  }

  /// Re-filter every pane after the "show hidden files" setting changes.
  void applyShowHidden(bool show) {
    for (final s in state.sessions) {
      s.left.setShowHidden(show);
      s.right.setShowHidden(show);
    }
  }

  // ── File operations ──
  void _toast(String title, String sub, ToastKind kind) =>
      ref.read(toastsProvider.notifier).push(title, sub, kind);

  Future<void> createFolder(PaneController pane, String name) async {
    if (name.trim().isEmpty) return;
    if (!pane.backend.supportsMutation) {
      _toast('Not supported', '${pane.endpointLabel} is read-only here', ToastKind.error);
      return;
    }
    try {
      await pane.backend.makeDir(pane.backend.childPath(pane.path, name.trim(), true));
      await pane.refresh();
      _toast('Folder created', name.trim(), ToastKind.success);
    } catch (e) {
      _toast('Couldn\'t create folder', _short(e), ToastKind.error);
    }
  }

  Future<void> renameItem(PaneController pane, FileItem item, String newName) async {
    if (item.isParent || newName.trim().isEmpty || newName.trim() == item.name) return;
    try {
      final from = pane.backend.childPath(pane.path, item.name, item.isDir);
      final to = pane.backend.childPath(pane.path, newName.trim(), item.isDir);
      await pane.backend.rename(from, to);
      await pane.refresh();
      _toast('Renamed', '${item.name} → ${newName.trim()}', ToastKind.success);
    } catch (e) {
      _toast('Couldn\'t rename', _short(e), ToastKind.error);
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
      _toast('Deleted', targets.length == 1 ? targets.first.name : '${targets.length} items',
          ToastKind.info);
    } else {
      _toast('Delete incomplete', '$failed of ${targets.length} failed', ToastKind.error);
    }
  }

  String _short(Object e) {
    final m = e.toString().replaceFirst('Exception: ', '');
    return m.length > 80 ? '${m.substring(0, 80)}…' : m;
  }

  // ── Persistence ──
  List<SessionRecord> _records() => [
        for (final s in state.sessions)
          SessionRecord(
            leftConnId: s.left.connection?.id,
            leftPath: s.left.path,
            rightConnId: s.right.connection?.id,
            rightPath: s.right.path,
          )
      ];

  int _activeIndex() {
    final i = state.sessions.indexWhere((s) => s.id == state.activeSessionId);
    return i < 0 ? 0 : i;
  }

  void _scheduleSave() {
    final store = ref.read(sessionStoreProvider);
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) return;
      final records = _records();
      final active = _activeIndex();
      final fingerprint =
          '${records.map((r) => '${r.leftConnId}|${r.leftPath}|${r.rightConnId}|${r.rightPath}').join(';')}#$active';
      if (fingerprint == _lastSaved) return;
      _lastSaved = fingerprint;
      store.replaceAll(records, activeIndex: active);
    });
  }
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, SessionsState>(SessionsNotifier.new);
