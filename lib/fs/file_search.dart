import '../models/file_item.dart';
import 'storage_backend.dart';

/// One match from a recursive [searchTree].
class SearchHit {
  final String name;
  final String path; // full backend path
  final bool isDir;
  final int? sizeBytes;
  const SearchHit({required this.name, required this.path, required this.isDir, this.sizeBytes});
}

/// A cancellation flag shared with a running [searchTree].
class SearchCancel {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// True if [name] matches [query]: a glob (when it contains `*`/`?`) or a
/// case-insensitive substring otherwise.
bool matchesQuery(String name, String query) {
  if (query.isEmpty) return false;
  final q = query.toLowerCase();
  final n = name.toLowerCase();
  if (q.contains('*') || q.contains('?')) return _glob(q).hasMatch(n);
  return n.contains(q);
}

RegExp _glob(String pattern) {
  final sb = StringBuffer('^');
  for (final ch in pattern.split('')) {
    switch (ch) {
      case '*':
        sb.write('.*');
      case '?':
        sb.write('.');
      default:
        sb.write(RegExp.escape(ch));
    }
  }
  sb.write(r'$');
  return RegExp(sb.toString());
}

/// Walks [backend] from [root] breadth-first, yielding every entry whose name
/// matches [query]. Stops early on [cancel] or after [maxHits] matches.
/// [onScanned] reports how many entries have been examined so far.
Stream<SearchHit> searchTree(
  StorageBackend backend,
  String root,
  String query, {
  SearchCancel? cancel,
  void Function(int scanned)? onScanned,
  int maxHits = 2000,
}) async* {
  final queue = <String>[root];
  var scanned = 0;
  var hits = 0;
  while (queue.isNotEmpty) {
    if (cancel?.cancelled ?? false) return;
    final dir = queue.removeAt(0);
    List<FileItem> items;
    try {
      items = await backend.list(dir);
    } catch (_) {
      continue; // unreadable subtree — skip it
    }
    for (final it in items) {
      if (it.isParent) continue;
      scanned++;
      final full = backend.childPath(dir, it.name, it.isDir);
      if (matchesQuery(it.name, query)) {
        yield SearchHit(name: it.name, path: full, isDir: it.isDir, sizeBytes: it.sizeBytes);
        if (++hits >= maxHits) return;
      }
      if (it.isDir) queue.add(full);
    }
    onScanned?.call(scanned);
  }
}
