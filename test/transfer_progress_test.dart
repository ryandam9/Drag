import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:drag/widgets/transfer_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _mB = 1024 * 1024;

Transfer _active({
  required String name,
  required int size,
  double progress = 0.5,
  String speed = '2.0 MB/s',
  String eta = '0:30',
  TransferDirection dir = TransferDirection.upload,
}) =>
    Transfer(
        name: name,
        route: 'Local → s3://bucket/$name',
        direction: dir,
        sizeBytes: size,
        session: 's',
        status: TransferStatus.active,
        progress: progress,
        speed: speed,
        eta: eta);

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      home: Scaffold(body: Stack(children: [ActiveTransferOverlay()])),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() {
    final b = TestWidgetsFlutterBinding.ensureInitialized();
    b.platformDispatcher.views.first.physicalSize = const Size(1000, 800);
    b.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .resetPhysicalSize();
  });

  testWidgets('renders nothing when no transfer is active', (tester) async {
    final c = makeContainer();
    await _pump(tester, c);
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);
  });

  testWidgets('shows the big-file card with ring %, speed and ETA', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      _active(name: 'movie.mkv', size: 200 * _mB, progress: 0.5),
    ]);
    await _pump(tester, c);

    expect(find.text('movie.mkv'), findsOneWidget);
    expect(find.text('⬆ Big file'), findsOneWidget);
    expect(find.text('2.0 MB/s'), findsOneWidget);
    expect(find.text('ETA 0:30'), findsOneWidget);
    expect(find.text('50'), findsOneWidget); // ring percentage
  });

  testWidgets('a small upload shows the Uploading chip', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      _active(name: 'note.txt', size: 1024, progress: 0.3),
    ]);
    await _pump(tester, c);
    expect(find.text('Uploading'), findsOneWidget);
  });

  testWidgets('an indeterminate (0%) transfer shows the … ring', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      _active(name: 'pending.bin', size: 5 * _mB, progress: 0, eta: '—'),
    ]);
    await _pump(tester, c);
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('summarises the count of other active transfers', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      _active(name: 'big.bin', size: 100 * _mB, progress: 0.4),
      _active(name: 'second.bin', size: 50 * _mB, progress: 0.2),
    ]);
    await _pump(tester, c);
    // The largest is shown; the other is summarised.
    expect(find.text('big.bin'), findsOneWidget);
    expect(find.text('+ 1 more transferring…'), findsOneWidget);
  });

  testWidgets('is hidden on the connections and settings screens', (tester) async {
    final c = makeContainer();
    c.read(transfersProvider.notifier).debugSetTransfers([
      _active(name: 'hidden.bin', size: 100 * _mB),
    ]);
    c.read(navProvider.notifier).go(AppScreen.settings);
    await _pump(tester, c);
    expect(find.text('hidden.bin'), findsNothing);

    c.read(navProvider.notifier).go(AppScreen.connections);
    await tester.pump();
    expect(find.text('hidden.bin'), findsNothing);

    // Back on the browser it appears.
    c.read(navProvider.notifier).go(AppScreen.browser);
    await tester.pump();
    expect(find.text('hidden.bin'), findsOneWidget);
  });
}
