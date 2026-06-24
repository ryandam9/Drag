import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/connection_store.dart';
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

  @override
  ConnectionsState build() {
    final initial = ref.read(initialConnectionsProvider);
    final list = List<Connection>.of(initial ?? const []);
    return ConnectionsState(list, list.isEmpty ? null : list.first);
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
  Future<void> save(Connection c) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    // [c] is mutated in place by the form; emit a fresh list so watchers rebuild.
    state = ConnectionsState(List.of(_list), c);
    await _store?.upsert(c, _list.indexOf(c).clamp(0, _list.length));
  }

  Future<Connection> duplicate(Connection c) async {
    final copy = Connection.fromJson(c.toJson())
      ..id = Connection.newId()
      ..name = '${c.name} (copy)';
    final idx = _list.indexOf(c);
    final next = [..._list]..insert(idx < 0 ? _list.length : idx + 1, copy);
    state = ConnectionsState(next, copy);
    await _persist();
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
  }
}

final connectionsProvider =
    NotifierProvider<ConnectionsNotifier, ConnectionsState>(ConnectionsNotifier.new);
