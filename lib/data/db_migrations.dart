import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A single forward schema change, applied when upgrading the database *to*
/// its keyed version. Should be idempotent-friendly where practical (e.g.
/// `ALTER TABLE … ADD COLUMN`).
typedef Migration = Future<void> Function(Database db);

/// Applies every migration whose target version falls in
/// `(oldVersion, newVersion]`, in ascending version order. Wire it up as a
/// sqflite `onUpgrade` callback:
///
/// ```dart
/// OpenDatabaseOptions(
///   version: 2,
///   onCreate: _create,                       // builds the latest schema
///   onUpgrade: (db, old, now) => runMigrations(db, old, now, _migrations),
/// )
/// ```
///
/// where `_migrations` maps a target version to the step that reaches it:
///
/// ```dart
/// final _migrations = <int, Migration>{
///   2: (db) => db.execute('ALTER TABLE settings ADD COLUMN theme TEXT'),
/// };
/// ```
///
/// A bumped `version` with no matching entry is a no-op, so it's safe to raise
/// the version for an `onCreate`-only schema change and backfill the migration
/// later. Steps run on the open database in a single upgrade pass.
Future<void> runMigrations(
  Database db,
  int oldVersion,
  int newVersion,
  Map<int, Migration> migrations,
) async {
  for (var v = oldVersion + 1; v <= newVersion; v++) {
    final step = migrations[v];
    if (step != null) await step(db);
  }
}
