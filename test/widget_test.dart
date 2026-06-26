import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drag/data/known_hosts_store.dart';
import 'package:drag/fs/host_key_verifier.dart';
import 'package:drag/main.dart';
import 'package:drag/state/app.dart';
import 'package:drag/widgets/nav_rail.dart';

void main() {
  setUp(() {
    // Drag is a wide desktop layout; give the test a realistic window.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1320, 860);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
  });

  Widget app() => ProviderScope(
        // Avoid real filesystem I/O during the boot test.
        overrides: [autoRefreshPanesProvider.overrideWithValue(false)],
        child: const DragApp(),
      );

  testWidgets('Drag boots into the dual-pane browser (Local ⇄ Local)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    // The session tab strip reflects the active session — a fresh Local tab.
    // (The "Drag — Local" window title now lives in the native title bar.)
    expect(find.text('Local'), findsWidgets);
    // Both panes default to the Local endpoint on a clean install.
    expect(find.text('LOCAL'), findsWidgets);
    expect(find.text('S3'), findsNothing);
  });

  testWidgets('Navigation rail switches to the transfer queue', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(NavRail), findsOneWidget);

    final context = tester.element(find.byType(NavRail));
    final container = ProviderScope.containerOf(context);
    container.read(navProvider.notifier).go(AppScreen.queue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Stats footer of the queue screen.
    expect(find.text('Total queued'), findsOneWidget);
  });

  testWidgets('Navigation rail opens the About screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    final context = tester.element(find.byType(NavRail));
    final container = ProviderScope.containerOf(context);
    container.read(navProvider.notifier).go(AppScreen.about);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('What is Drag?'), findsOneWidget);
    expect(find.text('What it does'), findsOneWidget);
    expect(find.text('Under the hood'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
  });

  testWidgets('AppShell registers the SFTP host-key prompt on mount (any screen)', (tester) async {
    // Open the real (in-memory) store outside the fake-async zone — awaiting
    // sqflite I/O directly inside testWidgets would deadlock.
    late final KnownHostsStore store;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      store = await KnownHostsStore.open(inMemoryDatabasePath);
    });
    globalHostKeyVerifier = HostKeyVerifier(store);
    addTearDown(() => globalHostKeyVerifier = null);

    // No prompt before the shell mounts — a connection now would auto-trust.
    expect(globalHostKeyVerifier!.prompt, isNull);
    await tester.pumpWidget(app());
    await tester.pump();
    // The always-mounted shell wired the interactive prompt, so connections
    // from the Connection Manager (or anywhere) are covered, not just Browser.
    expect(globalHostKeyVerifier!.prompt, isNotNull);
  });
}
