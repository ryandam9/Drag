import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/connection_store.dart';
import '../data/secret_store.dart';
import '../models/connection.dart';
import 'providers.dart';
import 'sessions_provider.dart';

/// The saved connections plus the one currently shown in the form.
class ConnectionsState {
  final List<Connection> connections;
  final Connection? selected;
  const ConnectionsState(this.connections, this.selected);

  ConnectionsState copyWith({List<Connection>? connections, Connection? selected}) =>
      ConnectionsState(connections ?? this.connections, selected ?? this.selected);
}

/// Owns the saved connections and the current selection, with CRUD that
/// persists to [ConnectionStore] (secrets excluded — see issue #16). The list
/// starts empty on a fresh install; the user adds their own real SFTP / S3
/// endpoints in the Connection Manager.
class ConnectionsNotifier extends Notifier<ConnectionsState> {
  ConnectionStore? get _store => ref.read(connectionStoreProvider);
  SecretStore? get _secrets => ref.read(secretStoreProvider);

  /// Completes once the startup keychain load has landed on the restored
  /// connections (immediately when there's nothing to load). Anything that
  /// persists secrets — or logs in with them — must await this first, so it
  /// can never race the load and see (or save) still-empty secret fields.
  Future<void> get secretsReady => _secretsReady;
  Future<void> _secretsReady = Future.value();

  @override
  ConnectionsState build() {
    final initial = ref.read(initialConnectionsProvider);
    final list = List<Connection>.of(initial ?? const []);
    // Lazily pull each connection's secrets out of the OS keychain and back
    // into the form, once the app is running (keychain plugins aren't ready
    // before the first frame).
    if (_secrets != null && list.isNotEmpty) {
      _secretsReady = Future.microtask(() => _loadSecrets(list));
    }
    return ConnectionsState(list, list.isEmpty ? null : list.first);
  }

  Future<void> _loadSecrets(List<Connection> list) async {
    final store = _secrets;
    if (store == null) return;
    for (final c in list) {
      if (c.id.isNotEmpty) await store.load(c);
    }
    touch(); // refresh the form with the restored secrets
  }

  List<Connection> get _list => state.connections;

  Future<void> _persist() async => _store?.replaceAll(_list);

  void select(Connection c) => state = ConnectionsState(_list, c);

  /// Re-emit the current state so watchers pick up an in-place change to a
  /// connection (e.g. its `online` flag flipping after [connect]).
  void touch() => state = ConnectionsState(List.of(_list), state.selected);

  /// Create a blank connection, select it, and persist.
  Future<Connection> create() async {
    final c = Connection(id: Connection.newId(), name: 'New connection', host: '');
    final next = [..._list, c];
    state = ConnectionsState(next, c);
    await _persist();
    return c;
  }

  /// Persist edits made to [c] in place (via the form) and refresh listeners.
  /// Non-secret fields go to SQLite; secrets go to the OS keychain.
  Future<void> save(Connection c) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    // Never persist before the startup keychain load has landed on [c] —
    // otherwise an early save could capture (and wipe) still-empty secrets.
    await secretsReady;
    // [c] is mutated in place by the form; emit a fresh list so watchers rebuild.
    state = ConnectionsState(List.of(_list), c);
    await _store?.upsert(c, _list.indexOf(c).clamp(0, _list.length));
    // An explicit Save honours emptied secret fields by clearing the keychain.
    await _secrets?.save(c, clear: true);
  }

  /// Persist [c] (record + secrets) without changing the current selection or
  /// re-emitting state. Called when the user Connects/Tests so a typed password
  /// survives a restart even if they never press Save explicitly. A connection
  /// not yet in the list (shouldn't normally happen) is skipped for the SQLite
  /// upsert but its secrets are still saved.
  Future<void> remember(Connection c) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    await secretsReady; // don't race the startup keychain load
    final idx = _list.indexOf(c);
    if (idx >= 0) await _store?.upsert(c, idx);
    await _secrets?.save(c);
  }

  Future<Connection> duplicate(Connection c) async {
    final copy = Connection.fromJson(c.toJson())
      ..id = Connection.newId()
      ..name = '${c.name} (copy)'
      // toJson drops secrets, so copy them across explicitly.
      ..password = c.password
      ..passphrase = c.passphrase
      ..secretAccessKey = c.secretAccessKey
      ..sessionToken = c.sessionToken;
    final idx = _list.indexOf(c);
    final next = [..._list]..insert(idx < 0 ? _list.length : idx + 1, copy);
    state = ConnectionsState(next, copy);
    await _persist();
    await _secrets?.save(copy);
    return copy;
  }

  Future<void> delete(Connection c) async {
    final idx = _list.indexOf(c);
    final next = [..._list]..remove(c);
    ref.read(sessionsProvider.notifier).evictBackend(c);
    final selected = identical(state.selected, c)
        ? (next.isEmpty ? null : next[idx.clamp(0, next.length - 1)])
        : state.selected;
    state = ConnectionsState(next, selected);
    await _persist();
    await _secrets?.delete(c.id);
  }
}

final connectionsProvider =
    NotifierProvider<ConnectionsNotifier, ConnectionsState>(ConnectionsNotifier.new);
