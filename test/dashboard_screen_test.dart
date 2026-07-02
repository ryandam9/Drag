import 'package:drag/screens/dashboard_screen.dart';
import 'package:drag/state/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  setUp(() {
    final b = TestWidgetsFlutterBinding.ensureInitialized();
    b.platformDispatcher.views.first.physicalSize = const Size(1500, 940);
    b.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
        .resetPhysicalSize();
  });

  // No HistoryRepository: the dashboard renders with empty history (its real
  // SQLite I/O wouldn't resolve under the widget tester's async zone anyway).
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('shows an Export CSV action', (tester) async {
    await pump(tester);
    expect(find.text('⬇ Export CSV'), findsOneWidget);
  });

  testWidgets('exporting empty history reports nothing to export', (
    tester,
  ) async {
    final c = await pump(tester);

    await tester.tap(find.text('⬇ Export CSV'));
    await tester.pump();

    expect(c.read(toastsProvider).last.title, 'Nothing to export');
    await tester.pump(const Duration(seconds: 11)); // drain the toast timer
  });
}
