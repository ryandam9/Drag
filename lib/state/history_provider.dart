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

  @override
  HistoryState build() {
    ref.onDispose(() => _disposed = true);
    final hasDb = _repo != null;
    if (hasDb) refresh();
    return HistoryState(hasDb: hasDb);
  }

  /// Persist a finished transfer, then refresh the dashboard data.
  Future<void> record(Transfer t) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.add(TransferRecord.fromTransfer(t));
      await refresh();
    } catch (_) {/* history is best-effort */}
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

final historyProvider =
    NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);
