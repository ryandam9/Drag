import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
            conn_id TEXT,
            path TEXT NOT NULL,
            label TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        '''),
      ),
    );
    return BookmarkStore._(db);
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final base = await factory.getDatabasesPath();
    return base.endsWith('/') ? '${base}drag_bookmarks.db' : '$base/drag_bookmarks.db';
  }

  Future<List<Bookmark>> load() async {
    final rows = await _db.query(_table, orderBy: 'created_at DESC, id DESC');
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<int> add(Bookmark b) => _db.insert(_table, b.toRow());

  Future<void> remove(int id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> close() => _db.close();
}
