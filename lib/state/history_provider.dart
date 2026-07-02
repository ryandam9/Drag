import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_db.dart';
import '../models/transfer.dart';
import 'providers.dart';

/// The transfer history shown on the dashboard.
class HistoryState {
  final List<TransferRecord> records;
  final HistoryStats stats;
  final bool hasDb;
  const HistoryState({
    this.records = const [],
    this.stats = const HistoryStats(),
    this.hasDb = false,
  });
}

/// Persistent transfer history, backed by [HistoryRepository] (SQLite). Loads
/// on first build and refreshes whenever a transfer finishes.
class HistoryNotifier extends Notifier<HistoryState> {
  HistoryRepository? get _repo => ref.read(historyRepositoryProvider);
  bool _disposed = false;
  Timer? _refreshTimer;

  /// Trailing debounce for post-[record] refreshes, so a burst of completions
  /// (e.g. a folder drop finishing hundreds of files) reloads the dashboard
  /// once, not once per file. Overridable in tests to avoid real waits.
  @visibleForTesting
  Duration refreshDebounce = const Duration(milliseconds: 250);

  @override
  HistoryState build() {
    ref.onDispose(() {
      _disposed = true;
      // Nothing needs flushing: every record was already persisted by
      // [record]; the pending refresh would only re-read the DB for a state
      // that no longer exists.
      _refreshTimer?.cancel();
    });
    final hasDb = _repo != null;
    if (hasDb) unawaited(refresh());
    return HistoryState(hasDb: hasDb);
  }

  /// Persist a finished transfer, then schedule a (debounced) refresh of the
  /// dashboard data.
  Future<void> record(Transfer t) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.add(TransferRecord.fromTransfer(t));
      _scheduleRefresh();
    } catch (_) {
      /* history is best-effort */
    }
  }

  /// Trailing-edge debounce: each record pushes the reload back, so a burst
  /// settles into a single refresh shortly after the last completion.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDebounce, () {
      if (!_disposed) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) return;
    final records = await repo.recent();
    final stats = await repo.stats();
    if (_disposed) return;
    state = HistoryState(records: records, stats: stats, hasDb: true);
  }

  Future<void> clear() async {
    await _repo?.clear();
    await refresh();
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);
