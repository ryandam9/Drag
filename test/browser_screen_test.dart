import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/screens/browser_screen.dart';
import 'package:drag/state/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/memory_backend.dart';

void main() {
  setUp(() {
    final b = TestWidgetsFlutterBinding.ensureInitialized();
    b.platformDispatcher.views.first.physicalSize = const Size(1900, 1000);
    b.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .resetPhysicalSize();
  });

  /// Both panes on in-memory backends (no disk I/O → resolves under fake-async).
  Future<(ProviderContainer, MemoryBackend, MemoryBackend)> setup(WidgetTester tester,
      {String leftPath = '/'}) async {
    final c = makeContainer(connections: sampleConnections());
    final s = c.read(sessionsProvider.notifier);
    final left = MemoryBackend.sample();
    final right = MemoryBackend();
    s.leftPane
      ..backend = left
      ..path = leftPath;
    await s.leftPane.refresh();
    s.rightPane
      ..backend = right
      ..connection = null
      ..path = '/';
    await s.rightPane.refresh();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
    ));
    await tester.pump();
    return (c, left, right);
  }

  testWidgets('renders panes, toolbar, file rows and the idle queue strip', (tester) async {
    final (_, _, _) = await setup(tester);
    expect(find.text('LOCAL'), findsWidgets);
    expect(find.text('⊕ New Folder'), findsOneWidget);
    expect(find.text('↑ Up'), findsOneWidget);
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.text('beta.bin'), findsOneWidget);
    expect(find.text('nested'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('tapping a file selects it', (tester) async {
    final (c, _, _) = await setup(tester);
    await tester.tap(find.text('alpha.txt'));
    await tester.pump();
    expect(c.read(sessionsProvider.notifier).leftPane.selectedItems().map((e) => e.name),
        contains('alpha.txt'));
  });

  testWidgets('toolbar Up navigates the focused pane to its parent', (tester) async {
    final (c, _, _) = await setup(tester, leftPath: '/nested');
    final pane = c.read(sessionsProvider.notifier).leftPane;
    expect(pane.path, '/nested');
    await tester.tap(find.text('↑ Up'));
    await tester.pumpAndSettle();
    expect(pane.path, '/');
  });

  testWidgets('New Folder dialog creates a directory', (tester) async {
    final (c, left, _) = await setup(tester);
    await tester.tap(find.text('⊕ New Folder'));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);
    final dialogField =
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, 'created_dir');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('created_dir'), findsOneWidget);
    expect((await left.list('/')).any((e) => e.name == 'created_dir'), isTrue);
    await tester.pump(const Duration(seconds: 6)); // drain the success-toast timer
  });

  testWidgets('F2 with nothing selected shows an info toast', (tester) async {
    final (c, _, _) = await setup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(c.read(toastsProvider).last.title, 'Nothing selected');
    await tester.pump(const Duration(seconds: 6)); // drain the toast timer
  });

  testWidgets('endpoint picker offers Local plus every saved connection', (tester) async {
    final (c, _, _) = await setup(tester);
    final picker = tester.widget<DropdownButton<Connection?>>(
        find.byType(DropdownButton<Connection?>).first);
    final values = picker.items!.map((i) => i.value).toList();
    // Local (null) + the three sample connections.
    expect(values.length, 1 + c.read(connectionsProvider).connections.length);
    expect(values, contains(null));
    expect(values.whereType<Connection>().map((x) => x.name),
        contains('s3-prod (Account A)'));
  });

  testWidgets('queue strip surfaces the active transfer', (tester) async {
    final c = makeContainer(connections: sampleConnections());
    final s = c.read(sessionsProvider.notifier);
    s.leftPane..backend = MemoryBackend.sample()..path = '/';
    await s.leftPane.refresh();
    c.read(transfersProvider.notifier).debugSetTransfers([
      Transfer(
          name: 'moving.bin',
          route: 'Local → s3',
          direction: TransferDirection.upload,
          sizeBytes: 1000,
          session: 's',
          status: TransferStatus.active,
          progress: 0.5,
          speed: '1.0 MB/s'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: BrowserScreen())),
    ));
    await tester.pump();
    expect(find.textContaining('Transferring — moving.bin'), findsOneWidget);
  });

  testWidgets('the log panel toggles from the toolbar', (tester) async {
    await setup(tester);
    expect(find.text('Local endpoint ready'), findsNothing);
    await tester.tap(find.text('📋 Log'));
    await tester.pump();
    expect(find.text('Local endpoint ready'), findsOneWidget);
  });

  testWidgets('session tabs reflect open sessions and can be closed', (tester) async {
    final (c, _, _) = await setup(tester);
    final s = c.read(sessionsProvider.notifier);
    s.openSession(c.read(connectionsProvider).connections.firstWhere((x) => x.isS3));
    await tester.pump();
    expect(find.text('s3-prod (Account A)'), findsWidgets);
    expect(c.read(sessionsProvider).sessions.length, 2);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(c.read(sessionsProvider).sessions.length, 1);
  });

  testWidgets('clicking the New Session + opens the connection manager', (tester) async {
    final (c, _, _) = await setup(tester);
    await tester.tap(find.text('＋').first);
    await tester.pump();
    expect(c.read(navProvider), AppScreen.connections);
  });

  testWidgets('F2 renames the selected file', (tester) async {
    final (c, left, _) = await setup(tester);
    await tester.tap(find.text('alpha.txt'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsWidgets);
    final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'renamed.txt');
    await tester.tap(find.text('Rename').last); // the confirm button (title is also 'Rename')
    await tester.pumpAndSettle();
    expect((await left.list('/')).any((e) => e.name == 'renamed.txt'), isTrue);
    expect((await left.list('/')).any((e) => e.name == 'alpha.txt'), isFalse);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Delete key removes the selected file after confirmation', (tester) async {
    final (c, left, _) = await setup(tester);
    await tester.tap(find.text('beta.bin'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    // Confirmation dialog.
    expect(find.textContaining('Delete "beta.bin"'), findsOneWidget);
    await tester.tap(find.text('Delete')); // the dialog's confirm button
    await tester.pumpAndSettle();
    expect((await left.list('/')).any((e) => e.name == 'beta.bin'), isFalse);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('double-tapping a folder opens it', (tester) async {
    final (c, _, _) = await setup(tester);
    final pane = c.read(sessionsProvider.notifier).leftPane;
    await tester.tap(find.text('nested'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('nested'));
    await tester.pumpAndSettle();
    expect(pane.path, '/nested');
    expect(find.text('inner.txt'), findsOneWidget);
  });

  testWidgets('arrow keys move the selection and Enter opens a folder', (tester) async {
    final (c, _, _) = await setup(tester);
    final pane = c.read(sessionsProvider.notifier).leftPane;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(pane.selectedIndex, 0);
    expect(pane.items[0].name, 'nested'); // dirs sort first
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pane.path, '/nested');
    expect(find.text('inner.txt'), findsOneWidget);
  });

  testWidgets('Tab switches the focused pane', (tester) async {
    final (c, _, _) = await setup(tester);
    expect(c.read(sessionsProvider).focusedLeft, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.read(sessionsProvider).focusedLeft, isFalse);
  });

  testWidgets('Space opens a preview popup for the selected file', (tester) async {
    await setup(tester);
    await tester.tap(find.text('alpha.txt'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    // The popup shows the file name as a title and a Close action.
    expect(find.text('alpha.txt'), findsWidgets); // row + dialog title
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('type-ahead jumps to the matching row', (tester) async {
    final (c, _, _) = await setup(tester);
    final pane = c.read(sessionsProvider.notifier).leftPane;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(pane.items[pane.selectedIndex!].name, 'beta.bin');
  });

  testWidgets('dragging a file onto the other pane transfers it', (tester) async {
    final (c, _, right) = await setup(tester);
    expect((await right.list('/')).any((e) => e.name == 'alpha.txt'), isFalse);

    await tester.drag(find.text('alpha.txt'), const Offset(1100, 0));
    await tester.pumpAndSettle();

    // Let the streamed copy finish.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect((await right.list('/')).any((e) => e.name == 'alpha.txt'), isTrue);
    await tester.pump(const Duration(seconds: 6));
  });
}
