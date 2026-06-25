import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_shell.dart';
import 'data/bookmark_store.dart';
import 'data/connection_store.dart';
import 'data/history_db.dart';
import 'data/known_hosts_store.dart';
import 'data/secret_store.dart';
import 'data/session_store.dart';
import 'data/settings_store.dart';
import 'fs/host_key_verifier.dart';
import 'models/app_font.dart';
import 'platform/desktop_notifications.dart';
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

  BookmarkStore? bookmarkStore;
  List<Bookmark>? bookmarks;
  try {
    bookmarkStore = await BookmarkStore.open();
    bookmarks = await bookmarkStore.load();
  } catch (_) {
    bookmarkStore = null;
    bookmarks = null;
  }

  // Trusted SSH host keys (TOFU). Wire the global verifier so SFTP connections
  // remember keys and reject changed ones.
  KnownHostsStore? knownHostsStore;
  try {
    knownHostsStore = await KnownHostsStore.open();
    globalHostKeyVerifier = HostKeyVerifier(knownHostsStore);
  } catch (_) {
    knownHostsStore = null;
  }

  // Apply the persisted theme + fonts to the global palette before the first frame.
  if (settings != null) {
    FsColors.applyTheme(birdThemeByName(settings.themeName),
        brightness: resolveBrightness(settings.brightnessMode));
    FsType.uiFontFamily = AppFont.resolve(settings.uiFont, mono: false);
    FsType.monoFontFamily = AppFont.resolve(settings.monospaceFont, mono: true);
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
        WindowOptions(size: size, minimumSize: const Size(880, 600), title: 'Drag'),
        () async {
          await windowManager.setMinimumSize(const Size(880, 600));
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

    // OS desktop notifications (best-effort; a failure never blocks startup).
    try {
      final notifier = DesktopNotifications();
      await notifier.setup();
      gDesktopNotifications = notifier;
      gFocusWindow = () {
        windowManager.show();
        windowManager.focus();
      };
    } catch (_) {/* notifications unavailable */}
  }

  runApp(ProviderScope(
    overrides: [
      historyRepositoryProvider.overrideWithValue(history),
      connectionStoreProvider.overrideWithValue(connectionStore),
      settingsStoreProvider.overrideWithValue(settingsStore),
      sessionStoreProvider.overrideWithValue(sessionStore),
      secretStoreProvider.overrideWithValue(KeychainSecretStore()),
      bookmarkStoreProvider.overrideWithValue(bookmarkStore),
      knownHostsStoreProvider.overrideWithValue(knownHostsStore),
      initialBookmarksProvider.overrideWithValue(bookmarks),
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

class _DragAppState extends ConsumerState<DragApp> with WindowListener, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The OS flipped light/dark. In `'system'` mode, re-derive the palette and
  /// rebuild so the resolved brightness flows into the shell key below.
  @override
  void didChangePlatformBrightness() {
    if (ref.read(settingsProvider).brightnessMode == 'system') {
      ref.read(settingsProvider.notifier).reapplyGlobals();
      setState(() {});
    }
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

  // Track focus so transfer-finished notifications only fire when the app is
  // in the background.
  @override
  void onWindowFocus() => gWindowFocused = true;

  @override
  void onWindowBlur() => gWindowFocused = false;

  @override
  Widget build(BuildContext context) {
    // Rebuild the theme + text scale when appearance settings change.
    final fontSize = ref.watch(settingsProvider.select((s) => s.uiFontSize));
    // Watch the accent + theme so the ThemeData (and the whole UI) is rebuilt
    // when either changes.
    final accentValue = ref.watch(settingsProvider.select((s) => s.accentValue));
    final themeName = ref.watch(settingsProvider.select((s) => s.themeName));
    final uiFont = ref.watch(settingsProvider.select((s) => s.uiFont));
    final monoFont = ref.watch(settingsProvider.select((s) => s.monospaceFont));
    final brightnessMode = ref.watch(settingsProvider.select((s) => s.brightnessMode));
    final brightness = resolveBrightness(brightnessMode);

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
      // Key the shell by the active palette so a theme change remounts the
      // whole tree, forcing every widget to re-read the global FsColors ramp.
      // Session/tab state lives in Riverpod providers, so it survives the
      // remount — only ephemeral widget state (scroll offsets) resets.
      home: AppShell(key: ValueKey('$themeName:$accentValue:$uiFont:$monoFont:${brightness.name}')),
    );
  }
}
