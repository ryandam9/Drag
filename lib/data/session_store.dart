import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One persisted browser tab: which endpoint each pane points at (a saved
/// connection id, or `null` for the Local filesystem) and the directory it was
/// last showing. Paths are restored on next launch; credentials are not stored
/// here (they live only in memory — see [Connection.toJson]).
class SessionRecord {
  final String? leftConnId;
  final String leftPath;
  final String? rightConnId;
  final String rightPath;

  const SessionRecord({
    this.leftConnId,
    this.leftPath = '',
    this.rightConnId,
    this.rightPath = '',
  });

  Map<String, Object?> toMap(int sort, bool active) => {
        'sort': sort,
        'left_conn': leftConnId,
        'left_path': leftPath,
        'right_conn': rightConnId,
        'right_path': rightPath,
        'active': active ? 1 : 0,
      };

  factory SessionRecord.fromMap(Map<String, Object?> m) => SessionRecord(
        leftConnId: m['left_conn'] as String?,
        leftPath: (m['left_path'] as String?) ?? '',
        rightConnId: m['right_conn'] as String?,
        rightPath: (m['right_path'] as String?) ?? '',
      );
}

/// The persisted session layout: the open tabs and which one was active.
class SessionLayout {
  final List<SessionRecord> sessions;
  final int activeIndex;
  const SessionLayout(this.sessions, this.activeIndex);

  static const empty = SessionLayout([], 0);
}

/// Persists the open browser tabs (and the active one) in local SQLite, so the
/// workspace comes back exactly as the user left it across launches.
class SessionStore {
  SessionStore._(this._db);

  final Database _db;
  static const _table = 'sessions';

  static Future<SessionStore> open([String? path]) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath = path ?? await _defaultPath(factory);
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            sort INTEGER PRIMARY KEY,
            left_conn TEXT,
            left_path TEXT NOT NULL,
            right_conn TEXT,
            right_path TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 0
          )
        '''),
      ),
    );
    return SessionStore._(db);
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final base = await factory.getDatabasesPath();
    return base.endsWith('/') ? '${base}drag_sessions.db' : '$base/drag_sessions.db';
  }

  Future<SessionLayout> load() async {
    final rows = await _db.query(_table, orderBy: 'sort ASC');
    if (rows.isEmpty) return SessionLayout.empty;
    final sessions = rows.map(SessionRecord.fromMap).toList();
    final activeIndex = rows.indexWhere((r) => (r['active'] as int?) == 1);
    return SessionLayout(sessions, activeIndex < 0 ? 0 : activeIndex);
  }

  /// Rewrites the whole table to match [sessions] (order = list order).
  Future<void> replaceAll(List<SessionRecord> sessions, {int activeIndex = 0}) async {
    await _db.transaction((txn) async {
      await txn.delete(_table);
      for (var i = 0; i < sessions.length; i++) {
        await txn.insert(_table, sessions[i].toMap(i, i == activeIndex));
      }
    });
  }

  Future<void> close() => _db.close();
}
