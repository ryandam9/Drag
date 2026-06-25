import 'dart:io';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/transfer.dart';
import 'package:drag/platform/desktop_notifications.dart';
import 'package:drag/state/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

/// Captures notifications instead of calling the native plugin.
class _FakeNotifications extends DesktopNotifications {
  final List<(String, String)> shown = [];
  @override
  Future<void> show(String title, String body, {VoidCallback? onClick}) async {
    shown.add((title, body));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldNotify', () {
    test('only when enabled and the window is unfocused', () {
      expect(shouldNotify(enabled: true, windowFocused: false), isTrue);
      expect(shouldNotify(enabled: true, windowFocused: true), isFalse);
      expect(shouldNotify(enabled: false, windowFocused: false), isFalse);
      expect(shouldNotify(enabled: false, windowFocused: true), isFalse);
    });
  });

  group('transfer-finished notification', () {
    late _FakeNotifications fake;
    setUp(() {
      fake = _FakeNotifications();
      gDesktopNotifications = fake;
      gWindowFocused = false;
    });
    tearDown(() {
      gDesktopNotifications = null;
      gWindowFocused = true;
    });

    Future<Transfer> runOne(ProviderContainer c) async {
      final s = c.read(sessionsProvider.notifier);
      final src = await Directory.systemTemp.createTemp('ntf_src');
      final dst = await Directory.systemTemp.createTemp('ntf_dst');
      addTearDown(() => src.delete(recursive: true));
      addTearDown(() => dst.delete(recursive: true));
      await File(p.join(src.path, 'a.bin')).writeAsBytes(List.filled(512, 1));
      s.leftPane
        ..backend = LocalBackend()
        ..path = src.path;
      await s.leftPane.refresh();
      s.rightPane
        ..backend = LocalBackend()
        ..connection = null
        ..path = dst.path;
      await s.rightPane.refresh();
      final item = s.leftPane.items.firstWhere((e) => e.name == 'a.bin');
      s.dropTransfer(DragPayload(item, true), false);
      final t = c.read(transfersProvider).transfers.first;
      for (var i = 0; i < 300 && t.status != TransferStatus.done && t.status != TransferStatus.error; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // The completion callback (record / notify) runs after `run()` resolves —
      // let that microtask chain flush before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return t;
    }

    test('notifies on completion when unfocused and enabled', () async {
      final c = makeContainer(settings: AppSettings(notifyOnComplete: true));
      final t = await runOne(c);
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(fake.shown.length, 1);
      expect(fake.shown.first.$1, 'Transfer complete');
    });

    test('does not notify while the window is focused', () async {
      gWindowFocused = true;
      final c = makeContainer(settings: AppSettings(notifyOnComplete: true));
      final t = await runOne(c);
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(fake.shown, isEmpty);
    });

    test('does not notify when the setting is off', () async {
      final c = makeContainer(settings: AppSettings(notifyOnComplete: false));
      final t = await runOne(c);
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(fake.shown, isEmpty);
    });
  });
}
