import '../models/file_item.dart';

/// How one pane's entry relates to the matching entry in the other pane.
enum CompareMark {
  /// Present here but not in the other pane.
  onlyHere,

  /// Present in both, but the contents differ (size, or file-vs-folder).
  differs,

  /// Present in both and identical (by the cheap size/kind check).
  same,
}

/// The per-name comparison marks for each pane (keyed by entry name).
class PaneDiff {
  final Map<String, CompareMark> left;
  final Map<String, CompareMark> right;
  const PaneDiff(this.left, this.right);

  int _count(Map<String, CompareMark> m, CompareMark mark) =>
      m.values.where((v) => v == mark).length;

  /// Entries only on the left / only on the right.
  int get onlyLeft => _count(left, CompareMark.onlyHere);
  int get onlyRight => _count(right, CompareMark.onlyHere);

  /// Entries present on both sides but differing (counted once).
  int get differing => _count(left, CompareMark.differs);

  bool get isIdentical => onlyLeft == 0 && onlyRight == 0 && differing == 0;
}

/// Two entries of the same name "differ" when one is a folder and the other a
/// file, or when two files have different sizes. (Folders with the same name
/// are treated as matching at this level — deep compare is out of scope here.)
bool entriesDiffer(FileItem a, FileItem b) {
  if (a.isDir != b.isDir) return true;
  if (!a.isDir && (a.sizeBytes ?? 0) != (b.sizeBytes ?? 0)) return true;
  return false;
}

/// Compares two directory listings by name, producing a [CompareMark] for every
/// entry on each side (parent ".." entries are ignored).
PaneDiff comparePanes(List<FileItem> left, List<FileItem> right) {
  final l = {for (final i in left) if (!i.isParent) i.name: i};
  final r = {for (final i in right) if (!i.isParent) i.name: i};

  Map<String, CompareMark> marksFor(Map<String, FileItem> a, Map<String, FileItem> b) {
    final out = <String, CompareMark>{};
    for (final e in a.entries) {
      final other = b[e.key];
      out[e.key] = other == null
          ? CompareMark.onlyHere
          : (entriesDiffer(e.value, other) ? CompareMark.differs : CompareMark.same);
    }
    return out;
  }

  return PaneDiff(marksFor(l, r), marksFor(r, l));
}

/// A planned mirror of one pane onto the other: the entries to copy (those that
/// are missing or differ on the destination) and, optionally, the destination
/// entries to delete (those that exist only on the destination).
class MirrorPlan {
  final bool leftToRight;
  final List<FileItem> copy;
  final List<FileItem> delete;
  const MirrorPlan({required this.leftToRight, required this.copy, required this.delete});

  bool get isEmpty => copy.isEmpty && delete.isEmpty;
  int get fileCopies => copy.where((e) => !e.isDir).length;
  int get folderCopies => copy.where((e) => e.isDir).length;
}

/// Builds a [MirrorPlan] to make [dstItems] match [srcItems]: copy everything
/// that's missing or different on the destination, and (if [deleteExtras])
/// remove destination entries that don't exist on the source.
MirrorPlan planMirror(
  List<FileItem> srcItems,
  List<FileItem> dstItems, {
  required bool leftToRight,
  required bool deleteExtras,
}) {
  final diff = comparePanes(srcItems, dstItems);
  final copy = <FileItem>[];
  for (final i in srcItems) {
    if (i.isParent) continue;
    final m = diff.left[i.name];
    if (m == CompareMark.onlyHere || m == CompareMark.differs) copy.add(i);
  }
  final delete = <FileItem>[];
  if (deleteExtras) {
    for (final i in dstItems) {
      if (i.isParent) continue;
      if (diff.right[i.name] == CompareMark.onlyHere) delete.add(i);
    }
  }
  return MirrorPlan(leftToRight: leftToRight, copy: copy, delete: delete);
}
