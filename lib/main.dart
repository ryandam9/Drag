import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/history_db.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open the local SQLite history database (best-effort — the app still runs
  // without it, the dashboard just shows "unavailable").
  HistoryRepository? history;
  try {
    history = await HistoryRepository.open();
  } catch (_) {
    history = null;
  }

  runApp(DragApp(history: history));
}

class DragApp extends StatefulWidget {
  final HistoryRepository? history;
  const DragApp({super.key, this.history});

  @override
  State<DragApp> createState() => _DragAppState();
}

class _DragAppState extends State<DragApp> {
  late final AppState _state = AppState(history: widget.history);

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
