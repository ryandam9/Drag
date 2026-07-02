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
  final l = {
    for (final i in left)
      if (!i.isParent) i.name: i,
  };
  final r = {
    for (final i in right)
      if (!i.isParent) i.name: i,
  };

  Map<String, CompareMark> marksFor(
    Map<String, FileItem> a,
    Map<String, FileItem> b,
  ) {
    final out = <String, CompareMark>{};
    for (final e in a.entries) {
      final other = b[e.key];
      out[e.key] = other == null
          ? CompareMark.onlyHere
          : (entriesDiffer(e.value, other)
                ? CompareMark.differs
                : CompareMark.same);
    }
    return out;
  }

  return PaneDiff(marksFor(l, r), marksFor(r, l));
}

/// How a mirror decides two same-named files differ.
enum CompareMode {
  /// Byte count only (cheap; default).
  size,

  /// Byte count and last-modified timestamp.
  sizeAndTime,

  /// Content hash — exact but reads both files, so it's opt-in.
  checksum,
}

extension CompareModeLabel on CompareMode {
  String get label => switch (this) {
    CompareMode.size => 'Size',
    CompareMode.sizeAndTime => 'Size + modified',
    CompareMode.checksum => 'Checksum (slow)',
  };
}

/// Computes a content hash for the file at [path] on one side (used only by
/// [CompareMode.checksum]).
typedef MirrorHasher = Future<String> Function(String path);

/// A cooperative cancel flag for an in-progress [planMirrorRecursive].
class MirrorCancel {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Lists the entries of a directory at [path] on one side of a mirror.
typedef MirrorLister = Future<List<FileItem>> Function(String path);

/// Joins a child [name] onto a directory [path], backend-aware (e.g. S3's
/// trailing-slash folders). Matches `StorageBackend.childPath`.
typedef MirrorJoin = String Function(String path, String name, bool isDir);

/// One file to copy from [srcPath] to [dstPath] (because it's missing on, or
/// differs from, the destination).
class MirrorCopy {
  final String srcPath;
  final String dstPath;
  final String name;
  final int sizeBytes;
  const MirrorCopy({
    required this.srcPath,
    required this.dstPath,
    required this.name,
    required this.sizeBytes,
  });
}

/// A destination directory to create so the tree structure exists before files
/// land in it (also covers empty source folders).
class MirrorMkdir {
  final String dstPath;
  const MirrorMkdir(this.dstPath);
}

/// A destination entry to remove — either a destination-only "extra" (when
/// `deleteExtras`) or an entry whose type blocks the source (a file where a
/// folder must go, or vice-versa).
class MirrorDelete {
  final String dstPath;
  final bool isDir;
  const MirrorDelete(this.dstPath, this.isDir);
}

/// A planned recursive mirror of one tree onto another. [deletes] run first,
/// then [mkdirs] (parents before children), then the file [copies].
class MirrorPlan {
  final bool leftToRight;
  final List<MirrorMkdir> mkdirs;
  final List<MirrorCopy> copies;
  final List<MirrorDelete> deletes;

  /// True when planning stopped early because a limit (max depth / max files)
  /// was hit or the user cancelled — so the plan is partial.
  final bool truncated;

  const MirrorPlan({
    required this.leftToRight,
    this.mkdirs = const [],
    this.copies = const [],
    this.deletes = const [],
    this.truncated = false,
  });

