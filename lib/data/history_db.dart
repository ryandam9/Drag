import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/transfer.dart';
import 'app_db.dart';
import 'db_migrations.dart';

/// A persisted record of a finished transfer.
class TransferRecord {
  final int? id;
  final String name;
  final String sourcePath;
  final String destPath;
  final String session;
  final int sizeBytes;
  final int direction; // 0 = upload, 1 = download
  final int durationMs;
  final bool success;
  final String? error;
  final DateTime finishedAt;

  const TransferRecord({
    this.id,
    required this.name,
    required this.sourcePath,
    required this.destPath,
    required this.session,
    required this.sizeBytes,
    required this.direction,
    required this.durationMs,
    required this.success,
    required this.finishedAt,
    this.error,
  });

  bool get isUpload => direction == 0;

  /// Average throughput in bytes/sec (0 if unknown).
  double get bytesPerSecond =>
      durationMs <= 0 ? 0 : sizeBytes * 1000 / durationMs;

  factory TransferRecord.fromTransfer(Transfer t) {
    // Fall back to the human route ("src → dst") when explicit paths are absent
    // (e.g. simulated/seed transfers).
    var src = t.sourcePath;
    var dst = t.destPath;
    if (src.isEmpty && dst.isEmpty && t.route.contains(' → ')) {
      final parts = t.route.split(' → ');
      src = parts.first.trim();
      dst = parts.length > 1 ? parts[1].trim() : '';
    }
    return TransferRecord(
      name: t.name,
      sourcePath: src,
      destPath: dst,
      session: t.session,
      sizeBytes: t.sizeBytes,
      direction: t.direction == TransferDirection.upload ? 0 : 1,
      durationMs: t.elapsed?.inMilliseconds ?? 0,
      success: t.status == TransferStatus.done,
      error: t.errorMessage,
      finishedAt: t.finishedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'source_path': sourcePath,
    'dest_path': destPath,
    'session': session,
    'size_bytes': sizeBytes,
    'direction': direction,
    'duration_ms': durationMs,
    'success': success ? 1 : 0,
    'error': error,
    'finished_at': finishedAt.toUtc().toIso8601String(),
  };

  factory TransferRecord.fromMap(Map<String, Object?> m) => TransferRecord(
    id: m['id'] as int?,
    name: m['name'] as String? ?? '',
    sourcePath: m['source_path'] as String? ?? '',
    destPath: m['dest_path'] as String? ?? '',
    session: m['session'] as String? ?? '',
    sizeBytes: (m['size_bytes'] as int?) ?? 0,
    direction: (m['direction'] as int?) ?? 0,
    durationMs: (m['duration_ms'] as int?) ?? 0,
    success: (m['success'] as int?) == 1,
    error: m['error'] as String?,
    finishedAt:
        DateTime.tryParse(m['finished_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// Aggregate numbers for the dashboard.
class HistoryStats {
  final int total;
  final int succeeded;
  final int failed;
  final int totalBytes;
  final double avgBytesPerSecond;

  const HistoryStats({
    this.total = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.totalBytes = 0,
    this.avgBytesPerSecond = 0,
  });
}

/// Stores completed/failed transfers in a local SQLite database
/// (via `sqflite_common_ffi`, which works on macOS/Linux/Windows desktop).
class HistoryRepository {
  HistoryRepository._(this._db);

  final Database _db;

  static const _table = 'transfers';

  /// Opens (and migrates) the database. Pass `inMemoryDatabasePath` for tests.
  static Future<HistoryRepository> open([String? path]) async {
    final db = await openAppDb(
      'drag_history.db',
      path: path,
      migrations: _migrations,
      onCreate: (db) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            source_path TEXT NOT NULL,
            dest_path TEXT NOT NULL,
            session TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            direction INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            success INTEGER NOT NULL,
            error TEXT,
            finished_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_finished ON $_table(finished_at DESC)',
        );
      },
    );
    final repo = HistoryRepository._(db);
    await repo._purgeLegacySeed();
    return repo;
  }

  /// One-time cleanup: very early builds of the app shipped demo/seed transfer
  /// rows (e.g. uploads to the fictional `prod-server-01`). Those were removed
  /// from the code long ago, but they linger in databases created by those
  /// builds. This deletes ONLY rows matching that exact legacy signature, so it
  /// can never touch a real transfer the user actually ran.
  Future<void> _purgeLegacySeed() async {
    try {
      await _db.delete(
        _table,
        where:
            "dest_path LIKE '%prod-server-01%' "
            "AND name IN ('backup_2025-06-19.tar.gz', 'deploy.sh', 'config.yaml')",
      );
    } catch (_) {
      // Best-effort — never block startup on cleanup.
    }
  }

  Future<int> add(TransferRecord record) => _db.insert(_table, record.toMap());

  Future<List<TransferRecord>> recent({int limit = 200}) async {
    final rows = await _db.query(
      _table,
      orderBy: 'finished_at DESC',
      limit: limit,
    );
    return rows.map(TransferRecord.fromMap).toList();
  }

  Future<HistoryStats> stats() async {
    final r = (await _db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        COALESCE(SUM(success), 0) AS succeeded,
        COALESCE(SUM(size_bytes), 0) AS total_bytes,
        COALESCE(SUM(CASE WHEN success = 1 AND duration_ms > 0 THEN size_bytes ELSE 0 END), 0) AS ok_bytes,
        COALESCE(SUM(CASE WHEN success = 1 AND duration_ms > 0 THEN duration_ms ELSE 0 END), 0) AS ok_ms
      FROM $_table
    ''')).first;

    final total = (r['total'] as int?) ?? 0;
    final succeeded = (r['succeeded'] as int?) ?? 0;
    final totalBytes = (r['total_bytes'] as int?) ?? 0;
    final okBytes = (r['ok_bytes'] as int?) ?? 0;
    final okMs = (r['ok_ms'] as int?) ?? 0;
    return HistoryStats(
      total: total,
      succeeded: succeeded,
      failed: total - succeeded,
      totalBytes: totalBytes,
      avgBytesPerSecond: okMs <= 0 ? 0 : okBytes * 1000 / okMs,
    );
  }

  Future<void> clear() => _db.delete(_table);

  Future<void> close() => _db.close();
}

/// Schema migrations keyed by the version they bring the database *to*.
/// Empty today (schema v1); add an entry and bump `version` for each change.
final _migrations = <int, Migration>{};
