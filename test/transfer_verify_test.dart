import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs a single file through [TransferService] from [src] to [dst] and returns
/// the finished [Transfer].
Future<Transfer> _run(
  StorageBackend src,
  String srcPath,
  StorageBackend dst,
  String dstPath, {
  required String verify,
}) async {
  final t = Transfer(
    name: p.basename(srcPath),
    route: 'test',
    direction: TransferDirection.upload,
    sizeBytes: 0,
    session: 's',
    sourcePath: srcPath,
    destPath: dstPath,
  );
  await TransferService().run(
    t: t,
    src: src,
    srcPath: srcPath,
    dst: dst,
    dstPath: dstPath,
    onStatus: () {},
    verify: verify,
  );
  return t;
}

void main() {
  late Directory src;
  late Directory dst;

  setUp(() async {
    src = await Directory.systemTemp.createTemp('verify_src');
    dst = await Directory.systemTemp.createTemp('verify_dst');
    await File(p.join(src.path, 'data.bin'))
        .writeAsBytes(List<int>.generate(4096, (i) => i % 251));
  });
  tearDown(() async {
    await src.delete(recursive: true);
    await dst.delete(recursive: true);
  });

  String srcFile() => p.join(src.path, 'data.bin');
  String dstFile() => p.join(dst.path, 'data.bin');

  group('post-transfer verification', () {
    test('an honest copy passes every verify level', () async {
      for (final level in ['off', 'size', 'checksum']) {
        final out = File(p.join(dst.path, '$level.bin')).path;
        final t = await _run(LocalBackend(), srcFile(), LocalBackend(), out,
            verify: level);
        expect(t.status, TransferStatus.done, reason: '$level: ${t.errorMessage}');
        expect(await File(out).length(), 4096);
      }
    });

    test('size verify catches a short write', () async {
      final t = await _run(
          LocalBackend(), srcFile(), _TruncatingLocal(), dstFile(),
          verify: 'size');
      expect(t.status, TransferStatus.error);
      expect(t.errorMessage, contains('Verification failed'));
    });

    test('checksum verify catches silent corruption that size misses', () async {
      // A copy that keeps the byte count but flips a byte: size says OK,
      // checksum must reject it.
      final pass = await _run(
          LocalBackend(), srcFile(), _CorruptingLocal(), p.join(dst.path, 'a.bin'),
          verify: 'size');
      expect(pass.status, TransferStatus.done,
          reason: 'same length should satisfy a size check');

      final fail = await _run(
          LocalBackend(), srcFile(), _CorruptingLocal(), p.join(dst.path, 'b.bin'),
          verify: 'checksum');
      expect(fail.status, TransferStatus.error);
      expect(fail.errorMessage, contains('Checksum mismatch'));
    });

    test("'off' skips verification entirely (corrupt copy still reported done)",
        () async {
      final t = await _run(
          LocalBackend(), srcFile(), _CorruptingLocal(), dstFile(),
          verify: 'off');
      expect(t.status, TransferStatus.done);
    });
  });

  group('StorageBackend.sizeOf', () {
    test('reports the file size and null for a missing file', () async {
      final b = LocalBackend();
      expect(await b.sizeOf(srcFile()), 4096);
      expect(await b.sizeOf(p.join(src.path, 'nope.bin')), isNull);
    });
  });
}

/// Writes one byte fewer than it receives, simulating a truncated upload.
class _TruncatingLocal extends LocalBackend {
  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
      {void Function(int sent)? onProgress}) {
    var dropped = false;
    final shortened = data.map((chunk) {
      if (!dropped && chunk.isNotEmpty) {
        dropped = true;
        return Uint8List.fromList(chunk.sublist(1));
      }
      return chunk;
    });
    return super.write(path, shortened, length, onProgress: onProgress);
  }
}

/// Writes the same number of bytes but flips one, simulating silent corruption.
class _CorruptingLocal extends LocalBackend {
  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
      {void Function(int sent)? onProgress}) {
    var flipped = false;
    final corrupted = data.map((chunk) {
      if (!flipped && chunk.isNotEmpty) {
        flipped = true;
        final copy = Uint8List.fromList(chunk);
        copy[0] = copy[0] ^ 0xFF;
        return copy;
      }
      return chunk;
    });
    return super.write(path, corrupted, length, onProgress: onProgress);
  }
}
