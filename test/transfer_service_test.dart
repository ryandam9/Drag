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

/// A trivial in-memory source for a known set of files.
class _MemSource extends StorageBackend {
  _MemSource(this.files);
  final Map<String, Uint8List> files;
  @override
  EndpointKind get kind => EndpointKind.s3;
  @override
  String get badge => 'M';
  @override
  String displayPath(String path) => path;
  @override
  String get initialPath => '/';
  @override
  Future<List<FileItem>> list(String path) async => const [];
  @override
  Future<ReadHandle> openRead(String path) async {
    final b = files[path] ?? Uint8List(0);
    return ReadHandle(Stream<Uint8List>.value(b), b.length);
  }
  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
          {void Function(int sent)? onProgress}) =>
      throw UnsupportedError('source only');
  @override
  String childPath(String path, String name, bool isDir) => '$path/$name';
  @override
  String parentPath(String path) => '/';
}

/// A non-atomic (stage-to-`.drag-partial`) destination whose rename refuses to
/// clobber an existing target — like SFTP v3 / Windows. [renameAlwaysFails] and
/// [deleteAlwaysFails] model an unrelated, non-"target exists" failure so the
/// finalize logic can be checked for both cases.
class _StagingDest extends StorageBackend {
  _StagingDest(this.files, {this.renameAlwaysFails = false, this.deleteAlwaysFails = false});
  final Map<String, Uint8List> files;
  final bool renameAlwaysFails;
  final bool deleteAlwaysFails;
  @override
  EndpointKind get kind => EndpointKind.sftp;
  @override
  String get badge => 'S';
  @override
  String displayPath(String path) => path;
  @override
  String get initialPath => '/';
  @override
  bool get atomicWrite => false; // ⇒ TransferService stages to .drag-partial
  @override
  Future<List<FileItem>> list(String path) async => const [];
  @override
  Future<ReadHandle> openRead(String path) async {
    final b = files[path] ?? Uint8List(0);
    return ReadHandle(Stream<Uint8List>.value(b), b.length);
  }
  @override
  Future<void> write(String path, Stream<Uint8List> data, int length,
      {void Function(int sent)? onProgress}) async {
    final out = <int>[];
    await for (final c in data) {
      out.addAll(c);
      onProgress?.call(out.length);
    }
    files[path] = Uint8List.fromList(out);
  }
  @override
  Future<int?> sizeOf(String path) async => files[path]?.length;
  @override
  Future<void> rename(String fromPath, String toPath) async {
    if (renameAlwaysFails) throw Exception('permission denied');
    if (files.containsKey(toPath)) throw Exception('target exists'); // won't clobber
    files[toPath] = files.remove(fromPath)!;
  }
  @override
  Future<void> delete(String path, {required bool isDir}) async {
    if (deleteAlwaysFails) throw Exception('permission denied');
    files.remove(path);
  }
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

  test('finalize replaces an existing destination when rename clashes', () async {
    final src = _MemSource({'/f': Uint8List.fromList(List.filled(1000, 7))});
    final dst = _StagingDest({'/f': Uint8List.fromList([1, 2, 3])}); // pre-existing file
    final t = _t(1000);
    await TransferService().run(
      t: t, src: src, srcPath: '/f', dst: dst, dstPath: '/f', onStatus: () {});
    expect(t.status, TransferStatus.done, reason: t.errorMessage ?? '');
    // The new bytes replaced the old file and the temp file is gone.
    expect(dst.files['/f']!.length, 1000);
    expect(dst.files.containsKey('/f.drag-partial'), isFalse);
  });

  test('finalize does NOT delete the destination on an unrelated rename failure', () async {
    final original = Uint8List.fromList([1, 2, 3]);
    final src = _MemSource({'/f': Uint8List.fromList(List.filled(1000, 7))});
    // Rename fails for a non-"target exists" reason and delete is also refused
    // (e.g. permissions) — the existing destination must be left intact.
    final dst = _StagingDest({'/f': original},
        renameAlwaysFails: true, deleteAlwaysFails: true);
    final t = _t(1000);
    await TransferService().run(
      t: t, src: src, srcPath: '/f', dst: dst, dstPath: '/f', onStatus: () {});
    expect(t.status, TransferStatus.error);
    // The valid destination survived; only the temp file holds the new bytes.
    expect(dst.files['/f'], original);
    expect(dst.files['/f.drag-partial']!.length, 1000);
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
