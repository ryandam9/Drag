import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/connection_store.dart';
import 'data/history_db.dart';
import 'models/connection.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open local SQLite stores (best-effort — the app still runs without them).
  HistoryRepository? history;
  try {
    history = await HistoryRepository.open();
  } catch (_) {
    history = null;
  }

  ConnectionStore? connectionStore;
  List<Connection>? connections;
  try {
    connectionStore = await ConnectionStore.open();
    connections = await connectionStore.loadOrSeed();
  } catch (_) {
    connectionStore = null;
    connections = null; // fall back to in-memory seed data
  }

  runApp(DragApp(
    history: history,
    connectionStore: connectionStore,
    connections: connections,
  ));
}

class DragApp extends StatefulWidget {
  final HistoryRepository? history;
  final ConnectionStore? connectionStore;
  final List<Connection>? connections;
  const DragApp({super.key, this.history, this.connectionStore, this.connections});

  @override
  State<DragApp> createState() => _DragAppState();
}

class _DragAppState extends State<DragApp> {
  late final AppState _state = AppState(
    history: widget.history,
    connectionStore: widget.connectionStore,
    connections: widget.connections,
  );

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Drag',
        debugShowCheckedModeBanner: false,
        theme: buildDragTheme(),
        home: const AppShell(),
      ),
    );
  }
}
