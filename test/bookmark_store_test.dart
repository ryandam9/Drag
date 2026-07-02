import 'package:drag/data/bookmark_store.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookmarkStore', () {
    test('add / load (newest first) / remove', () async {
      final store = await BookmarkStore.open(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.add(
        const Bookmark(connId: null, path: '/home/a', label: 'a'),
      );
      final id2 = await store.add(
        const Bookmark(connId: 's3a', path: 's3://b/x', label: 'x'),
      );

      var all = await store.load();
      expect(all.length, 2);
      expect(all.first.path, 's3://b/x'); // newest first

      await store.remove(id2);
      all = await store.load();
      expect(all.map((b) => b.path), ['/home/a']);
    });
  });

  group('BookmarksNotifier', () {
    test('toggle adds then removes, persisting to the store', () async {
      final store = await BookmarkStore.open(inMemoryDatabasePath);
      addTearDown(store.close);
      final c = makeContainer(
        overrides: [bookmarkStoreProvider.overrideWithValue(store)],
      );
      final n = c.read(bookmarksProvider.notifier);

      await n.toggle(null, '/home/a', 'a');
      expect(n.isBookmarked(null, '/home/a'), isTrue);
      expect(c.read(bookmarksProvider).length, 1);
      expect((await store.load()).length, 1); // persisted

      await n.toggle(null, '/home/a', 'a'); // toggle off
      expect(n.isBookmarked(null, '/home/a'), isFalse);
      expect((await store.load()).length, 0);
    });

    test('add is idempotent and forEndpoint filters by connection', () async {
      final c = makeContainer();
      final n = c.read(bookmarksProvider.notifier);
      await n.add('s3a', 's3://b/x', 'x');
      await n.add('s3a', 's3://b/x', 'x'); // duplicate ignored
      await n.add(null, '/home', 'home');

      expect(c.read(bookmarksProvider).length, 2);
      expect(n.forEndpoint('s3a').map((b) => b.path), ['s3://b/x']);
      expect(n.forEndpoint(null).map((b) => b.path), ['/home']);
    });

    test('restores bookmarks loaded at startup', () {
      final c = makeContainer(
        overrides: [
          initialBookmarksProvider.overrideWithValue(const [
            Bookmark(connId: null, path: '/p', label: 'p'),
          ]),
        ],
      );
      expect(c.read(bookmarksProvider).single.path, '/p');
    });
  });
}
