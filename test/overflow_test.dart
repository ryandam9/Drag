// Overflow / responsive guards (#48): pump the dense screens at the app's
// minimum supported window size (and at a larger text scale) and assert nothing
// overflows. These catch RenderFlex overflow regressions on the layout-heavy
// screens without the platform-fragility of pixel golden files.
import 'package:drag/models/transfer.dart';
import 'package:drag/screens/connection_manager_screen.dart';
import 'package:drag/screens/dashboard_screen.dart';
import 'package:drag/screens/settings_screen.dart';
import 'package:drag/screens/transfer_queue_screen.dart';
import 'package:drag/state/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  // The documented minimum window content size (see AppShell minimumSize).
  const minSize = Size(880, 600);

  Future<void> pumpAt(
    WidgetTester tester,
    ProviderContainer c,
    Widget screen, {
    Size size = minSize,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Transfer t(String name, TransferStatus s) => Transfer(
    name: name,
    route: 'Local → s3://bucket/very/long/destination/path/here',
    direction: TransferDirection.upload,
    sizeBytes: 248 * 1024 * 1024,
    session: 's',
    status: s,
  );

  testWidgets('Transfer Queue fits at the minimum size', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      t('backup_2025-06-19.tar.gz', TransferStatus.active),
      t(
        'a-rather-long-file-name-that-could-overflow.bin',
        TransferStatus.error,
      ),
      t('server.js', TransferStatus.done),
    ]);
    await pumpAt(tester, c, const TransferQueueScreen());
  });

  testWidgets('Transfer Queue fits at a larger text scale', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      t('x.bin', TransferStatus.active),
    ]);
    await pumpAt(tester, c, const TransferQueueScreen(), textScale: 1.3);
  });

  testWidgets('Dashboard fits at the minimum size', (tester) async {
    final c = makeContainer();
    await pumpAt(tester, c, const DashboardScreen());
  });

  testWidgets('Connection Manager fits at the minimum size', (tester) async {
    final c = makeContainer(connections: sampleConnections());
    c
        .read(connectionsProvider.notifier)
        .select(c.read(connectionsProvider).connections.first);
    await pumpAt(tester, c, const ConnectionManagerScreen());
  });

  testWidgets('Settings fits at the minimum size', (tester) async {
    final c = makeContainer();
    await pumpAt(tester, c, const SettingsScreen());
  });
}
