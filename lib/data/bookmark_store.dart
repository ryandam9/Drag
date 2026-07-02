import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_db.dart';
import 'db_migrations.dart';

/// A saved (endpoint, path) shortcut. [connId] is the connection id the path
/// belongs to, or null for the Local endpoint.
class Bookmark {
  final int? id;
  final String? connId;
  final String path;
  final String label;
  const Bookmark({this.id, this.connId, required this.path, required this.label});

  Bookmark withId(int id) => Bookmark(id: id, connId: connId, path: path, label: label);

  Map<String, Object?> toRow() => {
        'conn_id': connId,
        'path': path,
        'label': label,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory Bookmark.fromRow(Map<String, Object?> r) => Bookmark(
        id: r['id'] as int?,
        connId: r['conn_id'] as String?,
        path: r['path'] as String? ?? '',
        label: r['label'] as String? ?? '',
      );
}

/// Persists [Bookmark]s in a local SQLite database, newest first.
class BookmarkStore {
  BookmarkStore._(this._db);

  final Database _db;
  static const _table = 'bookmarks';

  static Future<BookmarkStore> open([String? path]) async {
    final db = await openAppDb(
      'drag_bookmarks.db',
      path: path,
      migrations: _migrations,
      onCreate: (db) => db.execute('''
        CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          conn_id TEXT,
          path TEXT NOT NULL,
          label TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      '''),
    );
    return BookmarkStore._(db);
  }

  Future<List<Bookmark>> load() async {
    final rows = await _db.query(_table, orderBy: 'created_at DESC, id DESC');
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<int> add(Bookmark b) => _db.insert(_table, b.toRow());

  Future<void> remove(int id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> close() => _db.close();
}

/// Schema migrations keyed by the version they bring the database *to*.
/// Empty today (schema v1); add an entry and bump `version` for each change.
final _migrations = <int, Migration>{};
