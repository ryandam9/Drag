import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/connection_store.dart';
import '../data/history_db.dart';
import '../data/secret_store.dart';
import '../data/session_store.dart';
import '../data/settings_store.dart';
import '../models/connection.dart';

/// Dependency-injection seams for the local SQLite stores and the data loaded
/// from them at startup. `main()` opens the stores and overrides these in the
/// root [ProviderScope]; tests either override them with in-memory stores or
/// leave the defaults (`null`) for a pure in-memory run.

final historyRepositoryProvider = Provider<HistoryRepository?>((ref) => null);

final connectionStoreProvider = Provider<ConnectionStore?>((ref) => null);

final settingsStoreProvider = Provider<SettingsStore?>((ref) => null);

final sessionStoreProvider = Provider<SessionStore?>((ref) => null);

/// Where connection secrets are persisted (OS keychain). Null → secrets stay
/// in memory only, as before keychain support existed.
final secretStoreProvider = Provider<SecretStore?>((ref) => null);

/// Settings loaded from [SettingsStore] at startup (null → defaults).
final initialSettingsProvider = Provider<AppSettings?>((ref) => null);

/// Saved connections loaded from [ConnectionStore] at startup (null → empty).
final initialConnectionsProvider = Provider<List<Connection>?>((ref) => null);

/// The persisted tab layout loaded from [SessionStore] at startup
/// (null/empty → a single fresh Local tab).
final initialSessionLayoutProvider = Provider<SessionLayout?>((ref) => null);

/// Whether panes list their contents automatically when built/switched.
/// Overridden to `false` in tests that don't want real filesystem I/O.
final autoRefreshPanesProvider = Provider<bool>((ref) => true);
