import 'dart:io';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('resume'));
  tearDown(() => dir.delete(recursive: true));

  group('LocalBackend ranged reads', () {
    test('openReadRange streams from an offset and reports the remaining size', () async {
      final payload = List<int>.generate(50, (i) => i);
      final f = File('${dir.path}/x.bin')..writeAsBytesSync(payload);
      final b = LocalBackend();
      expect(b.supportsResume, isTrue);

      final h = await b.openReadRange(f.path, 20);
      expect(h.length, 30);
      final got = <int>[];
      await for (final c in h.stream) {
        got.addAll(c);
      }
      expect(got, payload.sublist(20));
    });

    test('a zero offset reads the whole file', () async {
      final payload = List<int>.generate(10, (i) => i);
      final f = File('${dir.path}/y.bin')..writeAsBytesSync(payload);
      final h = await LocalBackend().openReadRange(f.path, 0);
      expect(h.length, 10);
    });
  });

  group('TransferService resume', () {
    Transfer download({int attempts = 0}) => Transfer(
          name: 'dst.bin',
          route: 'r',
          direction: TransferDirection.download,
          sizeBytes: 1000,
          session: 's',
          attempts: attempts,
        );

    test('a retry resumes a partial download instead of restarting', () async {
      final payload = List<int>.generate(1000, (i) => i % 256);
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/dst.bin';
      // A partial left by a previous attempt: the first 400 bytes, in the temp
      // sibling the transfer stages writes in.
      File('$dstPath.drag-partial').writeAsBytesSync(payload.sublist(0, 400));

      final t = download(attempts: 2); // a retry
      await TransferService().run(
        t: t,
        src: LocalBackend(),
        srcPath: src.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        verify: 'size',
      );

      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload); // partial + tail == full
      // The temp file is promoted (renamed), not left behind.
      expect(File('$dstPath.drag-partial').existsSync(), isFalse);
    });

    test('a first attempt overwrites a stale file (no accidental resume)', () async {
      final payload = List<int>.generate(1000, (i) => i % 256);
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/dst.bin';
      // A pre-existing (unrelated) file of the same partial length, all 0xFF.
      File(dstPath).writeAsBytesSync(List.filled(400, 0xFF));

      final t = download(attempts: 1); // first attempt
      await TransferService().run(
        t: t,
        src: LocalBackend(),
        srcPath: src.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        verify: 'size',
      );

      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload); // overwritten, not appended
    });

    test('a successful local transfer leaves no .drag-partial behind', () async {
      final payload = List<int>.generate(500, (i) => i % 256);
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/out.bin';

      final t = download();
      await TransferService().run(
        t: t,
        src: LocalBackend(),
        srcPath: src.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        verify: 'size',
      );

      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload);
      expect(File('$dstPath.drag-partial').existsSync(), isFalse);
    });

    test('an aborted local overwrite preserves the existing file and cleans the temp', () async {
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(List<int>.generate(1000, (i) => i % 256));
      final dstPath = '${dir.path}/keep.bin';
      final original = List<int>.filled(64, 0xAB);
      File(dstPath).writeAsBytesSync(original); // the file the user is overwriting

      final t = download();
      await TransferService().run(
        t: t,
        src: LocalBackend(),
        srcPath: src.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        control: TransferControl()..abort(), // pause/cancel before any bytes flow
      );

      expect(t.status, TransferStatus.paused);
      // The original destination must be intact — never truncated or deleted.
      expect(await File(dstPath).readAsBytes(), original);
      expect(File('$dstPath.drag-partial').existsSync(), isFalse);
    });

    test('checksum verification disables resume (hashes the whole file)', () async {
      final payload = List<int>.generate(1000, (i) => i % 256);
      final src = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/dst.bin';
      File('$dstPath.drag-partial').writeAsBytesSync(payload.sublist(0, 400));

      final t = download(attempts: 2);
      await TransferService().run(
        t: t,
        src: LocalBackend(),
        srcPath: src.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        verify: 'checksum',
      );

      // A full restart + checksum must still produce the correct file.
      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload);
    });
  });
}
