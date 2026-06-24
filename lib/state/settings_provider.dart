import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
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
    FsColors.accent = Color(s.accentValue);
    FsColors.accentHi = Color(s.accentHiValue);
  }

  void _update(AppSettings next) {
    state = next;
    _applyGlobals(next);
    _store?.save(next);
  }

  void setThemeName(String v) => _update(state.copyWith(themeName: v));

  /// Apply a named bird theme: its [BirdTheme.accent] becomes the UI accent and
  /// [BirdTheme.accentHi] the highlight, all persisted together.
  void setTheme(BirdTheme t) => _update(state.copyWith(
        themeName: t.name,
        accentValue: t.accent.toARGB32(),
        accentHiValue: t.accentHi.toARGB32(),
      ));

  /// Override just the accent with a custom colour, deriving its highlight.
  void setAccent(Color c) => _update(state.copyWith(
        accentValue: c.toARGB32(),
        accentHiValue: FsColors.highlightFor(c).toARGB32(),
      ));
  void setUiFontSize(double v) => _update(state.copyWith(uiFontSize: v));
  void setMonospaceFont(String v) => _update(state.copyWith(monospaceFont: v));
  void setShowHiddenFiles(bool v) => _update(state.copyWith(showHiddenFiles: v));
  void setShowPermsColumn(bool v) => _update(state.copyWith(showPermsColumn: v));
  void setShowLogOnStartup(bool v) => _update(state.copyWith(showLogOnStartup: v));
  void setConfirmOverwrite(bool v) => _update(state.copyWith(confirmOverwrite: v));

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
