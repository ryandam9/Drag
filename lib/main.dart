import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_shell.dart';
import 'data/connection_store.dart';
import 'data/history_db.dart';
import 'data/session_store.dart';
import 'data/settings_store.dart';
import 'models/connection.dart';
import 'state/app.dart';
import 'theme.dart';

/// Desktop platforms where native window management applies.
bool get _isDesktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

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
    connections = await connectionStore.load();
  } catch (_) {
    connectionStore = null;
    connections = null;
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

  SessionStore? sessionStore;
  SessionLayout? sessionLayout;
  try {
    sessionStore = await SessionStore.open();
    sessionLayout = await sessionStore.load();
  } catch (_) {
    sessionStore = null;
    sessionLayout = null;
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

  runApp(ProviderScope(
    overrides: [
      historyRepositoryProvider.overrideWithValue(history),
      connectionStoreProvider.overrideWithValue(connectionStore),
      settingsStoreProvider.overrideWithValue(settingsStore),
      sessionStoreProvider.overrideWithValue(sessionStore),
      initialSettingsProvider.overrideWithValue(settings),
      initialConnectionsProvider.overrideWithValue(connections),
      initialSessionLayoutProvider.overrideWithValue(sessionLayout),
    ],
    child: const DragApp(),
  ));
}

class DragApp extends ConsumerStatefulWidget {
  const DragApp({super.key});

  @override
  ConsumerState<DragApp> createState() => _DragAppState();
}

class _DragAppState extends ConsumerState<DragApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  // ── Persist window geometry on resize / move ──
  Future<void> _persistWindow() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      await ref.read(settingsProvider.notifier).saveWindowState(
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
    // Rebuild the theme + text scale when appearance settings change.
    final fontSize = ref.watch(settingsProvider.select((s) => s.uiFontSize));
    // Watch the accent so the ThemeData is rebuilt when it changes.
    ref.watch(settingsProvider.select((s) => s.accentValue));

    return MaterialApp(
      title: 'Drag',
      debugShowCheckedModeBanner: false,
      theme: buildDragTheme(),
      builder: (context, child) {
        final scale = fontSize / 13.0;
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      home: const AppShell(),
    );
  }
}
