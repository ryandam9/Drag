import 'package:drag/data/history_db.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/screens/connection_manager_screen.dart';
import 'package:drag/screens/dashboard_screen.dart';
import 'package:drag/screens/settings_screen.dart';
import 'package:drag/screens/transfer_queue_screen.dart';
import 'package:drag/state/app.dart';
import 'package:drag/widgets/toast_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// A history notifier with a fixed state — avoids real SQLite I/O inside the
/// fake-async zone of testWidgets.
class _FakeHistory extends HistoryNotifier {
  _FakeHistory(this._initial);
  final HistoryState _initial;
  @override
  HistoryState build() => _initial;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1320, 900);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
  });

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container, Widget screen) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: screen),
      ),
    ));
    await tester.pump();
  }

  group('Connection Manager', () {
    testWidgets('shows SSH fields for an SFTP connection', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.kind == EndpointKind.sftp));
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      expect(find.text('Hostname / IP'), findsOneWidget);
      expect(find.text('Authentication'), findsOneWidget);
      expect(find.text('Access Key ID'), findsNothing);
    });

    testWidgets('shows S3 credential fields for an S3 connection', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      expect(find.text('Access Key ID'), findsOneWidget);
      expect(find.text('Secret Access Key'), findsOneWidget);
      expect(find.text('Bucket'), findsOneWidget);
      expect(find.text('Hostname / IP'), findsNothing);
    });

    testWidgets('typing into the bucket field updates the connection', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      final s3 = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      c.read(connectionsProvider.notifier).select(s3);
      await pumpScreen(tester, c, const ConnectionManagerScreen());

      final bucketField = find.widgetWithText(TextField, s3.bucket);
      expect(bucketField, findsWidgets);
      await tester.enterText(bucketField.first, 'new-bucket-name');
      expect(s3.bucket, 'new-bucket-name');
    });

    testWidgets('shows the empty state with no connections', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      expect(find.text('No connections yet'), findsOneWidget);
    });
  });

  group('Transfer Queue', () {
    Transfer t(String name, TransferStatus status, {int size = 1000}) => Transfer(
        name: name, route: 'Local → s3', direction: TransferDirection.upload, sizeBytes: size, session: 's', status: status);

    testWidgets('renders seeded transfers and the stats bar', (tester) async {
      final c = makeContainer();
      c.read(transfersProvider.notifier).debugSetTransfers([
        t('backup_2025-06-19.tar.gz', TransferStatus.active, size: 248 * 1024 * 1024),
        t('.env', TransferStatus.error),
        t('server.js', TransferStatus.done),
      ]);
      await pumpScreen(tester, c, const TransferQueueScreen());
      expect(find.text('backup_2025-06-19.tar.gz'), findsOneWidget);
      expect(find.text('Total queued'), findsOneWidget);
      expect(find.textContaining('Active'), findsWidgets);
      expect(find.textContaining('Error'), findsWidgets);
    });

    testWidgets('Clear done removes the completed row', (tester) async {
      final c = makeContainer();
      c.read(transfersProvider.notifier).debugSetTransfers([t('server.js', TransferStatus.done)]);
      await pumpScreen(tester, c, const TransferQueueScreen());
      expect(find.text('server.js'), findsOneWidget);
      c.read(transfersProvider.notifier).clearDone();
      await tester.pump();
      expect(find.text('server.js'), findsNothing);
    });

    testWidgets('shows empty state when there are no transfers', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const TransferQueueScreen());
      expect(find.text('No transfers yet'), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('renders appearance options', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Show hidden files'), findsOneWidget);
    });

    testWidgets('toggling a checkbox updates settings', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      expect(c.read(settingsProvider).showLogOnStartup, isFalse);
      // Exactly one checkbox is unchecked by default (Show transfer log on startup).
      final unchecked = find.byWidgetPredicate((w) => w is Checkbox && w.value == false);
      expect(unchecked, findsOneWidget);
      await tester.tap(unchecked);
      await tester.pump();
      expect(c.read(settingsProvider).showLogOnStartup, isTrue);
    });
  });

  group('Dashboard', () {
    testWidgets('renders stat cards and history rows', (tester) async {
      final state = HistoryState(
        hasDb: true,
        records: [
          TransferRecord(
            name: 'archive.zip',
            sourcePath: 'Local:/a/archive.zip',
            destPath: 's3://bucket/archive.zip',
            session: 'bucket',
            sizeBytes: 5000,
            direction: 0,
            durationMs: 1000,
            success: true,
            finishedAt: DateTime.now(),
          ),
        ],
        stats: const HistoryStats(
            total: 1, succeeded: 1, failed: 0, totalBytes: 5000, avgBytesPerSecond: 5000),
      );
      final c = makeContainer(overrides: [historyProvider.overrideWith(() => _FakeHistory(state))]);
      await pumpScreen(tester, c, const DashboardScreen());

      expect(find.text('Total transfers'), findsOneWidget);
      expect(find.text('Data transferred'), findsOneWidget);
      expect(find.text('archive.zip'), findsOneWidget);
    });

    testWidgets('shows empty state with no history', (tester) async {
      final c = makeContainer(overrides: [
        historyProvider.overrideWith(() => _FakeHistory(const HistoryState())),
      ]);
      await pumpScreen(tester, c, const DashboardScreen());
      expect(find.text('No transfers yet'), findsOneWidget);
    });
  });

  group('Toasts', () {
    testWidgets('ToastOverlay renders queued toasts', (tester) async {
      final c = makeContainer();
      c.read(toastsProvider.notifier).push('Upload complete', 'file.txt → s3', ToastKind.success);
      await pumpScreen(tester, c, const Stack(children: [ToastOverlay()]));
      expect(find.text('Upload complete'), findsOneWidget);
      expect(find.text('file.txt → s3'), findsOneWidget);
      // Drain the auto-dismiss timer so no timer is left pending.
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
