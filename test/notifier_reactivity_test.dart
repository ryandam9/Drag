import 'dart:async';

import 'package:drag/data/history_db.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/state/app.dart';
import 'package:drag/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/harness.dart';

/// Verifies the reactive wiring end-to-end: a widget that `ref.watch`es every
/// notifier must rebuild — with the new value — whenever that notifier mutates
/// its state. This proves `state = ...` actually notifies listeners.
void main() {
  testWidgets('every notifier rebuilds its watchers with updated state', (
    tester,
  ) async {
    final c = makeContainer(connections: sampleConnections());
    var builds = 0;
    String? rendered;

    final probe = Consumer(
      builder: (ctx, ref, _) {
        builds++;
        final nav = ref.watch(navProvider);
        final toasts = ref.watch(toastsProvider).length;
        final font = ref.watch(settingsProvider).uiFontSize;
        final sel = ref.watch(connectionsProvider).selected?.name ?? '-';
        final sessions = ref.watch(sessionsProvider).sessions.length;
        final transfers = ref.watch(transfersProvider).transfers.length;
        ref.watch(historyProvider); // build it too (no repo → no async refresh)
        rendered =
            'nav=$nav toasts=$toasts font=$font sel=$sel sessions=$sessions transfers=$transfers';
        return Text(rendered!, textDirection: TextDirection.ltr);
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: probe),
    );
    await tester.pump();

    // Helper: run a mutation, pump, and assert the watcher rebuilt.
    Future<void> step(
      String label,
      void Function() mutate,
      String expectFragment,
    ) async {
      final before = builds;
      mutate();
      await tester.pump();
      expect(builds, greaterThan(before), reason: 'no rebuild after $label');
      expect(
        rendered,
        contains(expectFragment),
        reason: 'stale state after $label',
      );
    }

    await step(
      'nav.go',
      () => c.read(navProvider.notifier).go(AppScreen.queue),
      'nav=AppScreen.queue',
    );
    await step(
      'toasts.push',
      () => c.read(toastsProvider.notifier).push('t', 's', ToastKind.info),
      'toasts=1',
    );
    await step(
      'settings.setUiFontSize',
      () => c.read(settingsProvider.notifier).setUiFontSize(14),
      'font=14.0',
    );
    await step(
      'connections.create',
      () => c.read(connectionsProvider.notifier).create(),
      'sel=New connection',
    );
    await step(
      'sessions.openSession',
      () => c
          .read(sessionsProvider.notifier)
          .openSession(
            c.read(connectionsProvider).connections.firstWhere((x) => x.isS3),
          ),
      'sessions=2',
    );
    await step(
      'transfers.debugSetTransfers',
      () => c.read(transfersProvider.notifier).debugSetTransfers([
        Transfer(
          name: 'f',
          route: 'r',
          direction: TransferDirection.upload,
          sizeBytes: 1,
          session: 's',
        ),
      ]),
      'transfers=1',
    );

    // Drain the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 11));
  });

  test('container.listen receives an emission from every notifier', () async {
    final c = makeContainer(connections: sampleConnections());
    final repo = await HistoryRepository.open(inMemoryDatabasePath);
    addTearDown(repo.close);
    final ch = makeContainer(connections: sampleConnections(), history: repo);

    int fired;

    fired = 0;
    c.listen(navProvider, (_, _) => fired++);
    c.read(navProvider.notifier).go(AppScreen.dashboard);
    expect(fired, 1, reason: 'navProvider did not emit');

    fired = 0;
    c.listen(toastsProvider, (_, _) => fired++);
    c.read(toastsProvider.notifier).push('a', 'b', ToastKind.info);
    expect(fired, 1, reason: 'toastsProvider did not emit');

    fired = 0;
    c.listen(settingsProvider, (_, _) => fired++);
    c.read(settingsProvider.notifier).setTheme(birdThemeByName('Galah'));
    expect(fired, 1, reason: 'settingsProvider did not emit');

    fired = 0;
    c.listen(connectionsProvider, (_, _) => fired++);
    unawaited(c.read(connectionsProvider.notifier).create());
    expect(fired, 1, reason: 'connectionsProvider did not emit');

    fired = 0;
    c.listen(sessionsProvider, (_, _) => fired++);
    c.read(sessionsProvider.notifier).focusPane(false);
    expect(fired, 1, reason: 'sessionsProvider did not emit');

    fired = 0;
    c.listen(transfersProvider, (_, _) => fired++);
    c.read(transfersProvider.notifier).setMaxThreads(8);
    expect(fired, 1, reason: 'transfersProvider did not emit');

    // history uses a real (in-memory) repo so its async refresh can run.
    fired = 0;
    ch.listen(historyProvider, (_, _) => fired++);
    await ch.read(historyProvider.notifier).clear();
    expect(
      fired,
      greaterThanOrEqualTo(1),
      reason: 'historyProvider did not emit',
    );
  });
}
