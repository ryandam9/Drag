import 'dart:async';
import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../fs/simulated_backend.dart';
import '../fs/storage_backend.dart';
import '../fs/transfer_service.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../theme.dart';
import 'pane_controller.dart';

export 'pane_controller.dart' show DragPayload;

enum AppScreen { browser, connections, queue, settings }

class ToastMessage {
  final String title;
  final String subtitle;
  final ToastKind kind;
  final int id;
  ToastMessage(this.id, this.title, this.subtitle, this.kind);
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
  AppState({bool tickEnabled = true, bool autoRefreshPanes = true}) {
    leftPane = PaneController(backend: _localBackend, onChanged: notifyListeners);
    // Right pane defaults to the first S3 account to surface the new feature.
    final firstS3 = connections.firstWhere((c) => c.isS3, orElse: () => connections.first);
    rightPane = PaneController(
      backend: _backendFor(firstS3),
      connection: firstS3,
      onChanged: notifyListeners,
    );
    if (tickEnabled) {
      _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
    }
    if (autoRefreshPanes) {
      leftPane.refresh();
      rightPane.refresh();
    }
  }

  Timer? _ticker;
  bool _disposed = false;
  final TransferService _transfers = TransferService();
  final LocalBackend _localBackend = LocalBackend();
  final Map<Connection, StorageBackend> _backendCache = {};

  AppScreen screen = AppScreen.browser;

  final List<Connection> connections = buildConnections();
  final List<Transfer> transfers = buildTransfers();
  final List<ToastMessage> toasts = [];

  late final PaneController leftPane;
  late final PaneController rightPane;

  Connection selectedConnection = buildConnections().first;

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

  // ── Endpoints / backends ──────────────────────────────────────────────

  /// Builds (and caches) the backend for a connection. `null` → Local.
  StorageBackend _backendFor(Connection? c) {
    if (c == null) return _localBackend;
    return _backendCache.putIfAbsent(
        c, () => c.isS3 ? S3Backend(c) : SimulatedBackend(c));
  }

  /// Point a pane at Local (`connection == null`) or a saved connection.
  Future<void> setPaneEndpoint(bool left, Connection? c) async {
    final pane = left ? leftPane : rightPane;
    await pane.switchTo(_backendFor(c), c);
  }

  /// Re-create the backend for [c] (picks up freshly entered S3 credentials)
  /// and refresh any pane currently using it.
  Future<void> connect(Connection c) async {
    c.online = c.isS3 ? c.hasS3Credentials : true;
    _backendCache.remove(c);
    final backend = _backendFor(c);
    for (final pane in [leftPane, rightPane]) {
      if (identical(pane.connection, c)) {
        await pane.switchTo(backend, c);
      }
    }
    if (c.isS3 && !c.hasS3Credentials) {
      pushToast('Missing credentials', 'Enter Access Key, Secret & Bucket for ${c.name}', ToastKind.error);
    } else {
      pushToast('Session connected', '${c.name} · ${c.protocol.label}', ToastKind.info);
    }
    notifyListeners();
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
    final simulated = src.kind == EndpointKind.sftp || dst.kind == EndpointKind.sftp;
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
      if (t.status == TransferStatus.done) {
        pushToast('Transfer complete', '${item.name} → ${dst.endpointLabel} (${formatBytes(t.sizeBytes)})',
            ToastKind.success);
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

  void pushToast(String title, String sub, ToastKind kind) {
    if (_disposed) return;
    final msg = ToastMessage(_toastSeq++, title, sub, kind);
    toasts.add(msg);
    notifyListeners();
    Future.delayed(const Duration(seconds: 4), () {
      toasts.removeWhere((m) => m.id == msg.id);
      _safeNotify();
    });
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
        final step = t.sizeBytes > 10 * mB ? 0.015 : 0.18;
        t.progress = (t.progress + step).clamp(0, 1);
        if (t.progress >= 1) {
          t.status = TransferStatus.done;
          t.eta = 'Done';
          t.speed = t.speed == '—' ? '1.0 MB/s' : t.speed;
          pushToast(
            t.direction == TransferDirection.upload ? 'Upload complete' : 'Download complete',
            '${t.name} → ${t.session} (${formatBytes(t.sizeBytes)})',
            ToastKind.success,
          );
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
