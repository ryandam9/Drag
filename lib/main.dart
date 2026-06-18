import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  runApp(const FileSyncApp());
}

class FileSyncApp extends StatefulWidget {
  const FileSyncApp({super.key});

  @override
  State<FileSyncApp> createState() => _FileSyncAppState();
}

class _FileSyncAppState extends State<FileSyncApp> {
  final AppState _state = AppState();

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
        title: 'FileSync',
        debugShowCheckedModeBanner: false,
        theme: buildFileSyncTheme(),
        home: const AppShell(),
      ),
    );
  }
}
