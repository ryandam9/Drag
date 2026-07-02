import 'package:drag/data/history_db.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/screens/connection_manager_screen.dart';
import 'package:drag/screens/dashboard_screen.dart';
import 'package:drag/screens/settings_screen.dart';
import 'package:drag/screens/transfer_queue_screen.dart';
import 'package:drag/state/app.dart';
import 'package:drag/theme.dart';
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
    testWidgets('shows SSH fields for an SFTP connection (Connection tab)', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.kind == EndpointKind.sftp));
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      // The SFTP form is tabbed; an Authentication tab exists, host lives under
      // the Connection tab, and there are no S3 credential fields.
      expect(find.text('Authentication'), findsOneWidget); // tab chip
      await tester.tap(find.text('Connection'));
      await tester.pump();
      expect(find.text('Hostname / IP'), findsOneWidget);
      expect(find.text('Access Key ID'), findsNothing);
    });

    testWidgets('shows S3 fields under the Connection and Credentials tabs', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));
      await pumpScreen(tester, c, const ConnectionManagerScreen());

      await tester.tap(find.text('Connection'));
      await tester.pump();
      expect(find.text('Bucket'), findsOneWidget);
      expect(find.text('Hostname / IP'), findsNothing);

      await tester.tap(find.text('Credentials'));
      await tester.pump();
      expect(find.text('Access Key ID'), findsOneWidget);
      expect(find.text('Secret Access Key'), findsOneWidget);
    });

    testWidgets('secret fields can be revealed with the eye toggle', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      await tester.tap(find.text('Credentials')); // secrets live on this tab
      await tester.pump();

      // Secret + session-token fields start obscured, each with a "show" eye.
      expect(find.byIcon(Icons.visibility_outlined), findsWidgets);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

      final eye = find.byIcon(Icons.visibility_outlined).first;
      await tester.ensureVisible(eye);
      await tester.pump();
      await tester.tap(eye);
      await tester.pump();

      // That field flips to revealed (its toggle now shows "hide").
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('typing into the bucket field updates the connection', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      final s3 = c.read(connectionsProvider).connections.firstWhere((x) => x.isS3);
      c.read(connectionsProvider.notifier).select(s3);
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      await tester.tap(find.text('Connection')); // bucket lives on this tab
      await tester.pump();

      final bucketField = find.widgetWithText(TextField, s3.bucket);
      expect(bucketField, findsWidgets);
      await tester.enterText(bucketField.first, 'new-bucket-name');
      expect(s3.bucket, 'new-bucket-name');
    });

    testWidgets('editing the name field renames the connection', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      final conn = c.read(connectionsProvider).connections.first;
      c.read(connectionsProvider.notifier).select(conn);
      await pumpScreen(tester, c, const ConnectionManagerScreen());

      expect(find.text('Connection name'), findsOneWidget);
      final nameField = find.widgetWithText(TextField, conn.name);
      expect(nameField, findsWidgets);
      await tester.enterText(nameField.first, 'My Prod Box');
      await tester.pump();
      expect(conn.name, 'My Prod Box');
      // The sidebar list reflects the new name live.
      expect(find.text('My Prod Box'), findsWidgets);
    });

    testWidgets('the connection log shows lines and Clear empties it', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier).select(c.read(connectionsProvider).connections.first);
      c.read(connectionLogProvider.notifier).info('Testing "box" — sftp://u@h:22 · key');
      await pumpScreen(tester, c, const ConnectionManagerScreen());

      expect(find.text('Connection log'), findsOneWidget);
      expect(find.textContaining('Testing "box"'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('Testing "box"'), findsNothing);
      expect(find.text('Test or connect to see diagnostics here.'), findsOneWidget);
    });

    testWidgets('shows the empty state with no connections', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      expect(find.text('No connections yet'), findsOneWidget);
    });

    testWidgets('deleting a connection asks for confirmation first', (tester) async {
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier).select(c.read(connectionsProvider).connections.first);
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      final count = c.read(connectionsProvider).connections.length;

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('permanently removes the connection'), findsOneWidget);

      // Cancel keeps the connection…
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.read(connectionsProvider).connections.length, count);

      // …confirming removes it.
      await tester.tap(find.text('Delete')); // header button again
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last); // the dialog's confirm button
      await tester.pumpAndSettle();
      expect(c.read(connectionsProvider).connections.length, count - 1);
      await tester.pump(const Duration(seconds: 11)); // drain the toast timer
    });

    testWidgets('groups by tag and filters the list live via search', (tester) async {
      final conns = [
        Connection(id: '1', name: 'Prod SFTP', host: 'prod.example.com', tag: 'Production'),
        Connection(id: '2', name: 'Staging box', host: 'stg.example.com', tag: 'Staging'),
        Connection(id: '3', name: 'Data bucket', protocol: Protocol.s3, bucket: 'acme', tag: 'Production'),
      ];
      final c = makeContainer(connections: conns);
      await pumpScreen(tester, c, const ConnectionManagerScreen());

      // Sidebar is grouped by tag (group headers are sidebar-only).
      expect(find.text('PRODUCTION'), findsOneWidget);
      expect(find.text('STAGING'), findsOneWidget);

      // The search box is the first TextField (sidebar precedes the form).
      final search = find.byType(TextField).first;
      await tester.enterText(search, 'staging');
      await tester.pump();
      expect(find.text('STAGING'), findsOneWidget);
      expect(find.text('PRODUCTION'), findsNothing); // filtered out
      expect(find.text('Staging box'), findsOneWidget);

      // A query with no hits shows the empty note.
      await tester.enterText(search, 'zzzz');
      await tester.pump();
      expect(find.textContaining('No matches'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a narrow window', (tester) async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(520, 820);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
      addTearDown(() => binding.platformDispatcher.views.first.resetPhysicalSize());
      final c = makeContainer(connections: sampleConnections());
      c.read(connectionsProvider.notifier)
          .select(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));
      await pumpScreen(tester, c, const ConnectionManagerScreen());
      // A RenderFlex overflow would throw and fail the test.
      expect(tester.takeException(), isNull);
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

    testWidgets('the filter field narrows the visible transfers live', (tester) async {
      final c = makeContainer();
      c.read(transfersProvider.notifier).debugSetTransfers([
        t('report.pdf', TransferStatus.queued),
        t('backup.tar', TransferStatus.queued),
      ]);
      await pumpScreen(tester, c, const TransferQueueScreen());
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('backup.tar'), findsOneWidget);

      // Case-insensitive substring match against name/paths/session.
      final filter = find.byType(TextField).first; // header filter box
      await tester.enterText(filter, 'REPORT');
      await tester.pump();
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('backup.tar'), findsNothing);

      // No hits → a note instead of an empty table.
      await tester.enterText(filter, 'zzzz');
      await tester.pump();
      expect(find.textContaining('No transfers match'), findsOneWidget);

      // The ✕ affordance clears the filter.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('backup.tar'), findsOneWidget);
    });

    testWidgets('Threads field keeps an in-progress edit across live ticks', (tester) async {
      final c = makeContainer();
      c.read(transfersProvider.notifier)
          .debugSetTransfers([t('moving.bin', TransferStatus.active)]);
      await pumpScreen(tester, c, const TransferQueueScreen());

      // The threads box shows the current max (default 5).
      final threads = find.widgetWithText(TextField, '5');
      expect(threads, findsOneWidget);
      final ctl = tester.widget<TextField>(threads).controller!;

      // Clear it (an in-progress edit — not a valid number yet), then fire a
      // live progress tick, which rebuilds the stats bar.
      await tester.enterText(threads, '');
      c.read(transfersProvider).transfers.first.touchLive();
      await tester.pump();

      // The focused field keeps the edit instead of resetting to '5'.
      expect(ctl.text, '');
      expect(find.widgetWithText(TextField, '5'), findsNothing);
    });

    testWidgets('tapping a transfer row opens its details panel', (tester) async {
      final c = makeContainer();
      c.read(transfersProvider.notifier).debugSetTransfers([
        Transfer(
          name: 'photo.png',
          route: 'Local → s3://b/',
          direction: TransferDirection.upload,
          sizeBytes: 2048,
          session: 'sess',
          status: TransferStatus.error,
          errorMessage: 'timeout',
          sourcePath: '/home/u/photo.png',
          destPath: 's3://b/photo.png',
          attempts: 3,
        ),
      ]);
      await pumpScreen(tester, c, const TransferQueueScreen());

      await tester.tap(find.text('photo.png')); // the row
      await tester.pumpAndSettle();

      // The panel shows full details + the relevant action.
      expect(find.text('Direction'), findsOneWidget);
      expect(find.text('/home/u/photo.png'), findsOneWidget);
      expect(find.text('timeout'), findsWidgets); // error surfaced
      expect(find.text('Retry'), findsOneWidget); // error → retry action
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Direction'), findsNothing);
    });
  });

  group('Settings', () {
    testWidgets('Fingerprints section renders on the page', (tester) async {
      final c = makeContainer(); // no known-hosts store ⇒ "unavailable" notice
      await pumpScreen(tester, c, const SettingsScreen());
      // No tab to click — the section is on the single page.
      expect(find.text('Trusted SSH host keys'), findsOneWidget);
      expect(find.text('Host-key storage is unavailable.'), findsOneWidget);
    });

    testWidgets('renders appearance options', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('UI font'), findsOneWidget);
      expect(find.text('Monospace font'), findsOneWidget);
    });

    testWidgets('picking a bird theme recolors and persists', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      expect(c.read(settingsProvider).themeName, 'Rainbow Bee-eater');
      await tester.tap(find.text('Galah'));
      await tester.pump();
      expect(c.read(settingsProvider).themeName, 'Galah');
      // The accent is the seed-derived Material 3 primary for the bird's colour.
      final cs = ColorScheme.fromSeed(
          seedColor: birdThemeByName('Galah').primary, brightness: Brightness.light);
      expect(c.read(settingsProvider).accentValue, cs.primary.toARGB32());
      await tester.pump(const Duration(seconds: 11)); // drain the toast timer
    });

    testWidgets('every section renders on one page (no tabs)', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      // All section headers and their controls are present simultaneously.
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Show hidden files'), findsOneWidget);
      expect(find.text('Show transfer log on startup'), findsOneWidget);
      // No Save button — settings persist as they change, and the page says so.
      expect(find.text('Changes are saved automatically'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('toggling a checkbox updates settings', (tester) async {
      final c = makeContainer();
      await pumpScreen(tester, c, const SettingsScreen());
      expect(c.read(settingsProvider).showLogOnStartup, isFalse);
      // Tap the labelled row directly — no tab to switch to anymore.
      final row = find.text('Show transfer log on startup');
      await tester.ensureVisible(row);
      await tester.tap(row);
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
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
