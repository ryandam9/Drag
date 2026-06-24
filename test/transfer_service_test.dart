import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A source backend whose read fails with a (configurably long) message.
class _FailingSource extends StorageBackend {
  _FailingSource(this.message);
  final String message;
  @override
  EndpointKind get kind => EndpointKind.s3;
  @override
  String get badge => 'X';
  @override
  String displayPath(String path) => path;
  @override
  String get initialPath => '';
  @override
  Future<List<FileItem>> list(String path) async => const [];
  @override
  Future<ReadHandle> openRead(String path) => throw Exception(message);
  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
          {void Function(int sent)? onProgress}) =>
      throw UnsupportedError('no');
  @override
  String childPath(String path, String name, bool isDir) => '$path/$name';
  @override
  String parentPath(String path) => '/';
}

/// A source that emits [chunks] spaced by [gap] so the 400ms speed window fires.
class _SlowSource extends StorageBackend {
  _SlowSource(this.chunks, this.gap);
  final int chunks;
  final Duration gap;
  @override
  EndpointKind get kind => EndpointKind.s3;
  @override
  String get badge => 'X';
  @override
  String displayPath(String path) => path;
  @override
  String get initialPath => '';
  @override
  Future<List<FileItem>> list(String path) async => const [];
  @override
  Future<ReadHandle> openRead(String path) async {
    Stream<Uint8List> gen() async* {
      for (var i = 0; i < chunks; i++) {
        await Future<void>.delayed(gap);
        yield Uint8List(64 * 1024);
      }
    }

    return ReadHandle(gen(), chunks * 64 * 1024);
  }

  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
          {void Function(int sent)? onProgress}) =>
      throw UnsupportedError('no');
  @override
  String childPath(String path, String name, bool isDir) => '$path/$name';
  @override
  String parentPath(String path) => '/';
}

Transfer _t(int size) => Transfer(
    name: 'f', route: 'r', direction: TransferDirection.upload, sizeBytes: size, session: 's', live: true);

void main() {
  test('records an error when the source cannot be read', () async {
    final t = _t(100);
    var statusCalls = 0;
    await TransferService().run(
      t: t,
      src: _FailingSource('boom'),
      srcPath: 'x',
      dst: LocalBackend(),
      dstPath: '/tmp/none',
      onStatus: () => statusCalls++,
    );
    expect(t.status, TransferStatus.error);
    expect(t.errorMessage, 'boom');
    expect(t.finishedAt, isNotNull);
    expect(statusCalls, greaterThanOrEqualTo(2)); // active + error
  });

  test('truncates a very long error message to 90 chars + ellipsis', () async {
    final long = 'e' * 200;
    final t = _t(100);
    await TransferService().run(
      t: t,
      src: _FailingSource(long),
      srcPath: 'x',
      dst: LocalBackend(),
      dstPath: '/tmp/none',
      onStatus: () {},
    );
    expect(t.errorMessage!.length, 91); // 90 + ellipsis
    expect(t.errorMessage, endsWith('…'));
  });

  test('updates live speed/ETA once the 400ms window elapses', () async {
    final dir = await Directory.systemTemp.createTemp('svc');
    addTearDown(() => dir.delete(recursive: true));
    final t = _t(5 * 64 * 1024);
    var progressed = false;
    await TransferService().run(
      t: t,
      src: _SlowSource(5, const Duration(milliseconds: 130)),
      srcPath: 'x',
      dst: LocalBackend(),
      dstPath: p.join(dir.path, 'out.bin'),
      onStatus: () {},
      onProgress: () => progressed = true,
    );
    expect(t.status, TransferStatus.done);
    expect(t.speed, isNot('—')); // a real speed string was computed
    expect(progressed, isTrue);
  });
}
