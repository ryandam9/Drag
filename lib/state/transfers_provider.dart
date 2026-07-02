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
import '../platform/desktop_notifications.dart';
import 'history_provider.dart';
import 'navigation_provider.dart';
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
typedef ConflictResolver =
    Future<ConflictResolution?> Function(ConflictPrompt prompt);

/// Per-drop memory of an "apply to all" choice.
class _Batch {
  ConflictAction? applyToAll;
}

/// The transfer queue plus the parallel-thread budget. Per-status counts are
/// tallied once at construction, so hot readers (nav badge, queue toolbar)
/// don't rescan the whole list on every access.
class TransfersState {
  final List<Transfer> transfers;
  final int maxThreads;
  final List<int> _counts; // indexed by TransferStatus.index

  TransfersState({this.transfers = const [], this.maxThreads = 5})
    : _counts = _countByStatus(transfers);

  static List<int> _countByStatus(List<Transfer> transfers) {
    final counts = List<int>.filled(TransferStatus.values.length, 0);
    for (final t in transfers) {
      counts[t.status.index]++;
    }
    return counts;
  }

  int countOf(TransferStatus s) => _counts[s.index];
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
    // Apply the speed cap live: changing the setting updates the shared limiter
    // immediately, so transfers that are already active respect the new cap
    // without waiting for the next one to start.
    ref.listen(settingsProvider.select((s) => s.transferLimitKbps), (_, kbps) {
      _service.limiter.bytesPerSecond = kbps <= 0 ? null : kbps * 1024;
    }, fireImmediately: true);
    ref.onDispose(() {
      _disposed = true;
      // Abort every in-flight run first; each settles asynchronously and
      // disposes its own transfer's liveTick via the _cancelled path in
      // _runOnce. Disposing those notifiers here, while their streams are
      // still unwinding, would be a use-after-dispose.
      final inFlight = Set<Transfer>.of(_controls.keys);
      for (final control in _controls.values) {
        control.abort();
      }
      _cancelled.addAll(inFlight);
      _runners.clear();
      _deferred.clear();
      _partialCleanups.clear();
      for (final t in _current) {
        if (!inFlight.contains(t)) t.dispose();
      }
      // Transfers parked in a folder-walk batch were never published (nor
      // started), so they aren't in _current — release them too.
      for (final t in _batch ?? const <Transfer>[]) {
        t.dispose();
      }
    });
    return TransfersState();
  }

  /// The shared limiter's current cap in bytes/sec (null = unlimited). Exposed
  /// for tests asserting the live speed-limit update.
  @visibleForTesting
  int? get currentRateCap => _service.limiter.bytesPerSecond;

  List<Transfer> get _list => state.transfers;

  void _emit(List<Transfer> transfers, {int? maxThreads}) {
    if (_disposed) return;
    _current = transfers;
    state = TransfersState(
      transfers: transfers,
      maxThreads: maxThreads ?? state.maxThreads,
    );
  }

  void _toast(String title, String sub, ToastKind kind, {String? detail}) =>
      ref.read(toastsProvider.notifier).push(title, sub, kind, detail: detail);

  void setMaxThreads(int v) {
    _emit(_list, maxThreads: v.clamp(1, 16));
    _pump(); // a higher limit may let more queued transfers start
  }

  /// Seed the queue with prebuilt transfers (tests only — production transfers
  /// are created exclusively via [enqueue]).
  @visibleForTesting
  void debugSetTransfers(List<Transfer> transfers) => _emit(List.of(transfers));

  /// Queue and start a real transfer of [item] from [src] to [dst].
  /// [announce] controls the per-file "started" toast.
  void enqueue(
    PaneController src,
    PaneController dst,
    FileItem item, {
    bool announce = true,
  }) {
    final srcPath = src.backend.childPath(src.path, item.name, false);
    final dstPath = dst.backend.childPath(dst.path, item.name, false);
    enqueueFile(
      src,
      dst,
      srcPath,
      dstPath,
      item.name,
      item.sizeBytes ?? 0,
      announce: announce,
    );
  }

  /// Queue and start a transfer of a single file given its full [srcPath] /
  /// [dstPath] on each backend. Used directly by recursive folder transfers,
  /// where the paths include sub-directories under the dragged folder.
  void enqueueFile(
    PaneController src,
    PaneController dst,
    String srcPath,
    String dstPath,
    String name,
    int sizeBytes, {
    bool announce = true,
  }) {
    if (!src.backend.supportsTransfer || !dst.backend.supportsTransfer) {
      _toast(
        'Not supported',
        '${src.endpointLabel} → ${dst.endpointLabel} transfers are not available',
        ToastKind.error,
      );
      return;
    }
    final direction = dst.kind == EndpointKind.local
        ? TransferDirection.download
        : TransferDirection.upload;

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
    // During a folder walk new transfers are parked in the batch and published
    // as one emission per slice (see _flushBatch), so queuing thousands of
    // files doesn't copy + emit the whole list once per file.
    final batch = _batch;
    if (batch != null) {
      batch.add(t);
    } else {
      _emit([t, ..._list]);
    }

    if (announce) {
      _toast(
        'Transfer started',
        '$name → ${dst.endpointLabel}',
        ToastKind.info,
      );
    }

    // Remember how to (re)run this transfer so the scheduler and manual/auto
    // retry can replay it; the limiter starts it when a slot is free.
    _runners[t] = () => _runOnce(t, src, srcPath, dst, dstPath);
    // How to discard the staging partial a pause keeps for resume, should the
    // transfer later be cancelled while paused (no run in flight to clean up).
    _partialCleanups[t] = () =>
        _service.discardPartial(dst.backend, dstPath, t);
    _pump();
  }

  // ── Folder-scan progress / cancellation (#41) ──
  // A recursive folder drop can enqueue thousands of files; walk it
  // progressively (yielding to the event loop and reporting progress) and let
  // the user stop the scan before everything is queued.
  bool _scanning = false;
  bool _scanCancelled = false;
  int _scanned = 0;

  /// Whether a recursive folder enqueue is currently walking the tree.
  bool get isScanning => _scanning;

  /// Stop an in-progress folder scan; files already queued are kept.
  void cancelFolderScan() => _scanCancelled = true;

  /// Total attempts before a live transfer gives up and stays failed.
  static const maxAttempts = 3;

  /// How to re-run each live transfer (keyed by the transfer instance).
  final Map<Transfer, void Function()> _runners = {};

  /// The abort handle for each transfer's in-flight run (present only while
  /// active). Pause/cancel abort through this to stop the byte stream.
  final Map<Transfer, TransferControl> _controls = {};

  /// How to discard the staging partial each transfer's pause may have kept,
  /// keyed like [_runners]. Invoked by [cancel] on a paused transfer, since no
  /// run is in flight then to clean up after itself.
  final Map<Transfer, Future<void> Function()> _partialCleanups = {};

  /// While non-null (during a folder walk), [enqueueFile] parks new transfers
  /// here instead of emitting a fresh state per file; [_flushBatch] publishes
  /// the accumulated slice in a single emission.
  List<Transfer>? _batch;

  /// Publish the batched transfers (newest-first, matching [enqueueFile]'s
  /// per-file ordering) in one state emission, then let the scheduler start
  /// them.
  void _flushBatch() {
    final batch = _batch;
    if (batch == null || batch.isEmpty) return;
    _emit([...batch.reversed, ..._list]);
    batch.clear();
    _pump();
  }

  /// Queued transfers waiting out a retry backoff — excluded from [_pump] until
  /// their timer fires, so the concurrency limiter doesn't restart them early.
  final Set<Transfer> _deferred = {};

  /// Transfers cancelled while a run was still in flight. Their `liveTick` is
  /// disposed only once the run settles (see [_runOnce]), since the unwinding
  /// stream can still touch it — disposing immediately risks a "used after
  /// dispose" error.
  final Set<Transfer> _cancelled = {};

  /// Starts queued transfers (oldest first) until [TransfersState.maxThreads]
  /// are active. Called whenever a slot might free up (enqueue, completion,
  /// pause/cancel, resume, retry, thread-count change). Transfers with no
  /// runner (e.g. seeded in tests) or still in retry backoff are skipped.
  void _pump() {
    if (_disposed) return;
    final limit = state.maxThreads;
    final snapshot = _list;
    var active = snapshot
        .where((t) => t.status == TransferStatus.active)
        .length;
    if (active >= limit) return;
    for (final t in snapshot.reversed) {
      if (active >= limit) break;
      if (t.status != TransferStatus.queued || _deferred.contains(t)) continue;
      final runner = _runners[t];
      if (runner == null) continue;
      active++;
      runner(); // synchronously flips the transfer to active
    }
  }

  /// Backoff before an automatic retry (exponential: 2s, 4s). Overridable in
  /// tests so they don't have to wait real seconds.
  @visibleForTesting
  Duration Function(int attempts) backoffFor = (attempts) =>
      Duration(seconds: 1 << attempts);

  /// Run [t] once; on failure schedule an automatic retry with backoff until
  /// [maxAttempts] is reached, then settle as Error.
  /// The configured aggregate bandwidth cap in bytes/second, or null when the
  /// "Transfer speed limit" setting is Unlimited (0 KiB/s).
  int? get _transferBytesPerSecond {
    final kbps = ref.read(settingsProvider).transferLimitKbps;
    return kbps <= 0 ? null : kbps * 1024;
  }

  void _runOnce(
    Transfer t,
    PaneController src,
    String srcPath,
    PaneController dst,
    String dstPath,
  ) {
    t.attempts++;
    final control = TransferControl();
    _controls[t] = control;
    // Deliberately not awaited: the queue keeps running while this transfer
    // streams; completion is handled in the .then chain below.
    unawaited(
      _service
          .run(
            t: t,
            src: src.backend,
            srcPath: srcPath,
            dst: dst.backend,
            dstPath: dstPath,
            // Guarded: a run aborted by disposal still fires onStatus while
            // unwinding, when the notifier's state must no longer be touched.
            onStatus: () {
              if (!_disposed) _emit(_list);
            },
            onProgress:
                t.touchLive, // progress repaints only the progress widgets
            verify: ref.read(settingsProvider).verifyLevel,
            bytesPerSecond: _transferBytesPerSecond,
            control: control,
          )
          .then((_) {
            _controls.remove(t);
            // Cancelled mid-run: the queue already removed it and deferred disposing
            // its live notifier until the stream finished unwinding. Do it now.
            if (_cancelled.remove(t)) {
              t.dispose();
              if (!_disposed) _pump();
              return;
            }
            if (_disposed) return;
            // Aborted (paused/cancelled) — the queue already set the desired state.
            if (t.status == TransferStatus.paused) {
              _emit(_list);
              _pump(); // a paused transfer frees a slot for queued ones
              return;
            }
            if (t.status == TransferStatus.done) {
              unawaited(ref.read(historyProvider.notifier).record(t));
              _completionToast(t);
              _maybeNotify(t, success: true);
              unawaited(dst.refresh());
              _pump();
            } else if (t.status == TransferStatus.error) {
              if (t.attempts < maxAttempts) {
                // Transient — back off (2s, 4s) and re-queue. Deferred meanwhile so
                // the scheduler doesn't restart it before the backoff elapses.
                final delay = backoffFor(t.attempts);
                t.status = TransferStatus.queued;
                t.progress = 0;
                _deferred.add(t);
                _emit(_list);
                _pump(); // the freed slot can start a different queued transfer
                Timer(delay, () {
                  _deferred.remove(t);
                  if (_disposed || t.status != TransferStatus.queued) return;
                  _pump();
                });
              } else {
                unawaited(ref.read(historyProvider.notifier).record(t));
                _toast(
                  'Transfer failed',
                  '${t.name}: ${t.errorMessage ?? 'error'}',
                  ToastKind.error,
                );
                _maybeNotify(t, success: false);
                _pump();
              }
            }
          }),
    );
  }

  /// Import OS file-system paths (e.g. dropped from the native file manager)
  /// into [dst] at its current path. Files upload directly; folders recurse.
  void importFiles(PaneController dst, List<String> osPaths) {
    if (!dst.isReady) {
      _toast(
        'Not connected',
        'Connect ${dst.endpointLabel} before dropping files',
        ToastKind.error,
      );
      return;
    }
    if (!dst.backend.supportsMutation) {
      _toast(
        'Read-only',
        "Can't write to ${dst.endpointLabel} here",
        ToastKind.error,
      );
      return;
    }
    for (final osPath in osPaths) {
      final name = p.basename(osPath);
      // A throwaway Local source pane rooted at the dropped item's parent.
      final src = PaneController(backend: LocalBackend(), onChanged: () {})
        ..path = p.dirname(osPath);
      if (FileSystemEntity.isDirectorySync(osPath)) {
        unawaited(enqueueTree(src, dst, FileItem(name: name, isDir: true)));
      } else {
        var size = 0;
        try {
          size = File(osPath).lengthSync();
        } catch (_) {
          /* unknown size */
        }
        final dstPath = dst.backend.childPath(dst.path, name, false);
        enqueueFile(
          src,
          dst,
          osPath,
          dstPath,
          name,
          size,
          announce: osPaths.length == 1,
        );
      }
    }
    if (osPaths.length > 1) {
      _toast(
        'Importing',
        '${osPaths.length} items → ${dst.endpointLabel}',
        ToastKind.info,
      );
    }
  }

  /// Recursively transfer a [folder] from [src] to [dst]: recreate the
  /// directory tree on the destination and enqueue every nested file. Returns
  /// the number of files enqueued. Listing/mkdir errors on one subtree are
  /// reported but don't abort the rest.
  Future<int> enqueueTree(
    PaneController src,
    PaneController dst,
    FileItem folder,
  ) => _withScan(() => _transferFolder(src, dst, folder, _Batch(), false));

  /// Runs a folder-walk [body] with scan progress/cancel state set up and torn
  /// down, so [isScanning] and [cancelFolderScan] work for the duration. The
  /// walk's enqueues are batched (see [_flushBatch]) so a big tree produces a
  /// few list emissions instead of one per file.
  Future<T> _withScan<T>(Future<T> Function() body) async {
    _scanning = true;
    _scanCancelled = false;
    _scanned = 0;
    _batch = <Transfer>[];
    try {
      return await body();
    } finally {
      _flushBatch();
      _batch = null;
      _scanning = false;
    }
  }

  // ── Conflict resolution ──

  /// The UI registers a resolver (a dialog) here; null = no prompting.
  ConflictResolver? _resolver;
  void setConflictResolver(ConflictResolver? r) => _resolver = r;

  /// Transfer a dropped selection of [entries] (files and/or folders) from
  /// [src] to [dst], resolving destination name clashes when "confirm before
  /// overwriting" is on and a resolver is registered. Folders are walked
  /// recursively; one "apply to all" decision spans the whole drop.
  Future<void> transferSelection(
    PaneController src,
    PaneController dst,
    List<FileItem> entries,
  ) async {
    final files = entries.where((e) => !e.isDir).toList();
    final folders = entries.where((e) => e.isDir).toList();
    final settings = ref.read(settingsProvider);
    final batch = _Batch();
    // Conflict handling: a non-"ask" policy preset applies one action to the
    // whole drop without prompting; "ask" falls back to the confirm-overwrite
    // dialog. Either way name-clash detection (and thus a destination listing)
    // is needed, so `confirm` gates that work.
    final preset = _presetAction(settings.conflictPolicy);
    if (preset != null) batch.applyToAll = preset;
    final confirm =
        preset != null || (settings.confirmOverwrite && _resolver != null);
    final single = entries.length == 1 && folders.isEmpty;

    final topNames = confirm
        ? await _namesAt(dst.backend, dst.path)
        : <String>{};
    for (final f in files) {
      await _maybeEnqueue(
        src,
        dst,
        src.path,
        dst.path,
        f.name,
        f.sizeBytes ?? 0,
        topNames,
        batch,
        confirm,
        announce: single,
      );
    }
    if (files.length > 1 && folders.isEmpty) {
      _toast(
        'Transferring',
        '${files.length} files → ${dst.endpointLabel}',
        ToastKind.info,
      );
    }
    if (folders.isNotEmpty) {
      await _withScan(() async {
        for (final folder in folders) {
          if (_scanCancelled) break;
          await _transferFolder(src, dst, folder, batch, confirm);
        }
      });
    }
  }

  Future<int> _transferFolder(
    PaneController src,
    PaneController dst,
    FileItem folder,
    _Batch batch,
    bool confirm,
  ) async {
    if (!dst.backend.supportsMutation) {
      _toast(
        'Not supported',
        "Can't create folders on ${dst.endpointLabel}",
        ToastKind.error,
      );
      return 0;
    }
    final srcRoot = src.backend.childPath(src.path, folder.name, true);
    final dstRoot = dst.backend.childPath(dst.path, folder.name, true);
    _toast(
      'Expanding folder',
      '${folder.name} → ${dst.endpointLabel}',
      ToastKind.info,
    );
    var count = 0;
    try {
      await dst.backend.makeDir(dstRoot);
      count = await _walk(src, dst, srcRoot, dstRoot, batch, confirm);
    } catch (e) {
      _toast("Couldn't read folder", _short(e), ToastKind.error);
    }
    _toast(
      count == 0 ? 'Nothing to transfer' : 'Folder queued',
      count == 0
          ? '${folder.name} has no new files'
          : '$count ${count == 1 ? 'file' : 'files'} from ${folder.name}',
      ToastKind.info,
    );
    return count;
  }

  Future<int> _walk(
    PaneController src,
    PaneController dst,
    String srcDir,
    String dstDir,
    _Batch batch,
    bool confirm,
  ) async {
    final items = await src.backend.list(srcDir);
    final destNames = confirm
        ? await _namesAt(dst.backend, dstDir)
        : <String>{};
    var count = 0;
    for (final it in items) {
      if (_scanCancelled) return count; // user stopped the scan
      if (it.isParent) continue;
      if (it.isDir) {
        final d = dst.backend.childPath(dstDir, it.name, true);
        try {
          await dst.backend.makeDir(d);
          count += await _walk(
            src,
            dst,
            src.backend.childPath(srcDir, it.name, true),
            d,
            batch,
            confirm,
          );
        } catch (e) {
          _toast(
            "Couldn't copy folder",
            '${it.name}: ${_short(e)}',
            ToastKind.error,
          );
        }
      } else {
        if (await _maybeEnqueue(
          src,
          dst,
          srcDir,
          dstDir,
          it.name,
          it.sizeBytes ?? 0,
          destNames,
          batch,
          confirm,
        )) {
          count++;
          // Publish the queued slice, report progress and yield to the event
          // loop periodically so a huge tree doesn't freeze the UI (or flood
          // watchers with per-file emissions) while it's being queued.
          if (++_scanned % 50 == 0) {
            _flushBatch();
            _toast(
              'Queuing folder…',
              '$_scanned files queued so far',
              ToastKind.info,
            );
            await Future<void>.delayed(Duration.zero);
          }
        }
      }
    }
    return count;
  }

  /// Enqueue one file, first resolving a name clash if the destination already
  /// has [name]. Returns true if a transfer was enqueued (false = skipped).
  Future<bool> _maybeEnqueue(
    PaneController src,
    PaneController dst,
    String srcDir,
    String dstDir,
    String name,
    int size,
    Set<String> destNames,
    _Batch batch,
    bool confirm, {
    bool announce = false,
  }) async {
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

  /// The preset conflict action for a [conflictPolicy] setting, or null for the
  /// `'ask'` policy (which prompts instead).
  ConflictAction? _presetAction(String policy) => switch (policy) {
    'skip' => ConflictAction.skip,
    'overwrite' => ConflictAction.overwrite,
    'rename' => ConflictAction.rename,
    _ => null,
  };

  Future<ConflictAction> _ask(
    String name,
    PaneController dst,
    _Batch batch,
  ) async {
    final res = await _resolver!(
      ConflictPrompt(name: name, destLabel: dst.endpointLabel),
    );
    if (res == null) return ConflictAction.skip;
    if (res.applyToAll) batch.applyToAll = res.action;
    return res.action;
  }

  Future<Set<String>> _namesAt(StorageBackend backend, String dir) async {
    try {
      final items = await backend.list(dir);
      return {
        for (final it in items)
          if (!it.isParent) it.name,
      };
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
      if (t.status == TransferStatus.active ||
          t.status == TransferStatus.queued) {
        _controls[t]?.abort(AbortReason.pause); // keep the partial for resume
        // Clear any retry-backoff deferral too, otherwise a transfer paused
        // mid-backoff stays skipped by _pump() after resume until its timer
        // happens to fire.
        _deferred.remove(t);
        t.status = TransferStatus.paused;
        t.speed = '—';
        t.eta = '—';
      }
    }
    _emit(_list);
  }

  void resumeAll() {
    for (final t in _list.toList()) {
      if (t.status == TransferStatus.paused) resume(t);
    }
  }

  void clearDone() {
    final done = _list.where((t) => t.status == TransferStatus.done).toList();
    for (final t in done) {
      // Release each removed transfer's live notifier and drop any lingering
      // scheduler bookkeeping, so clearing the list can't leak `liveTick`s or
      // strand runner/control entries.
      _runners.remove(t);
      _controls.remove(t);
      _deferred.remove(t);
      _cancelled.remove(t);
      _partialCleanups.remove(t);
      t.dispose();
    }
    _emit(_list.where((t) => t.status != TransferStatus.done).toList());
  }

  /// Pause [t]: abort its in-flight stream (if active) and mark it paused,
  /// keeping the staging partial so resume can continue from it. A queued
  /// transfer simply won't start.
  void pause(Transfer t) {
    _controls[t]?.abort(AbortReason.pause);
    _deferred.remove(t);
    t.status = TransferStatus.paused;
    t.speed = '—';
    t.eta = '—';
    _emit(_list);
    _pump(); // pausing frees a concurrency slot
  }

  /// Resume a paused transfer by re-queuing it (a fresh attempt, so pausing
  /// never eats into the auto-retry budget). A pause that kept its staging
  /// partial continues from those bytes (see TransferService); otherwise the
  /// run restarts from zero. The scheduler starts it when a slot is free.
  void resume(Transfer t) {
    if (t.status != TransferStatus.paused) return;
    t.status = TransferStatus.queued;
    t.progress = 0;
    t.attempts = 0;
    _emit(_list);
    _pump();
  }

  /// Cancel [t]: abort any in-flight stream (which discards the partial
  /// destination) and remove it from the queue.
  void cancel(Transfer t) {
    final inFlight = _controls.containsKey(t);
    _controls[t]?.abort(); // a cancel: the run discards its own partial
    _runners.remove(t);
    _deferred.remove(t);
    // A transfer paused mid-stream kept its staging partial for resume; a
    // cancel means it's no longer wanted — discard it (best-effort).
    final cleanup = _partialCleanups.remove(t);
    if (t.pausedWithPartial) {
      t.pausedWithPartial = false;
      unawaited(cleanup?.call());
    }
    _emit(_list.where((x) => !identical(x, t)).toList());
    if (inFlight) {
      // The run is still unwinding and may touch the transfer's live notifier;
      // dispose only once it settles (see _runOnce). The control is removed
      // there too, so leave it in place to be cleaned up by the run.
      _cancelled.add(t);
    } else {
      t.dispose(); // queued/idle: nothing is running, safe to dispose now
    }
    _pump(); // a cancelled active transfer frees a slot
  }

  void togglePause(Transfer t) {
    if (t.status == TransferStatus.paused) {
      resume(t);
    } else if (t.status == TransferStatus.active ||
        t.status == TransferStatus.queued) {
      pause(t);
    }
  }

  /// Re-run a failed transfer from scratch (resets the attempt counter). A
  /// transfer with no stored runner (e.g. seeded in tests) just resets to queued.
  void retry(Transfer t) {
    t.errorMessage = null;
    t.progress = 0;
    t.attempts = 0;
    t.status = TransferStatus.queued;
    _deferred.remove(t);
    _emit(_list);
    _pump();
  }

  /// Retry every currently-failed transfer.
  void retryAllFailed() {
    final failed = _list
        .where((t) => t.status == TransferStatus.error)
        .toList();
    for (final t in failed) {
      retry(t);
    }
    if (failed.isNotEmpty) {
      _toast(
        'Retrying',
        '${failed.length} failed ${failed.length == 1 ? 'transfer' : 'transfers'}',
        ToastKind.info,
      );
    }
  }

  /// Post an OS desktop notification for a finished transfer, but only when the
  /// setting is on and the window is unfocused (so we never notify about
  /// something already on screen). Clicking it refocuses the app and opens the
  /// queue.
  void _maybeNotify(Transfer t, {required bool success}) {
    if (!shouldNotify(
      enabled: ref.read(settingsProvider).notifyOnComplete,
      windowFocused: gWindowFocused,
    )) {
      return;
    }
    final title = success ? 'Transfer complete' : 'Transfer failed';
    final body = success
        ? (t.destPath.isNotEmpty ? t.destPath : '${t.session} · ${t.name}')
        : '${t.name}: ${t.errorMessage ?? 'error'}';
    unawaited(
      gDesktopNotifications?.show(
        title,
        body,
        onClick: () {
          gFocusWindow?.call();
          if (!_disposed) ref.read(navProvider.notifier).go(AppScreen.queue);
        },
      ),
    );
  }

  /// Rich "transfer completed" notification: destination path, size, time.
  void _completionToast(Transfer t) {
    final dest = t.destPath.isNotEmpty
        ? t.destPath
        : '${t.session} · ${t.name}';
    _toast(
      'File transfer completed',
      dest,
      ToastKind.success,
      detail:
          '${formatBytes(t.sizeBytes)} · ${t.elapsedLabel}'
          '${t.speed != '—' ? ' · ${t.speed}' : ''}',
    );
  }
}

final transfersProvider = NotifierProvider<TransfersNotifier, TransfersState>(
  TransfersNotifier.new,
);
