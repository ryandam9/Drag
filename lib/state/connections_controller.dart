import 'package:flutter/material.dart';

import '../data/connection_store.dart';
import '../data/mock_data.dart';
import '../models/connection.dart';

/// Owns the list of saved connections and the current selection, with CRUD that
/// persists to [ConnectionStore] (secrets excluded — see issue #16).
/// [onRemoved] lets the sessions layer drop any cached backend for a deleted
/// connection.
class ConnectionsController extends ChangeNotifier {
  ConnectionsController({
    ConnectionStore? store,
    List<Connection>? initial,
    this.onRemoved,
  })
      // ignore: prefer_initializing_formals
      : _store = store {
    if (initial != null) {
      connections
        ..clear()
        ..addAll(initial);
    }
    selected = connections.first;
  }

  final ConnectionStore? _store;
  final void Function(Connection removed)? onRemoved;

  final List<Connection> connections = buildConnections();
  late Connection selected;

  bool _disposed = false;
  bool get hasStore => _store != null;

  Future<void> _persist() async => _store?.replaceAll(connections);

  void select(Connection c) {
    selected = c;
    _notify();
  }

  /// Create a blank connection, select it, and persist.
  Future<Connection> create() async {
    final c = Connection(id: Connection.newId(), name: 'New connection', host: '');
    connections.add(c);
    selected = c;
    _notify();
    await _persist();
    return c;
  }

  /// Persist edits made to [c] (in place via the form).
  Future<void> save(Connection c) async {
    if (c.id.isEmpty) c.id = Connection.newId();
    await _store?.upsert(c, connections.indexOf(c).clamp(0, connections.length));
    _notify();
  }

  Future<Connection> duplicate(Connection c) async {
    final copy = Connection.fromJson(c.toJson())
      ..id = Connection.newId()
      ..name = '${c.name} (copy)';
    final idx = connections.indexOf(c);
    connections.insert(idx < 0 ? connections.length : idx + 1, copy);
    selected = copy;
    _notify();
    await _persist();
    return copy;
  }

  Future<void> delete(Connection c) async {
    final idx = connections.indexOf(c);
    connections.remove(c);
    onRemoved?.call(c);
    if (connections.isEmpty) {
      connections.add(Connection(id: Connection.newId(), name: 'New connection'));
    }
    if (identical(selected, c)) {
      selected = connections[idx.clamp(0, connections.length - 1)];
    }
    _notify();
    await _persist();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
