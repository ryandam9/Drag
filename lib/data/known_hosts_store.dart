import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_db.dart';
import 'db_migrations.dart';

/// Whether trusted host keys survive a restart, or only last the session.
enum KnownHostsStoreStatus {
  /// Backed by an on-disk SQLite database — trusted keys persist across runs.
  persistent,

  /// The on-disk store couldn't be opened; an in-memory database is used so
  /// verification still happens, but trusted keys are forgotten on exit.
  memoryOnly,
}

/// A trusted SSH host key, remembered after the first connection (TOFU).
class KnownHost {
  final int? id;
  final String host;
  final int port;

  /// Host-key algorithm (e.g. `ssh-ed25519`, `rsa-sha2-512`).
  final String type;

  /// OpenSSH-style fingerprint, e.g. `SHA256:abc123…`.
  final String fingerprint;

  const KnownHost({
    this.id,
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
  });

  /// Stable label for the host (host:port, omitting the default SSH port).
  String get endpoint => port == 22 ? host : '$host:$port';

  Map<String, Object?> toRow() => {
        'host': host,
        'port': port,
        'type': type,
        'fingerprint': fingerprint,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory KnownHost.fromRow(Map<String, Object?> r) => KnownHost(
        id: r['id'] as int?,
        host: r['host'] as String? ?? '',
        port: (r['port'] as int?) ?? 22,
        type: r['type'] as String? ?? '',
        fingerprint: r['fingerprint'] as String? ?? '',
      );
}

/// Persists trusted SSH host keys in a local SQLite database.
class KnownHostsStore {
  KnownHostsStore._(this._db, this.status);

  final Database _db;

  /// Whether trusted keys persist across restarts or are session-only.
  final KnownHostsStoreStatus status;

  static const _table = 'known_hosts';
  static const _hostPortIndex = 'idx_known_hosts_host_port';

  static Future<KnownHostsStore> open([String? path]) async {
    final db = await openAppDb(
      'drag_known_hosts.db',
      path: path,
      version: 2,
      migrations: _migrations,
      onCreate: (db) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            host TEXT NOT NULL,
            port INTEGER NOT NULL,
            type TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        // One trusted key per host:port — upsert on re-trust, no duplicates.
        await db.execute(
            'CREATE UNIQUE INDEX $_hostPortIndex ON $_table(host, port)');
      },
    );
    // The default path is always an on-disk file; only an explicit in-memory
    // path (the fallback when the disk store can't open) is session-only.
    final status = path == inMemoryDatabasePath
        ? KnownHostsStoreStatus.memoryOnly
        : KnownHostsStoreStatus.persistent;
    return KnownHostsStore._(db, status);
  }

  Future<List<KnownHost>> load() async {
    final rows = await _db.query(_table, orderBy: 'host ASC, port ASC');
    return rows.map(KnownHost.fromRow).toList();
  }

  /// The remembered key for [host]:[port], or null if never seen.
  Future<KnownHost?> find(String host, int port) async {
    final rows = await _db.query(_table,
        where: 'host = ? AND port = ?', whereArgs: [host, port], limit: 1);
    return rows.isEmpty ? null : KnownHost.fromRow(rows.first);
  }

  /// Remember [h]. Upserts on `(host, port)` — re-trusting a host (e.g. after a
  /// legitimate key rotation the user re-confirmed) replaces the stored
  /// fingerprint instead of leaving a duplicate row.
  Future<void> trust(KnownHost h) =>
      _db.insert(_table, h.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(int id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> forget(String host, int port) =>
      _db.delete(_table, where: 'host = ? AND port = ?', whereArgs: [host, port]);

  Future<void> clear() => _db.delete(_table);

  Future<void> close() => _db.close();
}

/// Schema migrations keyed by the version they bring the database *to*.
final _migrations = <int, Migration>{
  // v2: enforce one trusted key per (host, port). De-duplicate any existing
  // rows (keeping the most recently inserted) before adding the unique index.
  2: (db) async {
    await db.execute('''
      DELETE FROM known_hosts WHERE id NOT IN (
        SELECT MAX(id) FROM known_hosts GROUP BY host, port
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_known_hosts_host_port ON known_hosts(host, port)');
  },
};
