import 'dart:io';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/state/pane_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileItem _f(
  String name, {
  bool dir = false,
  int? size,
  String modified = '',
  String perms = '',
}) => FileItem(
  name: name,
  isDir: dir,
  sizeBytes: size,
  modified: modified,
  perms: perms,
);

void main() {
  group('sortItems', () {
    final items = [
      const FileItem(name: '..', isDir: true),
      _f('zeta', dir: true),
      _f('alpha', dir: true),
      _f('b.txt', size: 100, modified: '2025-01-02  00:00', perms: 'rw-'),
      _f('a.txt', size: 300, modified: '2025-01-01  00:00', perms: 'rwx'),
      _f('c.txt', size: 200, modified: '2025-01-03  00:00', perms: 'r--'),
    ];

    test('name ascending keeps ".." first and dirs before files', () {
      final s = sortItems(items, SortKey.name, true);
      expect(s.first.name, '..');
      expect(s.map((e) => e.name).toList(), [
        '..',
        'alpha',
        'zeta',
        'a.txt',
        'b.txt',
        'c.txt',
      ]);
    });

    test('descending flips within groups but keeps .. and dirs pinned', () {
      final s = sortItems(items, SortKey.name, false);
      expect(s.first.name, '..'); // never moves
      expect(s[1].name, 'zeta'); // dirs still before files, but reversed
      expect(s[2].name, 'alpha');
      expect(s.sublist(3).map((e) => e.name), ['c.txt', 'b.txt', 'a.txt']);
    });

    test('size sort orders files by bytes (dirs grouped first)', () {
      final asc = sortItems(
        items,
        SortKey.size,
        true,
      ).where((e) => !e.isDir).map((e) => e.name).toList();
      expect(asc, ['b.txt', 'c.txt', 'a.txt']); // 100, 200, 300
    });

    test('modified sort uses the lexical timestamp (chronological)', () {
      final asc = sortItems(
        items,
        SortKey.modified,
        true,
      ).where((e) => !e.isDir).map((e) => e.name).toList();
      expect(asc, ['a.txt', 'b.txt', 'c.txt']);
    });
  });

  group('PaneController filter & sort', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('view');
      await File(p.join(dir.path, 'apple.txt')).writeAsString('a');
      await File(p.join(dir.path, 'banana.log')).writeAsString('bb');
      await File(p.join(dir.path, 'cherry.txt')).writeAsString('ccc');
      await Directory(p.join(dir.path, 'docs')).create();
    });
    tearDown(() => dir.delete(recursive: true));

    PaneController pane() =>
        PaneController(backend: LocalBackend(), onChanged: () {})
          ..path = dir.path;

    test('setFilter narrows the listing live (parent kept)', () async {
      final pc = pane();
      await pc.refresh();
      pc.setFilter('rry'); // matches cherry
      expect(pc.items.where((e) => !e.isParent).map((e) => e.name), [
        'cherry.txt',
      ]);
      pc.setFilter('');
      expect(pc.items.where((e) => !e.isParent).length, 4); // 3 files + docs
    });

    test('setSort toggles direction on repeat and clears selection', () async {
      final pc = pane();
      await pc.refresh();
      pc.select(1);
      pc.setSort(SortKey.name);
      expect(pc.sortKey, SortKey.name);
      expect(
        pc.sortAscending,
        isFalse,
      ); // name was the default; repeating flips
      expect(pc.selection, isEmpty);
      pc.setSort(SortKey.size);
      expect(pc.sortKey, SortKey.size);
      expect(pc.sortAscending, isTrue); // a new column resets to ascending
    });
  });

  group('PaneController.goUpLevels', () {
    test('walks up multiple directories at once', () async {
      final root = await Directory.systemTemp.createTemp('levels');
      addTearDown(() => root.delete(recursive: true));
      final deep = Directory(p.join(root.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);
      final pc = PaneController(backend: LocalBackend(), onChanged: () {})
        ..path = deep.path;
      await pc.refresh();
      await pc.goUpLevels(2); // c -> b -> a
      expect(pc.path, p.join(root.path, 'a'));
      await pc.goUpLevels(0); // no-op
      expect(pc.path, p.join(root.path, 'a'));
    });
  });
}
