import 'package:filesync/data/history_db.dart';
import 'package:filesync/models/connection.dart';
import 'package:filesync/screens/connection_manager_screen.dart';
import 'package:filesync/screens/dashboard_screen.dart';
import 'package:filesync/screens/settings_screen.dart';
import 'package:filesync/screens/transfer_queue_screen.dart';
import 'package:filesync/state/app_state.dart';
import 'package:filesync/widgets/toast_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppState app;

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1320, 900);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    app = AppState(tickEnabled: false, autoRefreshPanes: false);
  });
  tearDown(() {
    app.dispose();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: screen),
      ),
    ));
    await tester.pump();
  }

  group('Connection Manager', () {
    testWidgets('shows SSH fields for an SFTP connection', (tester) async {
      app.selectConnection(app.connections.firstWhere((c) => c.kind == EndpointKind.sftp));
      await pumpScreen(tester, const ConnectionManagerScreen());
      expect(find.text('Hostname / IP'), findsOneWidget);
      expect(find.text('Authentication'), findsOneWidget);
      expect(find.text('Access Key ID'), findsNothing);
    });

    testWidgets('shows S3 credential fields for an S3 connection', (tester) async {
      app.selectConnection(app.connections.firstWhere((c) => c.isS3));
      await pumpScreen(tester, const ConnectionManagerScreen());
      expect(find.text('Access Key ID'), findsOneWidget);
      expect(find.text('Secret Access Key'), findsOneWidget);
      expect(find.text('Bucket'), findsOneWidget);
      expect(find.text('Hostname / IP'), findsNothing);
    });

    testWidgets('typing into the bucket field updates the connection', (tester) async {
      final s3 = app.connections.firstWhere((c) => c.isS3);
      app.selectConnection(s3);
      await pumpScreen(tester, const ConnectionManagerScreen());

      // The bucket field is pre-filled; replace its contents.
      final bucketField = find.widgetWithText(TextField, s3.bucket);
      expect(bucketField, findsWidgets);
      await tester.enterText(bucketField.first, 'new-bucket-name');
      expect(s3.bucket, 'new-bucket-name');
    });
  });

  group('Transfer Queue', () {
    testWidgets('renders seed transfers and the stats bar', (tester) async {
      await pumpScreen(tester, const TransferQueueScreen());
      expect(find.text('backup_2025-06-19.tar.gz'), findsOneWidget);
      expect(find.text('Total queued'), findsOneWidget);
      expect(find.textContaining('Active'), findsWidgets);
      expect(find.textContaining('Error'), findsWidgets);
    });

    testWidgets('Clear done removes the completed row', (tester) async {
      await pumpScreen(tester, const TransferQueueScreen());
      expect(find.text('server.js'), findsOneWidget); // the done transfer
      app.clearDone();
      await tester.pump();
      expect(find.text('server.js'), findsNothing);
    });
  });

  group('Settings', () {
    testWidgets('renders appearance options', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Show hidden files'), findsOneWidget);
    });

    testWidgets('toggling a checkbox updates AppState', (tester) async {
      await pumpScreen(tester, const SettingsScreen());
      expect(app.showLogOnStartup, isFalse);
      // Exactly one checkbox is unchecked by default (Show transfer log on startup).
      final unchecked = find.byWidgetPredicate((w) => w is Checkbox && w.value == false);
      expect(unchecked, findsOneWidget);
      await tester.tap(unchecked);
      await tester.pump();
      expect(app.showLogOnStartup, isTrue);
    });
  });

  group('Dashboard', () {
    // Inject history data directly (the real SQLite path is covered by the
    // plain-async tests in history_db_test.dart / app_state_test.dart; doing
    // real DB I/O inside testWidgets' fake-async zone would deadlock).
    testWidgets('renders stat cards and history rows', (tester) async {
      app.history = [
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
      ];
      app.historyStats = const HistoryStats(
          total: 1, succeeded: 1, failed: 0, totalBytes: 5000, avgBytesPerSecond: 5000);

      await pumpScreen(tester, const DashboardScreen());

      expect(find.text('Total transfers'), findsOneWidget);
      expect(find.text('Data transferred'), findsOneWidget);
      expect(find.text('archive.zip'), findsOneWidget);
    });

    testWidgets('shows empty state with no history', (tester) async {
      await pumpScreen(tester, const DashboardScreen());
      expect(find.text('No transfers yet'), findsOneWidget);
    });
  });

  group('Toasts', () {
    testWidgets('ToastOverlay renders queued toasts', (tester) async {
      app.pushToast('Upload complete', 'file.txt → s3', ToastKind.success);
      await pumpScreen(
        tester,
        const Stack(children: [ToastOverlay()]),
      );
      expect(find.text('Upload complete'), findsOneWidget);
      expect(find.text('file.txt → s3'), findsOneWidget);
      // Drain the 4s auto-dismiss timer so no timer is left pending.
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
