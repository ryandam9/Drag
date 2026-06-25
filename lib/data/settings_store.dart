import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// User-adjustable app preferences plus the last window geometry. Persisted as
/// a single JSON row by [SettingsStore]. Contains no secrets.
class AppSettings {
  AppSettings({
    this.themeName = 'Rainbow Bee-eater',
    this.brightnessMode = 'system',
    this.accentValue = 0xFF007CBF,
    this.accentHiValue = 0xFF06ABDF,
    this.uiFontSize = 13,
    this.uiFont = 'Inter',
    this.monospaceFont = 'JetBrains Mono',
    this.showHiddenFiles = true,
    this.showPermsColumn = true,
    this.showLogOnStartup = false,
    this.confirmOverwrite = true,
    this.verifyLevel = 'size',
    this.transferLimitKbps = 0,
    this.notifyOnComplete = true,
    this.sidebarCollapsed = false,
    this.windowWidth,
    this.windowHeight,
    this.windowX,
    this.windowY,
  });

  String themeName;

  /// UI brightness: `'light'`, `'dark'`, or `'system'` (follow the OS).
  String brightnessMode;

  /// The accent color as a 32-bit ARGB value.
  int accentValue;

  /// The lighter accent-highlight color as a 32-bit ARGB value.
  int accentHiValue;

  /// Base UI font size in logical pixels (12 / 13 / 14).
  double uiFontSize;

  /// The proportional UI font family (a Google Fonts name).
  String uiFont;

  /// The monospace font family used for paths, logs and the file list.
  String monospaceFont;

  bool showHiddenFiles;
  bool showPermsColumn;
  bool showLogOnStartup;
  bool confirmOverwrite;

  /// How thoroughly a completed transfer is checked against its source:
  /// `'off'` (no check), `'size'` (compare byte counts) or `'checksum'`
  /// (compare MD5 digests). A mismatch fails the transfer so it can retry.
  String verifyLevel;

  /// Aggregate transfer bandwidth cap in KiB/second, shared across all active
  /// transfers. `0` means unlimited.
  int transferLimitKbps;

  /// Post an OS desktop notification when a transfer finishes while the app
  /// window is unfocused.
  bool notifyOnComplete;

  /// Whether the left navigation sidebar is collapsed to icons only.
  bool sidebarCollapsed;

  // Last window geometry (null until the window has been sized once).
  double? windowWidth;
  double? windowHeight;
  double? windowX;
  double? windowY;

  AppSettings copyWith({
    String? themeName,
    String? brightnessMode,
    int? accentValue,
    int? accentHiValue,
    double? uiFontSize,
    String? uiFont,
    String? monospaceFont,
    bool? showHiddenFiles,
    bool? showPermsColumn,
    bool? showLogOnStartup,
    bool? confirmOverwrite,
    String? verifyLevel,
    int? transferLimitKbps,
    bool? notifyOnComplete,
    bool? sidebarCollapsed,
    double? windowWidth,
    double? windowHeight,
    double? windowX,
    double? windowY,
  }) =>
      AppSettings(
        themeName: themeName ?? this.themeName,
        brightnessMode: brightnessMode ?? this.brightnessMode,
        accentValue: accentValue ?? this.accentValue,
        accentHiValue: accentHiValue ?? this.accentHiValue,
        uiFontSize: uiFontSize ?? this.uiFontSize,
        uiFont: uiFont ?? this.uiFont,
        monospaceFont: monospaceFont ?? this.monospaceFont,
        showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
        showPermsColumn: showPermsColumn ?? this.showPermsColumn,
        showLogOnStartup: showLogOnStartup ?? this.showLogOnStartup,
        confirmOverwrite: confirmOverwrite ?? this.confirmOverwrite,
        verifyLevel: verifyLevel ?? this.verifyLevel,
        transferLimitKbps: transferLimitKbps ?? this.transferLimitKbps,
        notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
        sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
        windowWidth: windowWidth ?? this.windowWidth,
        windowHeight: windowHeight ?? this.windowHeight,
        windowX: windowX ?? this.windowX,
        windowY: windowY ?? this.windowY,
      );

  Map<String, Object?> toJson() => {
        'themeName': themeName,
        'brightnessMode': brightnessMode,
        'accentValue': accentValue,
        'accentHiValue': accentHiValue,
        'uiFontSize': uiFontSize,
        'uiFont': uiFont,
        'monospaceFont': monospaceFont,
        'showHiddenFiles': showHiddenFiles,
        'showPermsColumn': showPermsColumn,
        'showLogOnStartup': showLogOnStartup,
        'confirmOverwrite': confirmOverwrite,
        'verifyLevel': verifyLevel,
        'transferLimitKbps': transferLimitKbps,
        'notifyOnComplete': notifyOnComplete,
        'sidebarCollapsed': sidebarCollapsed,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
        'windowX': windowX,
        'windowY': windowY,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) {
    double? d(Object? v) => (v as num?)?.toDouble();
    return AppSettings(
      themeName: (j['themeName'] as String?) ?? 'Rainbow Bee-eater',
      brightnessMode: (j['brightnessMode'] as String?) ?? 'system',
      accentValue: (j['accentValue'] as num?)?.toInt() ?? 0xFF007CBF,
      accentHiValue: (j['accentHiValue'] as num?)?.toInt() ?? 0xFF06ABDF,
      uiFontSize: d(j['uiFontSize']) ?? 13,
      uiFont: (j['uiFont'] as String?) ?? 'Inter',
      monospaceFont: (j['monospaceFont'] as String?) ?? 'JetBrains Mono',
      showHiddenFiles: (j['showHiddenFiles'] as bool?) ?? true,
      showPermsColumn: (j['showPermsColumn'] as bool?) ?? true,
      showLogOnStartup: (j['showLogOnStartup'] as bool?) ?? false,
      confirmOverwrite: (j['confirmOverwrite'] as bool?) ?? true,
      verifyLevel: (j['verifyLevel'] as String?) ?? 'size',
      transferLimitKbps: (j['transferLimitKbps'] as num?)?.toInt() ?? 0,
      notifyOnComplete: (j['notifyOnComplete'] as bool?) ?? true,
      sidebarCollapsed: (j['sidebarCollapsed'] as bool?) ?? false,
      windowWidth: d(j['windowWidth']),
      windowHeight: d(j['windowHeight']),
      windowX: d(j['windowX']),
      windowY: d(j['windowY']),
    );
  }
}

/// Persists [AppSettings] in a local SQLite database as a single JSON row
/// (`id = 1`). Mirrors the pattern used by `ConnectionStore` / history.
class SettingsStore {
  SettingsStore._(this._db);

  final Database _db;
  static const _table = 'settings';
  static const _rowId = 1;

  static Future<SettingsStore> open([String? path]) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath = path ?? await _defaultPath(factory);
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY,
            data TEXT NOT NULL
          )
        '''),
      ),
    );
    return SettingsStore._(db);
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final base = await factory.getDatabasesPath();
    return base.endsWith('/') ? '${base}drag_settings.db' : '$base/drag_settings.db';
  }

  /// Loads persisted settings, or returns defaults on first run.
  Future<AppSettings> load() async {
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [_rowId], limit: 1);
    if (rows.isEmpty) return AppSettings();
    return AppSettings.fromJson(
        jsonDecode(rows.first['data'] as String) as Map<String, Object?>);
  }

  Future<void> save(AppSettings s) async {
    await _db.insert(
      _table,
      {'id': _rowId, 'data': jsonEncode(s.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() => _db.close();
}
