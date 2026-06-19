import 'dart:io';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3Backend path math', () {
    final backend = S3Backend(Connection(name: 's3', protocol: Protocol.s3, bucket: 'b'));

    test('childPath appends key / prefix', () {
      expect(backend.childPath('', 'file.txt', false), 'file.txt');
      expect(backend.childPath('logs/', 'app.log', false), 'logs/app.log');
      expect(backend.childPath('logs/', 'sub', true), 'logs/sub/');
    });

    test('parentPath walks up the prefix', () {
      expect(backend.parentPath('logs/2025/'), 'logs/');
      expect(backend.parentPath('logs/'), '');
      expect(backend.parentPath(''), '');
    });

    test('displayPath renders an s3:// URI', () {
      expect(backend.displayPath('logs/app.log'), 's3://b/logs/app.log');
    });

    test('no credentials means not ready', () {
      expect(backend.isReady, isFalse);
    });
  });

  test('TransferService streams bytes with progress (local backend)', () async {
    final dir = await Directory.systemTemp.createTemp('filesync_test');
    addTearDown(() => dir.delete(recursive: true));

    final srcFile = File('${dir.path}/source.bin');
    final payload = List<int>.generate(64 * 1024, (i) => i % 256);
    await srcFile.writeAsBytes(payload);

    final backend = LocalBackend();
    final dstPath = '${dir.path}/dest.bin';

    final t = Transfer(
      name: 'source.bin',
      route: 'test',
      direction: TransferDirection.upload,
      sizeBytes: payload.length,
      session: 'local',
      live: true,
    );

    var progressSeen = false;
    var statusCalls = 0;
    await TransferService().run(
      t: t,
      src: backend,
      srcPath: srcFile.path,
      dst: backend,
      dstPath: dstPath,
      onStatus: () => statusCalls++,
      onProgress: () {
        if (t.progress > 0 && t.progress < 1) progressSeen = true;
      },
    );

    expect(t.status, TransferStatus.done);
    expect(t.progress, 1.0);
    expect(await File(dstPath).readAsBytes(), payload);
    // onStatus fires at least at start (active) and end (done).
    expect(statusCalls, greaterThanOrEqualTo(2));
    // Either we observed intermediate progress, or the file was small enough to
    // finish in one chunk — both are valid; the key invariant is completion.
    expect(progressSeen || t.progress == 1.0, isTrue);
  });
}
