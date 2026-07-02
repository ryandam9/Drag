import 'package:drag/data/connection_store.dart';
import 'package:drag/data/history_db.dart';
import 'package:drag/data/session_store.dart';
import 'package:drag/data/settings_store.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Builds a [ProviderContainer] wired for tests: pane auto-refresh is off by
/// default (no real filesystem I/O) and the SQLite stores are absent unless
/// supplied. Disposed automatically at the end of the test.
ProviderContainer makeContainer({
  List<Connection>? connections,
  AppSettings? settings,
  SessionLayout? layout,
  HistoryRepository? history,
  ConnectionStore? connectionStore,
  SettingsStore? settingsStore,
  SessionStore? sessionStore,
  bool autoRefresh = false,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      autoRefreshPanesProvider.overrideWithValue(autoRefresh),
      ...overrides,
      initialConnectionsProvider.overrideWithValue(connections),
      initialSettingsProvider.overrideWithValue(settings),
      initialSessionLayoutProvider.overrideWithValue(layout),
      historyRepositoryProvider.overrideWithValue(history),
      connectionStoreProvider.overrideWithValue(connectionStore),
      settingsStoreProvider.overrideWithValue(settingsStore),
      sessionStoreProvider.overrideWithValue(sessionStore),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A pair of test connections: one S3 (no creds) and one SFTP.
List<Connection> sampleConnections() => [
  Connection(
    id: 's3a',
    name: 's3-prod (Account A)',
    protocol: Protocol.s3,
    region: 'us-east-1',
    bucket: 'acme-prod-assets',
    group: ConnGroup.recent,
  ),
  Connection(
    id: 's3b',
    name: 's3-archive (Account B)',
    protocol: Protocol.s3,
    region: 'eu-west-1',
    bucket: 'acme-archive',
    group: ConnGroup.saved,
  ),
  Connection(
    id: 'sftp1',
    name: 'prod-server-01',
    host: 'prod-server-01.example.com',
    username: 'deploy',
    protocol: Protocol.sftp,
    group: ConnGroup.recent,
  ),
];
