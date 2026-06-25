import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../models/app_font.dart';
import '../theme.dart';
import 'providers.dart';

export '../data/settings_store.dart' show AppSettings;

/// Convenience views over the raw [AppSettings] value.
extension AppSettingsView on AppSettings {
  Color get accent => Color(accentValue);
}

/// Owns the user preferences. Applies them live (accent → global palette) and
/// persists every change to [SettingsStore]. The state *is* the immutable
/// [AppSettings] value; widgets watch the slice they render.
class SettingsNotifier extends Notifier<AppSettings> {
  SettingsStore? get _store => ref.read(settingsStoreProvider);

  @override
  AppSettings build() {
    final initial = ref.read(initialSettingsProvider) ?? AppSettings();
    _applyGlobals(initial);
    return initial;
  }

  void _applyGlobals(AppSettings s) {
    // Generate the whole palette from the active theme's seed colour, at the
    // resolved brightness (light / dark / follow-the-OS).
    FsColors.applyTheme(birdThemeByName(s.themeName),
        brightness: resolveBrightness(s.brightnessMode));
    // Apply the chosen fonts (sanitised against the known families).
    FsType.uiFontFamily = AppFont.resolve(s.uiFont, mono: false);
    FsType.monoFontFamily = AppFont.resolve(s.monospaceFont, mono: true);
  }

  /// Re-derive the global palette for the current settings — used when the OS
  /// brightness changes while in `'system'` mode (the value itself is unchanged).
  void reapplyGlobals() => _applyGlobals(state);

  void _update(AppSettings next) {
    state = next;
    _applyGlobals(next);
    _store?.save(next);
  }

  void setThemeName(String v) => _update(state.copyWith(themeName: v));

  /// Set the UI brightness mode (`'light'` / `'dark'` / `'system'`).
  void setBrightnessMode(String v) => _update(state.copyWith(brightnessMode: v));

  /// Apply a named bird theme. Its primary seeds the light Material 3 palette;
  /// the resolved accent is persisted too (for the pre-frame paint in main).
  void setTheme(BirdTheme t) {
    final cs = ColorScheme.fromSeed(seedColor: t.primary, brightness: Brightness.light);
    _update(state.copyWith(
      themeName: t.name,
      accentValue: cs.primary.toARGB32(),
      accentHiValue: cs.onSecondaryContainer.toARGB32(),
    ));
  }

  void setUiFontSize(double v) => _update(state.copyWith(uiFontSize: v));
  void setUiFont(String v) => _update(state.copyWith(uiFont: v));
  void setMonospaceFont(String v) => _update(state.copyWith(monospaceFont: v));
  void setShowHiddenFiles(bool v) => _update(state.copyWith(showHiddenFiles: v));
  void setShowPermsColumn(bool v) => _update(state.copyWith(showPermsColumn: v));
  void setShowLogOnStartup(bool v) => _update(state.copyWith(showLogOnStartup: v));
  void setConfirmOverwrite(bool v) => _update(state.copyWith(confirmOverwrite: v));
  void setVerifyLevel(String v) => _update(state.copyWith(verifyLevel: v));
  void setSidebarCollapsed(bool v) => _update(state.copyWith(sidebarCollapsed: v));
  void toggleSidebar() => setSidebarCollapsed(!state.sidebarCollapsed);

  /// Restore everything to defaults, keeping the remembered window geometry.
  void resetSettings() {
    _update(AppSettings(
      windowWidth: state.windowWidth,
      windowHeight: state.windowHeight,
      windowX: state.windowX,
      windowY: state.windowY,
    ));
  }

  /// Persist the latest window geometry (from the window listener). Does not
  /// reapply the palette — geometry is orthogonal to appearance.
  Future<void> saveWindowState({
    required double width,
    required double height,
    required double x,
    required double y,
  }) async {
    state = state.copyWith(
      windowWidth: width,
      windowHeight: height,
      windowX: x,
      windowY: y,
    );
    await _store?.save(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
