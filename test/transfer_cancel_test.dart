import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_backend.dart';

Transfer _t() => Transfer(
      name: 'f.bin',
      route: 'test',
      direction: TransferDirection.upload,
      sizeBytes: 1000,
      session: 's',
    );

void main() {
  test('an aborted transfer leaves a pre-existing destination untouched', () async {
    final src = MemoryBackend(files: {'/f.bin': Uint8List(1000)});
    // A file the user is about to overwrite. A pause/cancel must NOT destroy it.
    final original = Uint8List.fromList([1, 2, 3]);
    final dst = MemoryBackend(files: {'/f.bin': original});
    final t = _t();
    final control = TransferControl()..abort();

    await TransferService().run(
      t: t,
      src: src,
      srcPath: '/f.bin',
      dst: dst,
      dstPath: '/f.bin',
      onStatus: () {},
      control: control,
    );

    expect(t.status, TransferStatus.paused);
    // The original is preserved (MemoryBackend is atomic, like S3).
    expect((await dst.list('/')).any((e) => e.name == 'f.bin'), isTrue);
    final kept = await dst.openRead('/f.bin');
    expect(await kept.stream.expand((c) => c).toList(), [1, 2, 3]);
  });

  test('without an abort the transfer completes normally', () async {
    final src = MemoryBackend(files: {'/f.bin': Uint8List(500)});
    final dst = MemoryBackend();
    final t = _t();

    await TransferService().run(
      t: t,
      src: src,
      srcPath: '/f.bin',
      dst: dst,
      dstPath: '/f.bin',
      onStatus: () {},
      control: TransferControl(), // never aborted
    );

    expect(t.status, TransferStatus.done);
    expect((await dst.list('/')).any((e) => e.name == 'f.bin'), isTrue);
  });

  group('pause vs cancel (staged local destination)', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('pause'));
    tearDown(() => dir.delete(recursive: true));

    Transfer download() => Transfer(
          name: 'dst.bin',
          route: 'r',
          direction: TransferDirection.download,
          sizeBytes: 1000,
          session: 's',
          attempts: 1, // a first attempt — pause must still allow resume
        );

    test('pause mid-stream keeps the partial; resume continues from it', () async {
      final payload = List<int>.generate(1000, (i) => i % 256);
      final srcFile = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/dst.bin';

      final t = download();
      final control = TransferControl();
      await TransferService().run(
        t: t,
        src: _AbortingLocal(control, AbortReason.pause, afterBytes: 400),
        srcPath: srcFile.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        control: control,
      );

      // The staging partial survives the pause, holding the bytes streamed
      // so far, and the transfer knows it may resume from it.
      expect(t.status, TransferStatus.paused);
      expect(t.pausedWithPartial, isTrue);
      final partial = File('$dstPath.drag-partial-${t.id}');
      expect(partial.existsSync(), isTrue);
      final kept = partial.lengthSync();
      expect(kept, greaterThan(0));
      expect(kept, lessThan(1000));

      // Resume (as the queue does: a fresh run of the same Transfer). It must
      // continue from the kept bytes via a ranged read, not restart at zero.
      final src = _RangedLocal();
      await TransferService().run(
        t: t,
        src: src,
        srcPath: srcFile.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        verify: 'size',
      );

      expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
      expect(await File(dstPath).readAsBytes(), payload); // partial + tail == full
      expect(src.rangeStart, kept); // bytes before the pause were not re-sent
      expect(partial.existsSync(), isFalse); // promoted to the final name
    });

    test('cancel mid-stream still discards the partial', () async {
      final payload = List<int>.generate(1000, (i) => i % 256);
      final srcFile = File('${dir.path}/src.bin')..writeAsBytesSync(payload);
      final dstPath = '${dir.path}/dst.bin';

      final t = download();
      final control = TransferControl();
      await TransferService().run(
        t: t,
        src: _AbortingLocal(control, AbortReason.cancel, afterBytes: 400),
        srcPath: srcFile.path,
        dst: LocalBackend(),
        dstPath: dstPath,
        onStatus: () {},
        control: control,
      );

      expect(t.pausedWithPartial, isFalse);
      expect(File('$dstPath.drag-partial-${t.id}').existsSync(), isFalse);
      expect(File(dstPath).existsSync(), isFalse); // nothing published either
    });

    test('discardPartial removes the staging file a pause left behind', () async {
      final dstPath = '${dir.path}/dst.bin';
      final t = download();
      final partial = File('$dstPath.drag-partial-${t.id}')..writeAsBytesSync([1, 2, 3]);

      await TransferService().discardPartial(LocalBackend(), dstPath, t);

      expect(partial.existsSync(), isFalse);
    });
  });
}

/// A [LocalBackend] whose read re-chunks the file into 100-byte parts and
/// aborts [control] with [reason] once [afterBytes] bytes have been yielded —
/// simulating a transfer paused or cancelled genuinely mid-stream.
class _AbortingLocal extends LocalBackend {
  _AbortingLocal(this.control, this.reason, {required this.afterBytes});
  final TransferControl control;
  final AbortReason reason;
  final int afterBytes;

  @override
  Future<ReadHandle> openRead(String path) async {
    final h = await super.openRead(path);
    Stream<Uint8List> chunks() async* {
      var sent = 0;
      await for (final c in h.stream) {
        for (var i = 0; i < c.length; i += 100) {
          final end = i + 100 < c.length ? i + 100 : c.length;
          yield Uint8List.sublistView(c, i, end);
          sent += end - i;
          if (sent >= afterBytes) control.abort(reason);
        }
      }
    }

    return ReadHandle(chunks(), h.length);
  }
}

/// A [LocalBackend] that records the offset of a ranged read, so tests can
/// assert a resume really skipped the bytes already on disk.
class _RangedLocal extends LocalBackend {
  int? rangeStart;

  @override
  Future<ReadHandle> openReadRange(String path, int start) {
    rangeStart = start;
    return super.openReadRange(path, start);
  }
}
