import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fs/transfer_service.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import 'history_provider.dart';
import 'pane_controller.dart';
import 'toasts_provider.dart';

/// The transfer queue plus the parallel-thread budget.
class TransfersState {
  final List<Transfer> transfers;
  final int maxThreads;
  const TransfersState({this.transfers = const [], this.maxThreads = 5});

  int countOf(TransferStatus s) => transfers.where((t) => t.status == s).length;
  int get activeCount => countOf(TransferStatus.active);
  int get queuedCount => countOf(TransferStatus.queued);
  int get doneCount => countOf(TransferStatus.done);
  int get errorCount => countOf(TransferStatus.error);
  int get pausedCount => countOf(TransferStatus.paused);
}

/// Owns the transfer queue. The queue starts empty and only ever holds real
/// transfers driven by [TransferService]; high-frequency progress updates stay
/// on each [Transfer]'s own `liveTick`, while status transitions emit new
/// state here. Completion is surfaced via toasts and persisted to history.
class TransfersNotifier extends Notifier<TransfersState> {
  final TransferService _service = TransferService();
  bool _disposed = false;

  /// Mirror of the current transfers, kept in a plain field so [onDispose] can
  /// release each transfer's `liveTick` without touching `state` — Riverpod 3
  /// forbids reading providers/state inside lifecycle callbacks.
  List<Transfer> _current = const [];

  @override
  TransfersState build() {
    ref.onDispose(() {
      _disposed = true;
      for (final t in _current) {
        t.dispose();
      }
    });
    return const TransfersState();
  }

  List<Transfer> get _list => state.transfers;

  void _emit(List<Transfer> transfers, {int? maxThreads}) {
    if (_disposed) return;
    _current = transfers;
    state = TransfersState(transfers: transfers, maxThreads: maxThreads ?? state.maxThreads);
  }

  void _toast(String title, String sub, ToastKind kind, {String? detail}) =>
      ref.read(toastsProvider.notifier).push(title, sub, kind, detail: detail);

  void setMaxThreads(int v) => _emit(_list, maxThreads: v.clamp(1, 16));

  /// Seed the queue with prebuilt transfers (tests only — production transfers
  /// are created exclusively via [enqueue]).
  @visibleForTesting
  void debugSetTransfers(List<Transfer> transfers) => _emit(List.of(transfers));

  /// Queue and start a real transfer of [item] from [src] to [dst].
  /// [announce] controls the per-file "started" toast.
  void enqueue(PaneController src, PaneController dst, FileItem item, {bool announce = true}) {
    if (!src.backend.supportsTransfer || !dst.backend.supportsTransfer) {
      _toast('Not supported',
          '${src.endpointLabel} → ${dst.endpointLabel} transfers are not available', ToastKind.error);
      return;
    }
    final srcPath = src.backend.childPath(src.path, item.name, false);
    final dstPath = dst.backend.childPath(dst.path, item.name, false);
    final direction =
        dst.kind == EndpointKind.local ? TransferDirection.download : TransferDirection.upload;

    final t = Transfer(
      name: item.name,
      route: '${src.endpointLabel} → ${dst.displayPath}',
      direction: direction,
      sizeBytes: item.sizeBytes ?? 0,
      session: dst.endpointLabel,
      status: TransferStatus.queued,
      live: true,
      sourcePath: '${src.endpointLabel}:$srcPath',
      destPath: dst.displayPath,
    );
    _emit([t, ..._list]);

    if (announce) {
      _toast('Transfer started', '${item.name} → ${dst.endpointLabel}', ToastKind.info);
    }
    _service
        .run(
      t: t,
      src: src.backend,
      srcPath: srcPath,
      dst: dst.backend,
      dstPath: dstPath,
      onStatus: () => _emit(_list),
      onProgress: t.touchLive, // progress repaints only the progress widgets
    )
        .then((_) {
      if (_disposed) return;
      ref.read(historyProvider.notifier).record(t);
      if (t.status == TransferStatus.done) {
        _completionToast(t);
        dst.refresh();
      } else if (t.status == TransferStatus.error) {
        _toast('Transfer failed', '${item.name}: ${t.errorMessage ?? 'error'}', ToastKind.error);
      }
    });
  }

  void pauseAll() {
    for (final t in _list) {
      if (t.status == TransferStatus.active || t.status == TransferStatus.queued) {
        t.status = TransferStatus.paused;
        t.speed = '—';
        t.eta = '—';
      }
    }
    _emit(_list);
  }

  void resumeAll() {
    for (final t in _list) {
      if (t.status == TransferStatus.paused) t.status = TransferStatus.queued;
    }
    _emit(_list);
  }

  void clearDone() => _emit(_list.where((t) => t.status != TransferStatus.done).toList());

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
    _emit(_list);
  }

  void retry(Transfer t) {
    t.status = TransferStatus.queued;
    t.errorMessage = null;
    t.progress = 0;
    _emit(_list);
  }

  /// Rich "transfer completed" notification: destination path, size, time.
  void _completionToast(Transfer t) {
    final dest = t.destPath.isNotEmpty ? t.destPath : '${t.session} · ${t.name}';
    _toast(
      'File transfer completed',
      dest,
      ToastKind.success,
      detail: '${formatBytes(t.sizeBytes)} · ${t.elapsedLabel}'
          '${t.speed != '—' ? ' · ${t.speed}' : ''}',
    );
  }
}

final transfersProvider =
    NotifierProvider<TransfersNotifier, TransfersState>(TransfersNotifier.new);
