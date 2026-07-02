import 'dart:io';

import 'package:drag/fs/file_search.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('matchesQuery', () {
    test('substring is case-insensitive', () {
      expect(matchesQuery('Report.LOG', 'log'), isTrue);
      expect(matchesQuery('notes.txt', 'log'), isFalse);
      expect(matchesQuery('anything', ''), isFalse);
    });

    test('glob with * / ?', () {
      expect(matchesQuery('a.log', '*.log'), isTrue);
      expect(matchesQuery('a.txt', '*.log'), isFalse);
      expect(matchesQuery('a1.log', 'a?.log'), isTrue);
      expect(matchesQuery('a12.log', 'a?.log'), isFalse);
    });
  });

  group('searchTree (LocalBackend)', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('search');
      Directory(p.join(root.path, 'sub')).createSync();
      Directory(p.join(root.path, 'sub', 'deep')).createSync();
      await File(p.join(root.path, 'a.log')).writeAsString('x');
      await File(p.join(root.path, 'note.md')).writeAsString('x');
      await File(p.join(root.path, 'sub', 'b.txt')).writeAsString('x');
      await File(p.join(root.path, 'sub', 'deep', 'c.log')).writeAsString('x');
    });
    tearDown(() => root.delete(recursive: true));

    test('finds nested matches by substring', () async {
      final hits = await searchTree(LocalBackend(), root.path, 'log').toList();
      expect(hits.map((h) => h.name).toSet(), {'a.log', 'c.log'});
      // Paths are full and point at the right depth.
      expect(
        hits.firstWhere((h) => h.name == 'c.log').path,
        endsWith(p.join('deep', 'c.log')),
      );
    });

    test('glob matches', () async {
      final hits = await searchTree(
        LocalBackend(),
        root.path,
        '*.log',
      ).toList();
      expect(hits.map((h) => h.name).toSet(), {'a.log', 'c.log'});
    });

    test('cancellation stops the walk', () async {
      final cancel = SearchCancel()..cancel();
      final hits = await searchTree(
        LocalBackend(),
        root.path,
        'log',
        cancel: cancel,
      ).toList();
      expect(hits, isEmpty);
    });

    test('maxHits caps the results', () async {
      for (var i = 0; i < 5; i++) {
        await File(p.join(root.path, 'm$i.log')).writeAsString('x');
      }
      final hits = await searchTree(
        LocalBackend(),
        root.path,
        'log',
        maxHits: 2,
      ).toList();
      expect(hits.length, 2);
    });

    test('maxDepth bounds how deep the walk descends', () async {
      // Depth 0 → only the root level is scanned, so the nested sub/deep/c.log
      // is never reached; a.log (at the root) still matches.
      final shallow = await searchTree(
        LocalBackend(),
        root.path,
        '*.log',
        maxDepth: 0,
      ).toList();
      expect(shallow.map((h) => h.name).toSet(), {'a.log'});
      // Unbounded reaches the deep match too.
      final deep = await searchTree(
        LocalBackend(),
        root.path,
        '*.log',
      ).toList();
      expect(deep.map((h) => h.name).toSet(), {'a.log', 'c.log'});
    });

    test('maxScanned bounds total work and stops descending', () async {
      // BFS scans the whole root directory (a.log, note.md, sub) before
      // descending; with maxScanned: 1 it stops right after, so the deep
      // sub/deep/c.log is never examined.
      final hits = await searchTree(
        LocalBackend(),
        root.path,
        'log',
        maxScanned: 1,
      ).toList();
      expect(hits.map((h) => h.name).toSet(), {'a.log'});
    });

    test('timeout ends the walk', () async {
      // A zero (already-elapsed) timeout returns before scanning anything.
      final hits = await searchTree(
        LocalBackend(),
        root.path,
        'log',
        timeout: Duration.zero,
      ).toList();
      expect(hits, isEmpty);
    });
  });
}
