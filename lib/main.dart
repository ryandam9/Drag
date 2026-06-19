import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_shell.dart';
import 'data/connection_store.dart';
import 'data/history_db.dart';
import 'data/settings_store.dart';
import 'models/connection.dart';
import 'state/app_state.dart';
import 'state/scopes.dart';
import 'theme.dart';

/// Desktop platforms where native window management applies.
bool get _isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

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

  SettingsStore? settingsStore;
  AppSettings? settings;
  try {
    settingsStore = await SettingsStore.open();
    settings = await settingsStore.load();
  } catch (_) {
    settingsStore = null;
    settings = null;
  }

  // Apply the persisted accent to the global palette before the first frame.
  if (settings != null) {
    FsColors.accent = Color(settings.accentValue);
    FsColors.accentHi = FsColors.highlightFor(FsColors.accent);
  }

  // Restore window size/position (desktop only — no-op on other platforms).
  if (_isDesktop) {
    try {
      await windowManager.ensureInitialized();
      final s = settings;
      final size = (s?.windowWidth != null && s?.windowHeight != null)
          ? Size(s!.windowWidth!, s.windowHeight!)
          : const Size(1320, 860);
      await windowManager.waitUntilReadyToShow(
        WindowOptions(size: size, title: 'Drag'),
        () async {
          if (s?.windowX != null && s?.windowY != null) {
            await windowManager.setPosition(Offset(s!.windowX!, s.windowY!));
          } else {
            await windowManager.center();
          }
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (_) {
      // Headless / unsupported environments: carry on without window control.
    }
  }

  runApp(DragApp(
    history: history,
    connectionStore: connectionStore,
    settingsStore: settingsStore,
    settings: settings,
    connections: connections,
  ));
}

class DragApp extends StatefulWidget {
  final HistoryRepository? history;
  final ConnectionStore? connectionStore;
  final SettingsStore? settingsStore;
  final AppSettings? settings;
  final List<Connection>? connections;
  const DragApp({
    super.key,
    this.history,
    this.connectionStore,
    this.settingsStore,
    this.settings,
    this.connections,
  });

  @override
  State<DragApp> createState() => _DragAppState();
}

class _DragAppState extends State<DragApp> with WindowListener {
  late final AppState _state = AppState(
    history: widget.history,
    connectionStore: widget.connectionStore,
    settingsStore: widget.settingsStore,
    settings: widget.settings,
    connections: widget.connections,
  );

  @override
  void initState() {
    super.initState();
    // Rebuild MaterialApp's ThemeData when the accent / font size changes.
    _state.addListener(_onStateChanged);
    if (_isDesktop) windowManager.addListener(this);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    _state.removeListener(_onStateChanged);
    _state.dispose();
    super.dispose();
  }

  // ── Persist window geometry on resize / move ──
  Future<void> _persistWindow() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      await _state.saveWindowState(
        width: size.width,
        height: size.height,
        x: pos.dx,
        y: pos.dy,
      );
    } catch (_) {/* best-effort */}
  }

  @override
  void onWindowResized() => _persistWindow();

  @override
  void onWindowMoved() => _persistWindow();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Drag',
        debugShowCheckedModeBanner: false,
        theme: buildDragTheme(),
        builder: (context, child) {
          // Scale text to the chosen UI font size (13px = baseline 1.0).
          final scale = _state.uiFontSize / 13.0;
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          );
        },
        home: AppScopes(state: _state, child: const AppShell()),
      ),
    );
  }
}
