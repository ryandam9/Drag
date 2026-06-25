import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  KnownHostsStore._(this._db);

  final Database _db;
  static const _table = 'known_hosts';

  static Future<KnownHostsStore> open([String? path]) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath = path ?? await _defaultPath(factory);
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            host TEXT NOT NULL,
            port INTEGER NOT NULL,
            type TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        '''),
      ),
    );
    return KnownHostsStore._(db);
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final base = await factory.getDatabasesPath();
    return base.endsWith('/') ? '${base}drag_known_hosts.db' : '$base/drag_known_hosts.db';
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

  Future<void> trust(KnownHost h) => _db.insert(_table, h.toRow());

  Future<void> remove(int id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> forget(String host, int port) =>
      _db.delete(_table, where: 'host = ? AND port = ?', whereArgs: [host, port]);

  Future<void> clear() => _db.delete(_table);

  Future<void> close() => _db.close();
}
