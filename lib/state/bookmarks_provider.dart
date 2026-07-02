import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookmark_store.dart';
import 'providers.dart';

export '../data/bookmark_store.dart' show Bookmark;

/// Owns the saved path bookmarks, persisting changes to [BookmarkStore].
class BookmarksNotifier extends Notifier<List<Bookmark>> {
  BookmarkStore? get _store => ref.read(bookmarkStoreProvider);

  @override
  List<Bookmark> build() =>
      List.of(ref.read(initialBookmarksProvider) ?? const []);

  /// Bookmarks for one endpoint ([connId] null = Local).
  List<Bookmark> forEndpoint(String? connId) =>
      state.where((b) => b.connId == connId).toList();

  bool isBookmarked(String? connId, String path) =>
      state.any((b) => b.connId == connId && b.path == path);

  /// Bookmark [path] on [connId] (no-op if it already exists).
  Future<void> add(String? connId, String path, String label) async {
    if (isBookmarked(connId, path)) return;
    final b = Bookmark(connId: connId, path: path, label: label);
    final id = await _store?.add(b);
    state = [if (id != null) b.withId(id) else b, ...state];
  }

  Future<void> remove(Bookmark b) async {
    if (b.id != null) await _store?.remove(b.id!);
    state = state.where((x) => !identical(x, b) && x.id != b.id).toList();
  }

  /// Toggle the bookmark for ([connId], [path]).
  Future<void> toggle(String? connId, String path, String label) async {
    final existing = state
        .where((b) => b.connId == connId && b.path == path)
        .toList();
    if (existing.isEmpty) {
      await add(connId, path, label);
    } else {
      for (final b in existing) {
        await remove(b);
      }
    }
  }
}

final bookmarksProvider = NotifierProvider<BookmarksNotifier, List<Bookmark>>(
  BookmarksNotifier.new,
);
