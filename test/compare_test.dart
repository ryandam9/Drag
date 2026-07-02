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

  group('planMirrorRecursive', () {
    // Build a planner over two in-memory trees keyed by directory path
    // ("/" rooted, "/" + name children). Empty/absent dirs list as nothing.
    Future<MirrorPlan> plan(
      Map<String, List<FileItem>> src,
      Map<String, List<FileItem>> dst, {
      bool deleteExtras = false,
      CompareMode mode = CompareMode.size,
      MirrorHasher? hashSrc,
      MirrorHasher? hashDst,
      MirrorCancel? cancel,
      void Function(int)? onScanned,
      int? maxDepth,
      int? maxFiles,
    }) {
      String join(String path, String name, bool isDir) =>
          path == '/' ? '/$name' : '$path/$name';
      return planMirrorRecursive(
        srcRoot: '/',
        dstRoot: '/',
        listSrc: (p) async => src[p] ?? const [],
        listDst: (p) async => dst[p] ?? const [],
        joinSrc: join,
        joinDst: join,
        leftToRight: true,
        deleteExtras: deleteExtras,
        mode: mode,
        hashSrc: hashSrc,
        hashDst: hashDst,
        cancel: cancel,
        onScanned: onScanned,
        maxDepth: maxDepth,
        maxFiles: maxFiles,
      );
    }

    test('catches a difference nested inside a same-named folder', () async {
      final p = await plan(
        {
          '/': [_f('top', 1), _d('sub')],
          '/sub': [_f('nested', 10), _f('same', 3)],
        },
        {
          '/': [_f('top', 1), _d('sub')],
          '/sub': [_f('nested', 99), _f('same', 3)], // nested differs by size
        },
      );
      // The shallow planner treated /sub as "same"; the recursive one descends.
      expect(p.copies.map((c) => c.srcPath), ['/sub/nested']);
      expect(p.copies.single.dstPath, '/sub/nested');
      expect(p.dirCount, 0); // /sub already exists on both sides
    });

    test('creates missing folders and copies their contents', () async {
      final p = await plan(
        {
          '/': [_d('sub')],
          '/sub': [_f('a', 1), _d('deep')],
          '/sub/deep': [_f('b', 2)],
        },
        {'/': const []},
      );
      expect(p.mkdirs.map((m) => m.dstPath), [
        '/sub',
        '/sub/deep',
      ]); // parents first
      expect(p.copies.map((c) => c.dstPath).toSet(), {'/sub/a', '/sub/deep/b'});
      expect(p.totalBytes, 3);
    });

    test(
      'size+modified mode flags same-size files with a different mtime',
      () async {
        const sA = FileItem(name: 'a', sizeBytes: 10, modified: '2025-01-01');
        const dA = FileItem(name: 'a', sizeBytes: 10, modified: '2025-02-02');
        // Size-only sees them as identical; size+time catches the change.
        final sizeOnly = await plan(
          {
            '/': [sA],
          },
          {
            '/': [dA],
          },
        );
        expect(sizeOnly.copies, isEmpty);
        final withTime = await plan(
          {
            '/': [sA],
          },
          {
            '/': [dA],
          },
          mode: CompareMode.sizeAndTime,
        );
        expect(withTime.copies.map((c) => c.dstPath), ['/a']);
      },
    );

    test('checksum mode compares content hashes for same-size files', () async {
      const sA = FileItem(name: 'a', sizeBytes: 10);
      const dA = FileItem(name: 'a', sizeBytes: 10);
      final p = await plan(
        {
          '/': [sA],
        },
        {
          '/': [dA],
        },
        mode: CompareMode.checksum,
        hashSrc: (_) async => 'HASH_A',
        hashDst: (_) async => 'HASH_B', // differs → copy
      );
      expect(p.copies.map((c) => c.dstPath), ['/a']);

      final same = await plan(
        {
          '/': [sA],
        },
        {
          '/': [dA],
        },
        mode: CompareMode.checksum,
        hashSrc: (_) async => 'SAME',
        hashDst: (_) async => 'SAME', // equal → skip
      );
      expect(same.copies, isEmpty);
    });

    test('maxDepth bounds recursion and marks the plan truncated', () async {
      final p = await plan(
        {
          '/': [_d('sub')],
          '/sub': [_f('a', 1), _d('deep')],
          '/sub/deep': [_f('b', 2)],
        },
        {'/': const []},
        maxDepth: 1, // don't descend into /sub/deep
      );
      expect(p.copies.map((c) => c.dstPath), ['/sub/a']);
      expect(p.copies.any((c) => c.dstPath == '/sub/deep/b'), isFalse);
    });

    test('a cancel stops planning and marks it truncated', () async {
      final cancel = MirrorCancel()..cancel();
      final p = await plan(
        {
          '/': [_f('a', 1), _f('b', 2)],
        },
        {'/': const []},
        cancel: cancel,
      );
      expect(p.truncated, isTrue);
      expect(p.copies, isEmpty); // cancelled before examining entries
    });

    test('maxFiles caps the scan and reports truncated', () async {
      final p = await plan(
        {
          '/': [_f('a', 1), _f('b', 1), _f('c', 1)],
        },
        {'/': const []},
        maxFiles: 2,
      );
      expect(p.truncated, isTrue);
      expect(p.copies.length, lessThanOrEqualTo(2));
    });

    test('identical trees produce an empty plan', () async {
      final tree = {
        '/': [_f('a', 1), _d('sub')],
        '/sub': [_f('b', 2)],
      };
      final p = await plan(tree, {
        '/': [_f('a', 1), _d('sub')],
        '/sub': [_f('b', 2)],
      });
      expect(p.isEmpty, isTrue);
    });

    test(
      'deleteExtras removes destination-only entries at any depth',
      () async {
        final p = await plan(
          {
            '/': [_d('sub')],
            '/sub': [_f('keep', 1)],
          },
          {
            '/': [_d('sub'), _f('topextra', 9)],
            '/sub': [_f('keep', 1), _f('subextra', 4)],
          },
          deleteExtras: true,
        );
        expect(p.deletes.map((d) => d.dstPath).toSet(), {
          '/topextra',
          '/sub/subextra',
        });
        expect(p.copies, isEmpty);
      },
    );

    test('without deleteExtras, extras are left alone', () async {
      final p = await plan(
        {
          '/': [_f('a', 1)],
        },
        {
          '/': [_f('a', 1), _f('extra', 2)],
        },
      );
      expect(p.isEmpty, isTrue);
    });

    test(
      'resolves a type conflict (dst file where src has a folder)',
      () async {
        final p = await plan(
          {
            '/': [_d('x')],
            '/x': [_f('inside', 1)],
          },
          {
            '/': [_f('x', 5)],
          }, // x is a file on the destination
        );
        expect(p.deletes.single.dstPath, '/x');
        expect(p.deletes.single.isDir, isFalse);
        expect(p.mkdirs.map((m) => m.dstPath), ['/x']);
        expect(p.copies.single.dstPath, '/x/inside');
      },
    );
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
      // A nested folder present on both sides with a differing file inside —
      // the shallow planner would have missed this.
      await Directory(p.join(l.path, 'sub')).create();
      await Directory(p.join(r.path, 'sub')).create();
      await File(p.join(l.path, 'sub', 'deep.txt')).writeAsString('NEW-LONGER');
      await File(p.join(r.path, 'sub', 'deep.txt')).writeAsString('OLD');
      await File(
        p.join(r.path, 'b.txt'),
      ).writeAsString('B'); // extra on the right
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

      final plan = await s.mirrorPlan(leftToRight: true, deleteExtras: true);
      expect(plan.copies.map((c) => c.name).toSet(), {
        'a.txt',
        'deep.txt',
      }); // common identical, deep differs
      expect(plan.deletes.map((d) => d.dstPath), [p.join(r.path, 'b.txt')]);
      await s.runMirror(plan);

      final copied = File(p.join(r.path, 'a.txt'));
      final deep = File(p.join(r.path, 'sub', 'deep.txt'));
      for (
        var i = 0;
        i < 200 &&
            !(copied.existsSync() && await deep.readAsString() == 'NEW-LONGER');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await copied.readAsString(), 'A');
      expect(
        await deep.readAsString(),
        'NEW-LONGER',
      ); // nested difference mirrored
      expect(
        File(p.join(r.path, 'b.txt')).existsSync(),
        isFalse,
      ); // extra deleted
      expect(await File(p.join(r.path, 'common.txt')).readAsString(), 'X');
    });

    test('reports prep failures instead of silently swallowing them', () async {
      final c = makeContainer();
      final s = c.read(sessionsProvider.notifier);
      final l = await Directory.systemTemp.createTemp('mir_fl');
      final r = await Directory.systemTemp.createTemp('mir_fr');
      addTearDown(() => l.delete(recursive: true));
      addTearDown(() => r.delete(recursive: true));

      s.leftPane
        ..backend = LocalBackend()
        ..path = l.path;
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = r.path;

      // A delete of a path that doesn't exist fails — runMirror must surface it.
      final plan = MirrorPlan(
        leftToRight: true,
        deletes: [MirrorDelete(p.join(r.path, 'ghost.txt'), false)],
      );
      await s.runMirror(plan);

      final toast = c.read(toastsProvider).last;
      expect(toast.kind, ToastKind.error);
      expect(toast.title, contains('problem'));
      expect(toast.detail, isNotNull);
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
