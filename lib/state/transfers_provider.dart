import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../fs/storage_backend.dart';
import '../fs/transfer_service.dart';
import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import 'history_provider.dart';
import 'pane_controller.dart';
import 'settings_provider.dart';
import 'toasts_provider.dart';

/// What to do when a transfer's destination already has a file of that name.
enum ConflictAction { skip, overwrite, rename }

/// A request for the user to resolve one name clash.
class ConflictPrompt {
  final String name;
  final String destLabel;
  const ConflictPrompt({required this.name, required this.destLabel});
}

/// The user's answer to a [ConflictPrompt]; [applyToAll] reuses it for the rest
/// of the current drop.
class ConflictResolution {
  final ConflictAction action;
  final bool applyToAll;
  const ConflictResolution(this.action, {this.applyToAll = false});
}

/// Shows a conflict prompt and returns the choice (null = cancel → skip).
typedef ConflictResolver = Future<ConflictResolution?> Function(ConflictPrompt prompt);

/// Per-drop memory of an "apply to all" choice.
class _Batch {
  ConflictAction? applyToAll;
}


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
      _runners.clear();
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
    final srcPath = src.backend.childPath(src.path, item.name, false);
    final dstPath = dst.backend.childPath(dst.path, item.name, false);
    enqueueFile(src, dst, srcPath, dstPath, item.name, item.sizeBytes ?? 0, announce: announce);
  }

  /// Queue and start a transfer of a single file given its full [srcPath] /
  /// [dstPath] on each backend. Used directly by recursive folder transfers,
  /// where the paths include sub-directories under the dragged folder.
  void enqueueFile(PaneController src, PaneController dst, String srcPath, String dstPath,
      String name, int sizeBytes, {bool announce = true}) {
    if (!src.backend.supportsTransfer || !dst.backend.supportsTransfer) {
      _toast('Not supported',
          '${src.endpointLabel} → ${dst.endpointLabel} transfers are not available', ToastKind.error);
      return;
    }
    final direction =
        dst.kind == EndpointKind.local ? TransferDirection.download : TransferDirection.upload;

    final t = Transfer(
      name: name,
      route: '${src.endpointLabel} → ${dst.displayPath}',
      direction: direction,
      sizeBytes: sizeBytes,
      session: dst.endpointLabel,
      status: TransferStatus.queued,
      live: true,
      sourcePath: '${src.endpointLabel}:$srcPath',
      destPath: dst.backend.displayPath(dstPath),
    );
    _emit([t, ..._list]);

    if (announce) {
      _toast('Transfer started', '$name → ${dst.endpointLabel}', ToastKind.info);
    }

    // Remember how to (re)run this transfer so manual/auto retry can replay it.
    void start() => _runOnce(t, src, srcPath, dst, dstPath);
    _runners[t] = start;
    start();
  }

  /// Total attempts before a live transfer gives up and stays failed.
  static const maxAttempts = 3;

  /// How to re-run each live transfer (keyed by the transfer instance).
  final Map<Transfer, void Function()> _runners = {};

  /// Backoff before an automatic retry (exponential: 2s, 4s). Overridable in
  /// tests so they don't have to wait real seconds.
  @visibleForTesting
  Duration Function(int attempts) backoffFor = (attempts) => Duration(seconds: 1 << attempts);

  /// Run [t] once; on failure schedule an automatic retry with backoff until
  /// [maxAttempts] is reached, then settle as Error.
  void _runOnce(Transfer t, PaneController src, String srcPath, PaneController dst, String dstPath) {
    t.attempts++;
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
      if (t.status == TransferStatus.done) {
        ref.read(historyProvider.notifier).record(t);
        _completionToast(t);
        dst.refresh();
      } else if (t.status == TransferStatus.error) {
        if (t.attempts < maxAttempts) {
          // Transient — back off (2s, 4s) and try again automatically.
          final delay = backoffFor(t.attempts);
          t.status = TransferStatus.queued;
          t.progress = 0;
          _emit(_list);
          Timer(delay, () {
            if (_disposed || t.status != TransferStatus.queued) return;
            _runOnce(t, src, srcPath, dst, dstPath);
          });
        } else {
          ref.read(historyProvider.notifier).record(t);
          _toast('Transfer failed', '${t.name}: ${t.errorMessage ?? 'error'}', ToastKind.error);
        }
      }
    });
  }

  /// Import OS file-system paths (e.g. dropped from the native file manager)
  /// into [dst] at its current path. Files upload directly; folders recurse.
  void importFiles(PaneController dst, List<String> osPaths) {
    if (!dst.isReady) {
      _toast('Not connected', 'Connect ${dst.endpointLabel} before dropping files', ToastKind.error);
      return;
    }
    if (!dst.backend.supportsMutation) {
      _toast('Read-only', "Can't write to ${dst.endpointLabel} here", ToastKind.error);
      return;
    }
    for (final osPath in osPaths) {
      final name = p.basename(osPath);
      // A throwaway Local source pane rooted at the dropped item's parent.
      final src = PaneController(backend: LocalBackend(), onChanged: () {})..path = p.dirname(osPath);
      if (FileSystemEntity.isDirectorySync(osPath)) {
        enqueueTree(src, dst, FileItem(name: name, isDir: true));
      } else {
        var size = 0;
        try {
          size = File(osPath).lengthSync();
        } catch (_) {/* unknown size */}
        final dstPath = dst.backend.childPath(dst.path, name, false);
        enqueueFile(src, dst, osPath, dstPath, name, size, announce: osPaths.length == 1);
      }
    }
    if (osPaths.length > 1) {
      _toast('Importing', '${osPaths.length} items → ${dst.endpointLabel}', ToastKind.info);
    }
  }

  /// Recursively transfer a [folder] from [src] to [dst]: recreate the
  /// directory tree on the destination and enqueue every nested file. Returns
  /// the number of files enqueued. Listing/mkdir errors on one subtree are
  /// reported but don't abort the rest.
  Future<int> enqueueTree(PaneController src, PaneController dst, FileItem folder) =>
      _transferFolder(src, dst, folder, _Batch(), false);

  // ── Conflict resolution ──

  /// The UI registers a resolver (a dialog) here; null = no prompting.
  ConflictResolver? _resolver;
  void setConflictResolver(ConflictResolver? r) => _resolver = r;

  /// Transfer a dropped selection of [entries] (files and/or folders) from
  /// [src] to [dst], resolving destination name clashes when "confirm before
  /// overwriting" is on and a resolver is registered. Folders are walked
  /// recursively; one "apply to all" decision spans the whole drop.
  Future<void> transferSelection(
      PaneController src, PaneController dst, List<FileItem> entries) async {
    final files = entries.where((e) => !e.isDir).toList();
    final folders = entries.where((e) => e.isDir).toList();
    final confirm = ref.read(settingsProvider).confirmOverwrite && _resolver != null;
    final batch = _Batch();
    final single = entries.length == 1 && folders.isEmpty;

    final topNames = confirm ? await _namesAt(dst.backend, dst.path) : <String>{};
    for (final f in files) {
      await _maybeEnqueue(
          src, dst, src.path, dst.path, f.name, f.sizeBytes ?? 0, topNames, batch, confirm,
          announce: single);
    }
    if (files.length > 1 && folders.isEmpty) {
      _toast('Transferring', '${files.length} files → ${dst.endpointLabel}', ToastKind.info);
    }
    for (final folder in folders) {
      await _transferFolder(src, dst, folder, batch, confirm);
    }
  }

  Future<int> _transferFolder(
      PaneController src, PaneController dst, FileItem folder, _Batch batch, bool confirm) async {
    if (!dst.backend.supportsMutation) {
      _toast('Not supported', "Can't create folders on ${dst.endpointLabel}", ToastKind.error);
      return 0;
    }
    final srcRoot = src.backend.childPath(src.path, folder.name, true);
    final dstRoot = dst.backend.childPath(dst.path, folder.name, true);
    _toast('Expanding folder', '${folder.name} → ${dst.endpointLabel}', ToastKind.info);
    var count = 0;
    try {
      await dst.backend.makeDir(dstRoot);
      count = await _walk(src, dst, srcRoot, dstRoot, batch, confirm);
    } catch (e) {
      _toast("Couldn't read folder", _short(e), ToastKind.error);
    }
    _toast(count == 0 ? 'Nothing to transfer' : 'Folder queued',
        count == 0 ? '${folder.name} has no new files' : '$count ${count == 1 ? 'file' : 'files'} from ${folder.name}',
        ToastKind.info);
    return count;
  }

  Future<int> _walk(PaneController src, PaneController dst, String srcDir, String dstDir,
      _Batch batch, bool confirm) async {
    final items = await src.backend.list(srcDir);
    final destNames = confirm ? await _namesAt(dst.backend, dstDir) : <String>{};
    var count = 0;
    for (final it in items) {
      if (it.isParent) continue;
      if (it.isDir) {
        final d = dst.backend.childPath(dstDir, it.name, true);
        try {
          await dst.backend.makeDir(d);
          count += await _walk(
              src, dst, src.backend.childPath(srcDir, it.name, true), d, batch, confirm);
        } catch (e) {
          _toast("Couldn't copy folder", '${it.name}: ${_short(e)}', ToastKind.error);
        }
      } else {
        if (await _maybeEnqueue(
            src, dst, srcDir, dstDir, it.name, it.sizeBytes ?? 0, destNames, batch, confirm)) {
          count++;
        }
      }
    }
    return count;
  }

  /// Enqueue one file, first resolving a name clash if the destination already
  /// has [name]. Returns true if a transfer was enqueued (false = skipped).
  Future<bool> _maybeEnqueue(PaneController src, PaneController dst, String srcDir, String dstDir,
      String name, int size, Set<String> destNames, _Batch batch, bool confirm,
      {bool announce = false}) async {
    var outName = name;
    if (confirm && destNames.contains(name)) {
      final action = batch.applyToAll ?? await _ask(name, dst, batch);
      switch (action) {
        case ConflictAction.skip:
          return false;
        case ConflictAction.overwrite:
          break;
        case ConflictAction.rename:
          outName = _uniqueName(name, destNames);
      }
    }
    destNames.add(outName); // so later renames in the same dir don't collide
    final s = src.backend.childPath(srcDir, name, false);
    final d = dst.backend.childPath(dstDir, outName, false);
    enqueueFile(src, dst, s, d, outName, size, announce: announce);
    return true;
  }

  Future<ConflictAction> _ask(String name, PaneController dst, _Batch batch) async {
    final res = await _resolver!(ConflictPrompt(name: name, destLabel: dst.endpointLabel));
    if (res == null) return ConflictAction.skip;
    if (res.applyToAll) batch.applyToAll = res.action;
    return res.action;
  }

  Future<Set<String>> _namesAt(StorageBackend backend, String dir) async {
    try {
      final items = await backend.list(dir);
      return {for (final it in items) if (!it.isParent) it.name};
    } catch (_) {
      return <String>{};
    }
  }

  String _uniqueName(String name, Set<String> existing) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var n = 1;
    String candidate;
    do {
      candidate = '$base ($n)$ext';
      n++;
    } while (existing.contains(candidate));
    return candidate;
  }

  String _short(Object e) {
    final m = e.toString().replaceFirst('Exception: ', '');
    return m.length > 80 ? '${m.substring(0, 80)}…' : m;
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

  void clearDone() {
    final kept = _list.where((t) => t.status != TransferStatus.done).toList();
    _runners.removeWhere((t, _) => t.status == TransferStatus.done);
    _emit(kept);
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
    _emit(_list);
  }

  /// Re-run a failed transfer from scratch (resets the attempt counter). A
  /// transfer with no stored runner (e.g. seeded in tests) just resets to queued.
  void retry(Transfer t) {
    t.errorMessage = null;
    t.progress = 0;
    t.attempts = 0;
    t.status = TransferStatus.queued;
    _emit(_list);
    _runners[t]?.call();
  }

  /// Retry every currently-failed transfer.
  void retryAllFailed() {
    final failed = _list.where((t) => t.status == TransferStatus.error).toList();
    for (final t in failed) {
      retry(t);
    }
    if (failed.isNotEmpty) {
      _toast('Retrying', '${failed.length} failed ${failed.length == 1 ? 'transfer' : 'transfers'}', ToastKind.info);
    }
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
