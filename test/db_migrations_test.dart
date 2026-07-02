import 'dart:io';

import 'package:drag/data/db_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  final factory = databaseFactoryFfi;

  group('runMigrations', () {
    test('applies only steps in (oldVersion, newVersion], in order', () async {
      final applied = <int>[];
      final migrations = <int, Migration>{
        2: (db) async => applied.add(2),
        3: (db) async => applied.add(3),
        4: (db) async => applied.add(4),
      };
      final db = await factory.openDatabase(inMemoryDatabasePath);
      await runMigrations(db, 1, 3, migrations);
      expect(applied, [2, 3], reason: 'v4 is beyond newVersion');
      await db.close();
    });

    test('a bumped version with no matching step is a no-op', () async {
      final db = await factory.openDatabase(inMemoryDatabasePath);
      // Empty map ⇒ nothing runs, no throw.
      await runMigrations(db, 1, 5, <int, Migration>{});
      await db.close();
    });

    test('end-to-end: a real onUpgrade adds a column and preserves data', () async {
      // A real file so the database persists across the two opens (in-memory
      // databases are recreated each open, which would never trigger onUpgrade).
      final dir = await Directory.systemTemp.createTemp('drag-migrate');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'mig.db');

      // Open at v1 with an initial schema and seed a row.
      final db1 = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
          ),
        ),
      );
      await db1.insert('t', {'id': 1, 'name': 'alpha'});
      await db1.close();

      // Reopen at v2 → onUpgrade runs the migration on the existing data.
      final migrations = <int, Migration>{
        2: (db) => db.execute("ALTER TABLE t ADD COLUMN note TEXT DEFAULT ''"),
      };
      final db2 = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => db.execute(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL, note TEXT DEFAULT '')",
          ),
          onUpgrade: (db, oldV, newV) =>
              runMigrations(db, oldV, newV, migrations),
        ),
      );

      final rows = await db2.query('t');
      expect(
        rows.single['name'],
        'alpha',
        reason: 'existing data survives the upgrade',
      );
      expect(
        rows.single['note'],
        '',
        reason: 'the new column exists with its default',
      );
      await db2.close();
    });
  });
}
