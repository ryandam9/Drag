import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:filesync/main.dart';
import 'package:filesync/state/app_state.dart';
import 'package:filesync/widgets/nav_rail.dart';

void main() {
  setUp(() {
    // FileSync is a wide desktop layout; give the test a realistic window.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1320, 860);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
  });

  testWidgets('FileSync boots into the dual-pane browser', (tester) async {
    await tester.pumpWidget(const FileSyncApp());
    await tester.pump();

    // Title bar shows the active SFTP session.
    expect(find.textContaining('FileSync — prod-server-01'), findsOneWidget);
    // Both panes are present.
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('REMOTE'), findsOneWidget);
  });

  testWidgets('Navigation rail switches to the transfer queue', (tester) async {
    await tester.pumpWidget(const FileSyncApp());
    await tester.pump();

    expect(find.byType(NavRail), findsOneWidget);

    final context = tester.element(find.byType(NavRail));
    AppScope.of(context).go(AppScreen.queue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Stats footer of the queue screen.
    expect(find.text('Total queued'), findsOneWidget);
  });
}
