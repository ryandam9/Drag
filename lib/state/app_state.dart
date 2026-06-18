import 'dart:async';
import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../theme.dart';

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

/// Single source of truth for the demo app. Drives navigation, the file panes,
/// the live transfer queue and toast notifications.
class AppState extends ChangeNotifier {
  AppState() {
    _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
  }

  late final Timer _ticker;

  AppScreen screen = AppScreen.browser;

  final List<FileItem> local = List.of(localFiles);
  final List<FileItem> remote = List.of(remoteFiles);
  final List<Connection> connections = buildConnections();
  final List<Transfer> transfers = buildTransfers();
  final List<ToastMessage> toasts = [];

  String localPath = '/Users/marco/projects/backend';
  String remotePath = 'sftp://deploy@prod-server-01/var/www/app';

  int? selectedLocalIndex = 3; // config.yaml, matching the mockup
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

  void selectLocal(int index) {
    selectedLocalIndex = index;
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

  /// Active transfers currently counted against the parallel-thread budget.
  int get activeCount => transfers.where((t) => t.status == TransferStatus.active).length;
  int get queuedCount => transfers.where((t) => t.status == TransferStatus.queued).length;
  int get doneCount => transfers.where((t) => t.status == TransferStatus.done).length;
  int get errorCount => transfers.where((t) => t.status == TransferStatus.error).length;
  int get pausedCount => transfers.where((t) => t.status == TransferStatus.paused).length;

  /// Drag a local file onto the remote pane → enqueue an upload.
  void uploadFile(FileItem f) {
    if (f.isDir || f.isParent) {
      pushToast('Folder upload', '${f.name} — directory transfer queued', ToastKind.info);
    }
    transfers.insert(
      activeCount,
      Transfer(
        name: f.name,
        route: 'Local → $remotePath/',
        direction: TransferDirection.upload,
        sizeBytes: f.sizeBytes ?? 0,
        session: selectedConnection.name,
        status: TransferStatus.queued,
      ),
    );
    pushToast('Queued for upload', '${f.name} → ${selectedConnection.name}', ToastKind.info);
    notifyListeners();
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
    final msg = ToastMessage(_toastSeq++, title, sub, kind);
    toasts.add(msg);
    notifyListeners();
    Future.delayed(const Duration(seconds: 4), () {
      toasts.removeWhere((m) => m.id == msg.id);
      notifyListeners();
    });
  }

  /// Advances active transfers and promotes queued ones — gives the queue a
  /// living feel without any real network I/O.
  void _tick() {
    var changed = false;
    for (final t in transfers) {
      if (t.status == TransferStatus.active) {
        changed = true;
        // Larger files crawl, small files race — keeps it believable.
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

    // Promote queued → active while under the thread budget.
    if (activeCount < maxThreads) {
      final next = transfers.where((t) => t.status == TransferStatus.queued).cast<Transfer?>().firstWhere(
            (t) => true,
            orElse: () => null,
          );
      if (next != null) {
        next.status = TransferStatus.active;
        next.speed = next.sizeBytes > 10 * mB ? '1.4 MB/s' : '210 KB/s';
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _ticker.cancel();
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
