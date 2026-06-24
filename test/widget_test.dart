import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    // Title bar reflects the active session — a fresh Local tab.
    expect(find.textContaining('Drag — Local'), findsOneWidget);
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
}
