import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../fs/transfer_service.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import 'pane_controller.dart';
import 'toast.dart';

/// Owns the transfer queue: the list, the parallel-thread budget, the simulated
/// ticker and the live [TransferService] runs. High-frequency progress updates
/// stay on each [Transfer]'s own `liveTick`; only status transitions notify
/// here. Completion is surfaced via [onToast] / [onRecord].
class TransfersController extends ChangeNotifier {
  TransfersController({
    bool tickEnabled = true,
    this.onToast,
    this.onRecord,
  }) {
    if (tickEnabled) {
      _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
    }
  }

  final ToastSink? onToast;

  /// Persist a finished transfer to history (best-effort).
  final void Function(Transfer t)? onRecord;

  final List<Transfer> transfers = buildTransfers();
  final TransferService _service = TransferService();
  Timer? _ticker;
  int maxThreads = 5;
  bool _disposed = false;

  int get activeCount => transfers.where((t) => t.status == TransferStatus.active).length;
  int get queuedCount => transfers.where((t) => t.status == TransferStatus.queued).length;
  int get doneCount => transfers.where((t) => t.status == TransferStatus.done).length;
  int get errorCount => transfers.where((t) => t.status == TransferStatus.error).length;
  int get pausedCount => transfers.where((t) => t.status == TransferStatus.paused).length;

  void setMaxThreads(int v) {
    maxThreads = v.clamp(1, 16);
    _notify();
  }

  /// Queue (and, for real backends, start) a transfer of [item] from [src] to
  /// [dst]. [announce] controls the per-file "started/queued" toast.
  void enqueue(PaneController src, PaneController dst, FileItem item, {bool announce = true}) {
    final srcPath = src.backend.childPath(src.path, item.name, false);
    final dstPath = dst.backend.childPath(dst.path, item.name, false);
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
    _notify();

    if (simulated) {
      if (announce) onToast?.call('Queued', '${item.name} → ${dst.endpointLabel}', ToastKind.info);
      return;
    }

    if (announce) {
      onToast?.call('Transfer started', '${item.name} → ${dst.endpointLabel}', ToastKind.info);
    }
    _service
        .run(
      t: t,
      src: src.backend,
      srcPath: srcPath,
      dst: dst.backend,
      dstPath: dstPath,
      onStatus: _notify,
      onProgress: t.touchLive, // progress repaints only the progress widgets
    )
        .then((_) {
      if (_disposed) return;
      onRecord?.call(t);
      if (t.status == TransferStatus.done) {
        _completionToast(t);
        dst.refresh();
      } else if (t.status == TransferStatus.error) {
        onToast?.call('Transfer failed', '${item.name}: ${t.errorMessage ?? 'error'}', ToastKind.error);
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
    _notify();
  }

  void resumeAll() {
    for (final t in transfers) {
      if (t.status == TransferStatus.paused) t.status = TransferStatus.queued;
    }
    _notify();
  }

  void clearDone() {
    transfers.removeWhere((t) => t.status == TransferStatus.done);
    _notify();
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
    _notify();
  }

  void retry(Transfer t) {
    t.status = TransferStatus.queued;
    t.errorMessage = null;
    t.progress = 0;
    _notify();
  }

  /// Rich "transfer completed" notification: destination path, size, time.
  void _completionToast(Transfer t) {
    final dest = t.destPath.isNotEmpty ? t.destPath : '${t.session} · ${t.name}';
    onToast?.call(
      'File transfer completed',
      dest,
      ToastKind.success,
      detail: '${formatBytes(t.sizeBytes)} · ${t.elapsedLabel}'
          '${t.speed != '—' ? ' · ${t.speed}' : ''}',
    );
  }

  /// Advances *simulated* transfers only (real ones are driven by
  /// [TransferService]). Progress-only steps ping each transfer's liveTick;
  /// status transitions hit this controller's notifier.
  void _tick() {
    var statusChanged = false;
    for (final t in transfers) {
      if (t.live) continue;
      if (t.status == TransferStatus.active) {
        t.startedAt ??= DateTime.now();
        final step = t.sizeBytes > 10 * mB ? 0.015 : 0.18;
        t.progress = (t.progress + step).clamp(0, 1);
        if (t.progress >= 1) {
          t.status = TransferStatus.done;
          t.eta = 'Done';
          t.speed = t.speed == '—' ? '1.0 MB/s' : t.speed;
          t.finishedAt = DateTime.now();
          _completionToast(t);
          onRecord?.call(t);
          statusChanged = true;
        } else {
          final remaining = ((1 - t.progress) * (t.sizeBytes > 10 * mB ? 90 : 4)).round();
          t.eta = '0:${remaining.toString().padLeft(2, '0')}';
          t.touchLive();
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
          statusChanged = true;
          break;
        }
      }
    }

    if (statusChanged) _notify();
  }

  /// Advances the simulated transfer ticker once (exposed for deterministic
  /// tests, via `AppState.debugTick`).
  void debugTick() => _tick();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final t in transfers) {
      t.dispose();
    }
    super.dispose();
  }
}
