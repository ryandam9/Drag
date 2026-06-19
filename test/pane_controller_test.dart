import 'dart:io';
import 'dart:ui';

import 'package:drag/fs/simulated_backend.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/state/pane_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fs_pane');
    await File(p.join(dir.path, 'a.txt')).writeAsString('a');
    await Directory(p.join(dir.path, 'nested')).create();
    await File(p.join(dir.path, 'nested', 'b.txt')).writeAsString('b');
  });
  tearDown(() => dir.delete(recursive: true));

  PaneController localPane({VoidCallback? onChanged}) {
    final pc = PaneController(backend: LocalBackend(), onChanged: onChanged ?? () {});
    pc.path = dir.path;
    return pc;
  }

  test('refresh populates items and clears loading/error', () async {
    var notified = 0;
    final pane = localPane(onChanged: () => notified++);
    await pane.refresh();
    expect(pane.loading, isFalse);
    expect(pane.error, isNull);
    expect(pane.items.map((e) => e.name), containsAll(['a.txt', 'nested']));
    expect(notified, greaterThan(0));
  });

  test('open() navigates into a directory and back via ..', () async {
    final pane = localPane();
    await pane.refresh();

    final nested = pane.items.firstWhere((e) => e.name == 'nested');
    await pane.open(nested);
    expect(pane.path, p.join(dir.path, 'nested'));
    expect(pane.items.any((e) => e.name == 'b.txt'), isTrue);

    final parent = pane.items.firstWhere((e) => e.isParent);
    await pane.open(parent);
    expect(pane.path, dir.path);
  });

  test('open() on a file is a no-op', () async {
    final pane = localPane();
    await pane.refresh();
    final before = pane.path;
    await pane.open(pane.items.firstWhere((e) => e.name == 'a.txt'));
    expect(pane.path, before);
  });

  test('goUp moves to the parent directory', () async {
    final pane = localPane();
    await pane.refresh();
    await pane.goUp();
    expect(pane.path, p.dirname(dir.path));
  });

  test('back / forward navigation history', () async {
    final pane = localPane();
    await pane.refresh();
    expect(pane.canGoBack, isFalse);

    final nested = pane.items.firstWhere((e) => e.name == 'nested');
    await pane.open(nested); // dir -> nested
    expect(pane.canGoBack, isTrue);
    expect(pane.canGoForward, isFalse);

    await pane.goBack();
    expect(pane.path, dir.path);
    expect(pane.canGoForward, isTrue);

    await pane.goForward();
    expect(pane.path, p.join(dir.path, 'nested'));

    // A fresh navigation clears the forward stack.
    await pane.goBack();
    await pane.open(nested);
    expect(pane.canGoForward, isFalse);
  });

  test('multi-select: single / toggle / range / clear-on-refresh', () async {
    final pane = localPane();
    await pane.refresh();
    final iA = pane.items.indexWhere((e) => e.name == 'a.txt');
    final iN = pane.items.indexWhere((e) => e.name == 'nested');

    pane.select(iA);
    expect(pane.selection, {iA});

    pane.toggleSelect(iN);
    expect(pane.selection.containsAll({iA, iN}), isTrue);
    expect(pane.selectedItems().map((e) => e.name), containsAll(['a.txt', 'nested']));

    pane.toggleSelect(iA);
    expect(pane.isSelected(iA), isFalse);

    pane.select(iN);
    pane.selectRange(iA);
    expect(pane.selection.length, (iA - iN).abs() + 1);

    await pane.refresh();
    expect(pane.selection, isEmpty);
  });

  test('select updates index and notifies', () {
    var notified = 0;
    final pane = localPane(onChanged: () => notified++);
    pane.select(3);
    expect(pane.selectedIndex, 3);
    expect(notified, 1);
  });

  test('hidden-file filter hides/show dot-files and clears selection', () async {
    await File(p.join(dir.path, '.secret')).writeAsString('x');
    final pane = localPane();
    await pane.refresh();
    // Shown by default.
    expect(pane.items.any((e) => e.name == '.secret'), isTrue);

    pane.select(0);
    pane.setShowHidden(false);
    expect(pane.items.any((e) => e.name == '.secret'), isFalse);
    // Visible (non-dot) entries remain.
    expect(pane.items.any((e) => e.name == 'a.txt'), isTrue);
    // Toggling re-filters and clears the now-stale selection.
    expect(pane.selection, isEmpty);

    pane.setShowHidden(true);
    expect(pane.items.any((e) => e.name == '.secret'), isTrue);
  });

  test('hidden filter set before refresh applies on first listing', () async {
    await File(p.join(dir.path, '.env')).writeAsString('x');
    final pane = PaneController(
        backend: LocalBackend(), onChanged: () {}, showHidden: false)
      ..path = dir.path;
    await pane.refresh();
    expect(pane.items.any((e) => e.name == '.env'), isFalse);
    // '..' parent entry is never filtered.
    expect(pane.items.where((e) => e.isParent).length, lessThanOrEqualTo(1));
  });

  test('not-ready backend short-circuits refresh with empty items', () async {
    final pane = PaneController(
      backend: S3Backend(Connection(name: 's', protocol: Protocol.s3, bucket: 'b')),
      connection: Connection(name: 's', protocol: Protocol.s3, bucket: 'b'),
      onChanged: () {},
    );
    await pane.refresh();
    expect(pane.isReady, isFalse);
    expect(pane.items, isEmpty);
    expect(pane.error, isNull);
  });

  test('breadcrumb head reflects endpoint type', () async {
    final local = localPane();
    expect(local.breadcrumb.first, '~');

    final s3conn = Connection(name: 's3', protocol: Protocol.s3, bucket: 'my-bucket');
    final s3 = PaneController(backend: S3Backend(s3conn), connection: s3conn, onChanged: () {});
    expect(s3.breadcrumb.first, 'my-bucket');

    final sftpConn = Connection(name: 'h', protocol: Protocol.sftp, remotePath: '/srv');
    final sftp = PaneController(backend: SimulatedBackend(sftpConn), connection: sftpConn, onChanged: () {});
    expect(sftp.breadcrumb.first, '/');
  });

  test('switchTo swaps backend, resets path and lists', () async {
    final pane = localPane();
    await pane.refresh();
    final sftpConn = Connection(name: 'h', protocol: Protocol.sftp, remotePath: '/srv');
    await pane.switchTo(SimulatedBackend(sftpConn), sftpConn);
    expect(pane.kind, EndpointKind.sftp);
    expect(pane.path, '/srv');
    expect(pane.items, isNotEmpty);
  });

  test('endpointLabel falls back to Local', () {
    expect(localPane().endpointLabel, 'Local');
  });
}
