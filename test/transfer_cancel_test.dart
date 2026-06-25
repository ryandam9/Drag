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
  test('an aborted control stops the transfer and removes the partial file', () async {
    final src = MemoryBackend(files: {'/f.bin': Uint8List(1000)});
    // A stale/partial destination file that the abort cleanup should remove.
    final dst = MemoryBackend(files: {'/f.bin': Uint8List.fromList([1, 2, 3])});
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
    expect((await dst.list('/')).any((e) => e.name == 'f.bin'), isFalse);
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
