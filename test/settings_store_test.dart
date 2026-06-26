import 'dart:ui' show PlatformDispatcher;

import 'package:drag/data/settings_store.dart';
import 'package:drag/models/app_font.dart';
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
        brightnessMode: 'dark',
        accentValue: 0xFF22C55E,
        uiFontSize: 14,
        uiFont: 'Poppins',
        monospaceFont: 'Fira Code',
        showHiddenFiles: false,
        showPermsColumn: false,
        showLogOnStartup: true,
        confirmOverwrite: false,
        transferLimitKbps: 5120,
        notifyOnComplete: false,
        windowWidth: 1200,
        windowHeight: 800,
        windowX: 40,
        windowY: 60,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.themeName, 'Light');
      expect(back.brightnessMode, 'dark');
      expect(back.accentValue, 0xFF22C55E);
      expect(back.accentHiValue, 0xFF06ABDF);
      expect(back.uiFontSize, 14);
      expect(back.uiFont, 'Poppins');
      expect(back.monospaceFont, 'Fira Code');
      expect(back.showHiddenFiles, isFalse);
      expect(back.showPermsColumn, isFalse);
      expect(back.showLogOnStartup, isTrue);
      expect(back.confirmOverwrite, isFalse);
      expect(back.transferLimitKbps, 5120);
      expect(back.notifyOnComplete, isFalse);
      expect(back.windowWidth, 1200);
      expect(back.windowHeight, 800);
      expect(back.windowX, 40);
      expect(back.windowY, 60);
    });

    test('fromJson tolerates missing keys with defaults', () {
      final s = AppSettings.fromJson(const {});
      expect(s.themeName, 'Rainbow Bee-eater');
      expect(s.brightnessMode, 'system');
      expect(s.transferLimitKbps, 0); // unlimited by default
      expect(s.accentHiValue, 0xFF06ABDF);
      expect(s.showHiddenFiles, isFalse); // hidden files are off by default
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
      expect(s.themeName, 'Rainbow Bee-eater');
      expect(s.showHiddenFiles, isFalse); // hidden files are off by default
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
      expect(s2.accentValue, 0xFF007CBF); // back to default in the new object
    });
  });

  group('settings application (Riverpod)', () {
    setUp(() {
      // Reset the global palette between tests.
      FsColors.accent = FsColors.accentDefault;
      FsColors.accentHi = const Color(0xFF06ABDF);
    });

    test('applies persisted settings on construction', () {
      final c = makeContainer(
          settings: AppSettings(uiFontSize: 14, showHiddenFiles: false));
      final settings = c.read(settingsProvider);
      expect(settings.uiFontSize, 14);
      expect(settings.showHiddenFiles, isFalse);
      // Panes built from the setting start with hidden files off.
      expect(c.read(sessionsProvider.notifier).leftPane.showHidden, isFalse);
    });

    test('setTheme seeds the light Material 3 palette from a bird primary', () {
      final c = makeContainer();
      final galah = birdThemeByName('Galah');
      final cs = ColorScheme.fromSeed(seedColor: galah.primary, brightness: Brightness.light);
      c.read(settingsProvider.notifier).setTheme(galah);
      final settings = c.read(settingsProvider);
      expect(settings.themeName, 'Galah');
      expect(settings.accentValue, cs.primary.toARGB32());
      // The whole light ramp is derived from the seed, not just the accent.
      expect(FsColors.accent, cs.primary);
      expect(FsColors.bgScaffold, cs.surfaceContainerLow);
      expect(FsColors.text1, cs.onSurface);
    });

    test('resolveBrightness maps modes (and system reads the platform)', () {
      expect(resolveBrightness('light'), Brightness.light);
      expect(resolveBrightness('dark'), Brightness.dark);
      // 'system' / anything else defers to the OS preference.
      expect(resolveBrightness('system'),
          PlatformDispatcher.instance.platformBrightness);
    });

    test('setBrightnessMode regenerates the palette at the chosen brightness', () {
      final c = makeContainer();
      final n = c.read(settingsProvider.notifier);

      n.setBrightnessMode('light');
      expect(c.read(settingsProvider).brightnessMode, 'light');
      expect(FsColors.brightness, Brightness.light);
      expect(FsColors.scheme.brightness, Brightness.light);
      final lightScaffold = FsColors.bgScaffold;
      final lightText = FsColors.text1;

      n.setBrightnessMode('dark');
      expect(c.read(settingsProvider).brightnessMode, 'dark');
      expect(FsColors.brightness, Brightness.dark);
      expect(FsColors.scheme.brightness, Brightness.dark);
      // The dark ramp differs from the light one (same seed, opposite surfaces).
      expect(FsColors.bgScaffold, isNot(lightScaffold));
      expect(FsColors.text1, isNot(lightText));
      // Dark text sits on dark surfaces → light foreground.
      expect(FsColors.text1.computeLuminance(),
          greaterThan(FsColors.bgScaffold.computeLuminance()));
    });

    test('birdThemeByName falls back to the default for an unknown name', () {
      expect(birdThemeByName('Nope').name, kDefaultThemeName);
      expect(kBirdThemes, hasLength(12));
    });

    test('setUiFont / setMonospaceFont apply the global font families', () {
      final c = makeContainer();
      final n = c.read(settingsProvider.notifier);
      n.setUiFont('Poppins');
      n.setMonospaceFont('Fira Code');
      expect(c.read(settingsProvider).uiFont, 'Poppins');
      expect(c.read(settingsProvider).monospaceFont, 'Fira Code');
      expect(FsType.uiFontFamily, 'Poppins');
      expect(FsType.monoFontFamily, 'Fira Code');
    });

    test('AppFont sanitises unknown / mismatched families to slot defaults', () {
      // A bogus name, or a mono font in the UI slot, falls back sensibly.
      expect(AppFont.resolve('Comic Sans', mono: false), 'Inter');
      expect(AppFont.resolve('Fira Code', mono: false), 'Inter');
      expect(AppFont.resolve('Menlo', mono: true), 'JetBrains Mono');
      expect(AppFont.resolve('Fira Code', mono: true), 'Fira Code');
      expect(AppFont.sansFonts.every((f) => !f.mono), isTrue);
      expect(AppFont.monoFonts.every((f) => f.mono), isTrue);
    });

    test('buildDragTheme tolerates a bundled (non-catalogue) UI font', () {
      // Roboto Condensed ships as an asset, not via google_fonts — building the
      // theme (which calls GoogleFonts.getTextTheme) must not throw for it.
      FsType.uiFontFamily = 'Roboto Condensed';
      expect(buildDragTheme, returnsNormally);
      expect(FsType.sans, returnsNormally);
      FsType.uiFontFamily = 'Inter';
    });

    test('setShowHiddenFiles propagates to every pane', () {
      final c = makeContainer();
      // Build sessions so the show-hidden listener is wired up.
      c.read(sessionsProvider);
      // Hidden files are off by default; enabling the setting reaches every pane.
      expect(c.read(sessionsProvider.notifier).leftPane.showHidden, isFalse);
      c.read(settingsProvider.notifier).setShowHiddenFiles(true);
      for (final s in c.read(sessionsProvider).sessions) {
        expect(s.left.showHidden, isTrue);
        expect(s.right.showHidden, isTrue);
      }
    });

    test('resetSettings restores defaults', () {
      final c = makeContainer();
      final n = c.read(settingsProvider.notifier);
      n.setTheme(birdThemeByName('Galah'));
      n.setUiFontSize(14);
      n.resetSettings();
      expect(c.read(settingsProvider).uiFontSize, 13);
      expect(c.read(settingsProvider).themeName, kDefaultThemeName);
      final def = ColorScheme.fromSeed(
          seedColor: birdThemeByName(kDefaultThemeName).primary, brightness: Brightness.light);
      expect(FsColors.accent, def.primary);
    });
  });
}