  bool get isEmpty => mkdirs.isEmpty && copies.isEmpty && deletes.isEmpty;
  int get fileCount => copies.length;
  int get dirCount => mkdirs.length;
  int get deleteCount => deletes.length;
  int get totalBytes => copies.fold(0, (sum, c) => sum + c.sizeBytes);
}

/// Recursively walks the source and destination trees (rooted at [srcRoot] /
/// [dstRoot]) and plans the operations to make the destination match the
/// source: directories to create, files to copy (missing, or different by
/// size), and — when [deleteExtras] — destination-only entries to remove.
/// Type conflicts (a file where the source has a folder, or vice-versa) are
/// always resolved by removing the blocker, regardless of [deleteExtras].
/// [mode] picks how same-named files are compared (size / size+time /
/// checksum). [hashSrc]/[hashDst] are required for [CompareMode.checksum].
/// Planning can be bounded and observed: [cancel] stops it, [onScanned] reports
/// entries examined, and [maxDepth]/[maxFiles] cap the walk on huge trees. When
/// any bound (or cancellation) cuts the walk short the result is a partial plan
/// with [MirrorPlan.truncated] set.
Future<MirrorPlan> planMirrorRecursive({
  required String srcRoot,
  required String dstRoot,
  required MirrorLister listSrc,
  required MirrorLister listDst,
  required MirrorJoin joinSrc,
  required MirrorJoin joinDst,
  required bool leftToRight,
  required bool deleteExtras,
  CompareMode mode = CompareMode.size,
  MirrorHasher? hashSrc,
  MirrorHasher? hashDst,
  MirrorCancel? cancel,
  void Function(int scanned)? onScanned,
  int? maxDepth,
  int? maxFiles,
}) async {
  final mkdirs = <MirrorMkdir>[];
  final copies = <MirrorCopy>[];
  final deletes = <MirrorDelete>[];
  var scanned = 0;
  var stopped = false;

  // Whether a same-named source/destination *file* pair differs, per [mode].
  Future<bool> fileDiffers(
    FileItem s,
    FileItem d,
    String sPath,
    String dPath,
  ) async {
    if ((d.sizeBytes ?? 0) != (s.sizeBytes ?? 0)) {
      return true; // size always wins
    }
    if (mode == CompareMode.sizeAndTime) return s.modified != d.modified;
    if (mode == CompareMode.checksum && hashSrc != null && hashDst != null) {
      return (await hashSrc(sPath)) != (await hashDst(dPath));
    }
    return false;
  }

  Future<void> walk(String sDir, String dDir, bool dstExists, int depth) async {
    if (stopped || (cancel?.cancelled ?? false)) {
      stopped = true;
      return;
    }
    if (maxDepth != null && depth > maxDepth) return;
    final srcEntries = [
      for (final e in await listSrc(sDir))
        if (!e.isParent) e,
    ];
    final dstEntries = dstExists
        ? [
            for (final e in await listDst(dDir))
              if (!e.isParent) e,
          ]
        : <FileItem>[];
    final dstByName = {for (final e in dstEntries) e.name: e};
    final srcNames = {for (final e in srcEntries) e.name};

    for (final s in srcEntries) {
      if (cancel?.cancelled ?? false) {
        stopped = true;
        return;
      }
      if (maxFiles != null && scanned >= maxFiles) {
        stopped = true;
        return;
      }
      if (++scanned % 200 == 0) onScanned?.call(scanned);

      final d = dstByName[s.name];
      if (s.isDir) {
        final sPath = joinSrc(sDir, s.name, true);
        final dPath = joinDst(dDir, s.name, true);
        if (d != null && !d.isDir) {
          // A file blocks the folder — remove it, then build the subtree fresh.
          deletes.add(MirrorDelete(joinDst(dDir, s.name, false), false));
          mkdirs.add(MirrorMkdir(dPath));
          await walk(sPath, dPath, false, depth + 1);
        } else if (d == null) {
          mkdirs.add(MirrorMkdir(dPath));
          await walk(sPath, dPath, false, depth + 1);
        } else {
          await walk(sPath, dPath, true, depth + 1);
        }
      } else {
        final sPath = joinSrc(sDir, s.name, false);
        final dPath = joinDst(dDir, s.name, false);
        final size = s.sizeBytes ?? 0;
        if (d != null && d.isDir) {
          // A folder blocks the file — remove it, then copy.
          deletes.add(MirrorDelete(joinDst(dDir, s.name, true), true));
          copies.add(
            MirrorCopy(
              srcPath: sPath,
              dstPath: dPath,
              name: s.name,
              sizeBytes: size,
            ),
          );
        } else if (d == null || await fileDiffers(s, d, sPath, dPath)) {
          copies.add(
            MirrorCopy(
              srcPath: sPath,
              dstPath: dPath,
              name: s.name,
              sizeBytes: size,
            ),
          );
        }
      }
    }

    if (deleteExtras && dstExists) {
      for (final d in dstEntries) {
        if (!srcNames.contains(d.name)) {
          deletes.add(MirrorDelete(joinDst(dDir, d.name, d.isDir), d.isDir));
        }
      }
    }
  }

  await walk(srcRoot, dstRoot, true, 0);
  onScanned?.call(scanned);
  return MirrorPlan(
    leftToRight: leftToRight,
    mkdirs: mkdirs,
    copies: copies,
    deletes: deletes,
    truncated: stopped,
  );
}
