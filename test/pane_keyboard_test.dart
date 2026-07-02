import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/state/pane_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pane with a `..` row followed by [names] (a trailing `/` marks a folder),
/// no real backend listing required.
PaneController _pane(List<String> names) {
  final pc = PaneController(backend: LocalBackend(), onChanged: () {});
  pc.items = [
    const FileItem(name: '..', isDir: true),
    for (final n in names)
      FileItem(
        name: n.endsWith('/') ? n.substring(0, n.length - 1) : n,
        isDir: n.endsWith('/'),
      ),
  ];
  return pc;
}

void main() {
  group('PaneController keyboard navigation', () {
    test('moveSelection from nothing lands on first (down) or last (up)', () {
      final down = _pane(['a', 'b', 'c']);
      down.moveSelection(1);
      expect(down.selectedIndex, 0);

      final up = _pane(['a', 'b', 'c']);
      up.moveSelection(-1);
      expect(up.selectedIndex, up.items.length - 1);
    });

    test('moveSelection steps and clamps at both ends', () {
      final p = _pane(['a', 'b', 'c']); // indices 0=.. 1=a 2=b 3=c
      p.select(1);
      p.moveSelection(1);
      expect(p.selectedIndex, 2);
      p.moveSelection(-1);
      expect(p.selectedIndex, 1);
      p.moveSelection(-5); // clamp to top
      expect(p.selectedIndex, 0);
      p.moveSelection(99); // clamp to bottom
      expect(p.selectedIndex, p.items.length - 1);
    });

    test(
      'moveSelection keeps a single selection (no leftover multi-select)',
      () {
        final p = _pane(['a', 'b', 'c']);
        p.select(1);
        p.toggleSelect(2); // now {1,2}
        p.moveSelection(1);
        expect(p.selection, {p.selectedIndex});
      },
    );

    test('selectEdge jumps to first / last', () {
      final p = _pane(['a', 'b', 'c']);
      p.selectEdge(last: true);
      expect(p.selectedIndex, p.items.length - 1);
      p.selectEdge(last: false);
      expect(p.selectedIndex, 0);
    });

    test('empty listing is a no-op', () {
      final p = _pane([]);
      p.items = const [];
      p.moveSelection(1);
      p.selectEdge(last: true);
      expect(p.selectedIndex, isNull);
      expect(p.typeAhead('a'), isFalse);
    });

    group('typeAhead', () {
      test('jumps to the first matching name and skips ".."', () {
        final p = _pane(['apple', 'banana', 'avocado']);
        expect(p.typeAhead('a'), isTrue);
        expect(p.items[p.selectedIndex!].name, 'apple');
      });

      test('a repeated single letter cycles through matches', () {
        final p = _pane(['apple', 'banana', 'avocado']);
        p.typeAhead('a'); // apple
        p.typeAhead('a'); // avocado
        expect(p.items[p.selectedIndex!].name, 'avocado');
        p.typeAhead('a'); // wraps back to apple
        expect(p.items[p.selectedIndex!].name, 'apple');
      });

      test(
        'a longer prefix stays on the current row when it still matches',
        () {
          final p = _pane(['report.txt', 'readme.md', 'recipe.doc']);
          p.typeAhead('r'); // report.txt (first match)
          final at = p.selectedIndex;
          expect(p.typeAhead('re'), isTrue);
          expect(p.selectedIndex, at, reason: 'report still matches "re"');
          expect(p.typeAhead('rec'), isTrue);
          expect(p.items[p.selectedIndex!].name, 'recipe.doc');
        },
      );

      test('is case-insensitive and returns false with no match', () {
        final p = _pane(['Report.txt', 'notes.md']);
        expect(p.typeAhead('rep'), isTrue);
        expect(p.items[p.selectedIndex!].name, 'Report.txt');
        expect(p.typeAhead('zzz'), isFalse);
      });
    });
  });
}
