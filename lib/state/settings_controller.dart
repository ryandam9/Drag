import 'package:flutter/material.dart';

import '../data/settings_store.dart';
import '../theme.dart';

/// Owns the Appearance settings: applies them live (accent → global palette,
/// font size, the toggles) and persists them via [SettingsStore]. Pure
/// settings state — the one cross-cutting concern (hidden-file visibility
/// affecting the panes) is delegated through [onShowHiddenChanged].
class SettingsController extends ChangeNotifier {
  SettingsController({
    SettingsStore? store,
    AppSettings? initial,
    this.onShowHiddenChanged,
  })
      // ignore: prefer_initializing_formals
      : _store = store {
    if (initial != null) _apply(initial);
  }

  final SettingsStore? _store;

  /// Invoked when "show hidden files" changes, so the sessions/panes can
  /// re-filter their listings.
  final void Function(bool show)? onShowHiddenChanged;

  String themeName = 'Dark (default)';
  Color accent = FsColors.accent;
  double uiFontSize = 13;
  String monospaceFont = 'JetBrains Mono';
  bool showHiddenFiles = true;
  bool showPermsColumn = true;
  bool showLogOnStartup = false;
  bool confirmOverwrite = true;
  AppSettings _windowGeometry = AppSettings();

  bool _disposed = false;
  bool get hasStore => _store != null;

  /// Snapshot of the current settings for persistence.
  AppSettings get current => AppSettings(
        themeName: themeName,
        accentValue: accent.toARGB32(),
        uiFontSize: uiFontSize,
        monospaceFont: monospaceFont,
        showHiddenFiles: showHiddenFiles,
        showPermsColumn: showPermsColumn,
        showLogOnStartup: showLogOnStartup,
        confirmOverwrite: confirmOverwrite,
        windowWidth: _windowGeometry.windowWidth,
        windowHeight: _windowGeometry.windowHeight,
        windowX: _windowGeometry.windowX,
        windowY: _windowGeometry.windowY,
      );

  /// Apply persisted settings to in-memory state + the global theme accent.
  /// Called from the constructor before panes/sessions are built so the
  /// hidden-file filter and accent are correct from the first frame.
  void _apply(AppSettings s) {
    themeName = s.themeName;
    accent = Color(s.accentValue);
    uiFontSize = s.uiFontSize;
    monospaceFont = s.monospaceFont;
    showHiddenFiles = s.showHiddenFiles;
    showPermsColumn = s.showPermsColumn;
    showLogOnStartup = s.showLogOnStartup;
    confirmOverwrite = s.confirmOverwrite;
    _windowGeometry = s;
    FsColors.accent = accent;
    FsColors.accentHi = FsColors.highlightFor(accent);
  }

  Future<void> _persist() async => _store?.save(current);

  void setThemeName(String v) {
    themeName = v;
    _notify();
    _persist();
  }

  void setAccent(Color c) {
    accent = c;
    FsColors.accent = c;
    FsColors.accentHi = FsColors.highlightFor(c);
    _notify();
    _persist();
  }

  void setUiFontSize(double v) {
    uiFontSize = v;
    _notify();
    _persist();
  }

  void setMonospaceFont(String v) {
    monospaceFont = v;
    _notify();
    _persist();
  }

  void setShowHiddenFiles(bool v) {
    showHiddenFiles = v;
    onShowHiddenChanged?.call(v);
    _notify();
    _persist();
  }

  void setShowPermsColumn(bool v) {
    showPermsColumn = v;
    _notify();
    _persist();
  }

  void setShowLogOnStartup(bool v) {
    showLogOnStartup = v;
    _notify();
    _persist();
  }

  void setConfirmOverwrite(bool v) {
    confirmOverwrite = v;
    _notify();
    _persist();
  }

  /// Restore everything to defaults (keeping window geometry) and persist.
  void resetSettings() {
    _apply(AppSettings(
      windowWidth: _windowGeometry.windowWidth,
      windowHeight: _windowGeometry.windowHeight,
      windowX: _windowGeometry.windowX,
      windowY: _windowGeometry.windowY,
    ));
    onShowHiddenChanged?.call(showHiddenFiles);
    _notify();
    _persist();
  }

  /// Persist the latest window geometry (called from the window listener).
  Future<void> saveWindowState({
    required double width,
    required double height,
    required double x,
    required double y,
  }) async {
    _windowGeometry
      ..windowWidth = width
      ..windowHeight = height
      ..windowX = x
      ..windowY = y;
    await _persist();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
