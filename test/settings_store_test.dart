import 'package:drag/data/settings_store.dart';
import 'package:drag/state/app.dart';
import 'package:drag/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

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

  group('settings application (Riverpod)', () {
    setUp(() {
      // Reset the global palette between tests.
      FsColors.accent = FsColors.accentDefault;
      FsColors.accentHi = const Color(0xFF60A5FA);
    });

    test('applies persisted settings on construction', () {
      final c = makeContainer(
          settings: AppSettings(accentValue: 0xFF22C55E, uiFontSize: 14, showHiddenFiles: false));
      final settings = c.read(settingsProvider);
      expect(settings.uiFontSize, 14);
      expect(settings.showHiddenFiles, isFalse);
      expect(FsColors.accent, const Color(0xFF22C55E));
      // Panes built from the setting start with hidden files off.
      expect(c.read(sessionsProvider.notifier).leftPane.showHidden, isFalse);
    });

    test('setAccent recolors the global palette + derives highlight', () {
      final c = makeContainer();
      c.read(settingsProvider.notifier).setAccent(const Color(0xFFA855F7));
      expect(FsColors.accent, const Color(0xFFA855F7));
      expect(FsColors.accentHi, FsColors.highlightFor(const Color(0xFFA855F7)));
    });

    test('setShowHiddenFiles propagates to every pane', () {
      final c = makeContainer();
      // Build sessions so the show-hidden listener is wired up.
      c.read(sessionsProvider);
      expect(c.read(sessionsProvider.notifier).leftPane.showHidden, isTrue);
      c.read(settingsProvider.notifier).setShowHiddenFiles(false);
      for (final s in c.read(sessionsProvider).sessions) {
        expect(s.left.showHidden, isFalse);
        expect(s.right.showHidden, isFalse);
      }
    });

    test('resetSettings restores defaults', () {
      final c = makeContainer();
      final n = c.read(settingsProvider.notifier);
      n.setAccent(const Color(0xFFEF4444));
      n.setUiFontSize(14);
      n.resetSettings();
      expect(c.read(settingsProvider).uiFontSize, 13);
      expect(FsColors.accent, FsColors.accentDefault);
    });
  });
}
