import 'dart:io';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

FileItem _f(String name, int size) => FileItem(name: name, sizeBytes: size);
FileItem _d(String name) => FileItem(name: name, isDir: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('comparePanes', () {
    test('classifies only-here / differs / same', () {
      final left = [_f('a', 1), _f('b', 2), _d('shared'), _f('common', 5)];
      final right = [_f('b', 9), _f('c', 3), _d('shared'), _f('common', 5)];
      final diff = comparePanes(left, right);

      expect(diff.left['a'], CompareMark.onlyHere);
      expect(diff.left['b'], CompareMark.differs); // size 2 vs 9
      expect(diff.left['shared'], CompareMark.same); // both folders
      expect(diff.left['common'], CompareMark.same);
      expect(diff.right['c'], CompareMark.onlyHere);

      expect(diff.onlyLeft, 1);
      expect(diff.onlyRight, 1);
      expect(diff.differing, 1);
      expect(diff.isIdentical, isFalse);
    });

    test('identical listings report no differences', () {
      final items = [_f('a', 1), _d('d')];
      final diff = comparePanes(items, [_f('a', 1), _d('d')]);
      expect(diff.isIdentical, isTrue);
    });

    test('a file vs a folder of the same name differs', () {
      final diff = comparePanes([_f('x', 0)], [_d('x')]);
      expect(diff.left['x'], CompareMark.differs);
    });
  });

  group('planMirror', () {
    test('copies missing/different entries and deletes extras', () {
      final left = [_f('a', 1), _f('b', 2), _d('folder'), _f('common', 5)];
      final right = [_f('b', 9), _f('c', 3), _f('common', 5)];
      final plan = planMirror(left, right, leftToRight: true, deleteExtras: true);

      expect(plan.copy.map((e) => e.name).toSet(), {'a', 'b', 'folder'}); // c-same skipped
      expect(plan.fileCopies, 2); // a, b
      expect(plan.folderCopies, 1); // folder
      expect(plan.delete.map((e) => e.name).toList(), ['c']);
      expect(plan.isEmpty, isFalse);
    });

    test('without deleteExtras, nothing is deleted', () {
      final plan = planMirror([_f('a', 1)], [_f('b', 2)], leftToRight: true, deleteExtras: false);
      expect(plan.copy.map((e) => e.name), ['a']);
      expect(plan.delete, isEmpty);
    });
  });

  group('runMirror (Local→Local)', () {
    test('copies differences and deletes destination-only extras', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final l = await Directory.systemTemp.createTemp('mir_l');
      final r = await Directory.systemTemp.createTemp('mir_r');
      addTearDown(() => l.delete(recursive: true));
      addTearDown(() => r.delete(recursive: true));
      await File(p.join(l.path, 'a.txt')).writeAsString('A');
      await File(p.join(l.path, 'common.txt')).writeAsString('X');
      await File(p.join(r.path, 'b.txt')).writeAsString('B'); // extra on the right
      await File(p.join(r.path, 'common.txt')).writeAsString('X');

      s.leftPane
        ..backend = LocalBackend()
        ..path = l.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = r.path;
      await s.rightPane.refresh();

      final plan = s.mirrorPlan(leftToRight: true, deleteExtras: true);
      expect(plan.copy.map((e) => e.name), ['a.txt']); // common is identical
      expect(plan.delete.map((e) => e.name), ['b.txt']);
      await s.runMirror(plan);

      final copied = File(p.join(r.path, 'a.txt'));
      for (var i = 0; i < 200 && !copied.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await copied.readAsString(), 'A');
      expect(File(p.join(r.path, 'b.txt')).existsSync(), isFalse); // extra deleted
      expect(await File(p.join(r.path, 'common.txt')).readAsString(), 'X');
    });
  });

  group('compareActivePanes', () {
    test('marks both panes and toasts a summary', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final l = await Directory.systemTemp.createTemp('cmp_l');
      final r = await Directory.systemTemp.createTemp('cmp_r');
      addTearDown(() => l.delete(recursive: true));
      addTearDown(() => r.delete(recursive: true));
      await File(p.join(l.path, 'only_left.txt')).writeAsString('1');
      await File(p.join(r.path, 'only_right.txt')).writeAsString('2');

      s.leftPane
        ..backend = LocalBackend()
        ..path = l.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = r.path;
      await s.rightPane.refresh();

      final diff = s.compareActivePanes();
      expect(diff.onlyLeft, 1);
      expect(diff.onlyRight, 1);
      expect(s.leftPane.compareMarks['only_left.txt'], CompareMark.onlyHere);
      expect(s.rightPane.compareMarks['only_right.txt'], CompareMark.onlyHere);
      expect(c.read(toastsProvider).last.title, 'Compared');
    });
  });
}
