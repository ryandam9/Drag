import 'package:drag/data/settings_store.dart';
import 'package:drag/state/app_state.dart';
import 'package:drag/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings JSON', () {
    test('round-trips all fields', () {
      final s = AppSettings(
        themeName: 'Light',
        accentValue: 0xFF22C55E,
        uiFontSize: 14,
        monospaceFont: 'Fira Code',
        showHiddenFiles: false,
        showPermsColumn: false,
        showLogOnStartup: true,
        confirmOverwrite: false,
        windowWidth: 1200,
        windowHeight: 800,
        windowX: 40,
        windowY: 60,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.themeName, 'Light');
      expect(back.accentValue, 0xFF22C55E);
      expect(back.uiFontSize, 14);
      expect(back.monospaceFont, 'Fira Code');
      expect(back.showHiddenFiles, isFalse);
      expect(back.showPermsColumn, isFalse);
      expect(back.showLogOnStartup, isTrue);
      expect(back.confirmOverwrite, isFalse);
      expect(back.windowWidth, 1200);
      expect(back.windowHeight, 800);
      expect(back.windowX, 40);
      expect(back.windowY, 60);
    });

    test('fromJson tolerates missing keys with defaults', () {
      final s = AppSettings.fromJson(const {});
      expect(s.themeName, 'Dark (default)');
      expect(s.showHiddenFiles, isTrue);
      expect(s.windowWidth, isNull);
    });
  });

  group('SettingsStore', () {
    late SettingsStore store;

    setUp(() async {
      sqfliteFfiInit();
      store = await SettingsStore.open(inMemoryDatabasePath);
    });
    tearDown(() => store.close());

    test('load returns defaults on first run', () async {
      final s = await store.load();
      expect(s.themeName, 'Dark (default)');
      expect(s.showHiddenFiles, isTrue);
    });

    test('save then load persists the single row', () async {
      await store.save(AppSettings(accentValue: 0xFFA855F7, showHiddenFiles: false));
      final s = await store.load();
      expect(s.accentValue, 0xFFA855F7);
      expect(s.showHiddenFiles, isFalse);

      // Saving again overwrites the same row (no duplicates).
      await store.save(AppSettings(uiFontSize: 12));
      final s2 = await store.load();
      expect(s2.uiFontSize, 12);
      expect(s2.accentValue, 0xFF3B82F6); // back to default in the new object
    });
  });

  group('AppState settings application', () {
    setUp(() {
      // Reset the global palette between tests.
      FsColors.accent = FsColors.accentDefault;
      FsColors.accentHi = const Color(0xFF60A5FA);
    });

    test('applies persisted settings on construction', () {
      final app = AppState(
        tickEnabled: false,
        autoRefreshPanes: false,
        settings: AppSettings(
          accentValue: 0xFF22C55E,
          uiFontSize: 14,
          showHiddenFiles: false,
        ),
      );
      addTearDown(app.dispose);
      expect(app.uiFontSize, 14);
      expect(app.showHiddenFiles, isFalse);
      expect(FsColors.accent, const Color(0xFF22C55E));
      // Panes built from the setting start with hidden files off.
      expect(app.leftPane.showHidden, isFalse);
    });

    test('setAccent recolors the global palette + derives highlight', () {
      final app = AppState(tickEnabled: false, autoRefreshPanes: false);
      addTearDown(app.dispose);
      app.setAccent(const Color(0xFFA855F7));
      expect(FsColors.accent, const Color(0xFFA855F7));
      expect(FsColors.accentHi, FsColors.highlightFor(const Color(0xFFA855F7)));
    });

    test('setShowHiddenFiles propagates to every pane', () {
      final app = AppState(tickEnabled: false, autoRefreshPanes: false);
      addTearDown(app.dispose);
      expect(app.leftPane.showHidden, isTrue);
      app.setShowHiddenFiles(false);
      for (final s in app.sessions) {
        expect(s.left.showHidden, isFalse);
        expect(s.right.showHidden, isFalse);
      }
    });

    test('resetSettings restores defaults', () {
      final app = AppState(tickEnabled: false, autoRefreshPanes: false);
      addTearDown(app.dispose);
      app.setAccent(const Color(0xFFEF4444));
      app.setUiFontSize(14);
      app.resetSettings();
      expect(app.uiFontSize, 13);
      expect(FsColors.accent, FsColors.accentDefault);
    });
  });
}
