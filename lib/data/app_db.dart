import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_migrations.dart';

/// Opens one of the app's SQLite databases via `sqflite_common_ffi` (which
/// works on macOS/Linux/Windows desktop), wiring up the create/migrate
/// scaffolding every store otherwise duplicates.
///
/// Each store keeps its own separate database *file* — [filename] under the
/// platform databases directory — deliberately not consolidated into one
/// (declined in issue #140); this helper is code dedup only. [path] overrides
/// the location entirely (tests pass `inMemoryDatabasePath`). [onCreate]
/// builds the latest schema on first open; [migrations] upgrade older files
/// (see [runMigrations]).
Future<Database> openAppDb(
  String filename, {
  String? path,
  int version = 1,
  required FutureOr<void> Function(Database db) onCreate,
  Map<int, Migration> migrations = const {},
}) async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final dbPath = path ?? await _defaultPath(factory, filename);
  return factory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: version,
      onUpgrade: (db, oldV, newV) => runMigrations(db, oldV, newV, migrations),
      onCreate: (db, _) async => await onCreate(db),
    ),
  );
}

Future<String> _defaultPath(DatabaseFactory factory, String filename) async {
  final base = await factory.getDatabasesPath();
  return base.endsWith('/') ? '$base$filename' : '$base/$filename';
}
