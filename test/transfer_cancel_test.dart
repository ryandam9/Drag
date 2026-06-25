import 'dart:typed_data';

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
}
