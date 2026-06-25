import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_migrations.dart';

import '../models/connection.dart';

/// Persists saved connections in a local SQLite database (one JSON row per
/// connection, plus an ordering index). Secrets are intentionally NOT stored
/// here — see [Connection.toJson] and issue #16 (OS keychain).
class ConnectionStore {
  ConnectionStore._(this._db);

  final Database _db;
  static const _table = 'connections';

  static Future<ConnectionStore> open([String? path]) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath = path ?? await _defaultPath(factory);
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onUpgrade: (db, oldV, newV) => runMigrations(db, oldV, newV, _migrations),
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            sort INTEGER NOT NULL,
            data TEXT NOT NULL
          )
        '''),
      ),
    );
    return ConnectionStore._(db);
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final base = await factory.getDatabasesPath();
    return base.endsWith('/') ? '${base}drag_connections.db' : '$base/drag_connections.db';
  }

  Future<List<Connection>> load() async {
    final rows = await _db.query(_table, orderBy: 'sort ASC');
    return rows
        .map((r) => Connection.fromJson(
            jsonDecode(r['data'] as String) as Map<String, Object?>))
        .toList();
  }

  Future<void> upsert(Connection c, int sort) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    await _db.insert(
      _table,
      {'id': c.id, 'sort': sort, 'data': jsonEncode(c.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  /// Rewrites the whole table to match [connections] (order = list order).
  Future<void> replaceAll(List<Connection> connections) async {
    await _db.transaction((txn) async {
      await txn.delete(_table);
      for (var i = 0; i < connections.length; i++) {
        final c = connections[i];
        if (c.id.isEmpty) c.id = Connection.newId();
        await txn.insert(_table,
            {'id': c.id, 'sort': i, 'data': jsonEncode(c.toJson())});
      }
    });
  }

  Future<void> close() => _db.close();
}

/// Schema migrations keyed by the version they bring the database *to*.
/// Empty today (schema v1); add an entry and bump `version` for each change.
final _migrations = <int, Migration>{};
