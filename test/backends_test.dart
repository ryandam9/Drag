import 'dart:io';

import 'package:drag/fs/simulated_backend.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalBackend', () {
    late Directory dir;
    final backend = LocalBackend();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fs_local');
      await File(p.join(dir.path, 'readme.txt')).writeAsString('hello');
      await File(p.join(dir.path, 'data.bin')).writeAsBytes(List.filled(2048, 7));
      await Directory(p.join(dir.path, 'sub')).create();
    });
    tearDown(() => dir.delete(recursive: true));

    test('lists entries with .. , dirs first, and metadata', () async {
      final items = await backend.list(dir.path);
      expect(items.first.isParent, isTrue); // .. comes first
      final names = items.map((e) => e.name).toList();
      expect(names, containsAll(['sub', 'readme.txt', 'data.bin']));

      // Directory 'sub' sorts before files.
      final subIdx = names.indexOf('sub');
      final fileIdx = names.indexOf('data.bin');
      expect(subIdx < fileIdx, isTrue);

      final bin = items.firstWhere((e) => e.name == 'data.bin');
      expect(bin.sizeBytes, 2048);
      expect(bin.perms, isNotEmpty);
      expect(bin.modified, isNotEmpty);
    });

    test('round-trips bytes through openRead → write', () async {
      final handle = await backend.openRead(p.join(dir.path, 'data.bin'));
      expect(handle.length, 2048);

      final outPath = p.join(dir.path, 'copy.bin');
      var lastSent = 0;
      await backend.write(outPath, handle.stream, handle.length, onProgress: (s) => lastSent = s);
      expect(lastSent, 2048);
      expect(await File(outPath).readAsBytes(), List.filled(2048, 7));
    });

    test('childPath / parentPath', () {
      final child = backend.childPath(dir.path, 'sub', true);
      expect(child, p.join(dir.path, 'sub'));
      expect(backend.parentPath(child), dir.path);
    });

    test('badge & displayPath', () {
      expect(backend.badge, 'LOCAL');
      expect(backend.displayPath('/x/y'), '/x/y');
      expect(backend.isReady, isTrue);
    });

    test('makeDir creates a directory', () async {
      final path = p.join(dir.path, 'newdir');
      await backend.makeDir(path);
      expect(await Directory(path).exists(), isTrue);
    });

    test('rename moves a file', () async {
      final from = p.join(dir.path, 'readme.txt');
      final to = p.join(dir.path, 'readme2.txt');
      await backend.rename(from, to);
      expect(await File(from).exists(), isFalse);
      expect(await File(to).readAsString(), 'hello');
    });

    test('rename moves a directory', () async {
      final to = p.join(dir.path, 'sub-renamed');
      await backend.rename(p.join(dir.path, 'sub'), to);
      expect(await Directory(to).exists(), isTrue);
    });

    test('delete removes a file and a directory (recursive)', () async {
      await backend.delete(p.join(dir.path, 'readme.txt'), isDir: false);
      expect(await File(p.join(dir.path, 'readme.txt')).exists(), isFalse);
      await backend.delete(p.join(dir.path, 'sub'), isDir: true);
      expect(await Directory(p.join(dir.path, 'sub')).exists(), isFalse);
    });

    test('supportsMutation is true', () => expect(backend.supportsMutation, isTrue));
  });

  group('S3Backend (offline path math)', () {
    final b = S3Backend(Connection(name: 's', protocol: Protocol.s3, bucket: 'bk'));

    test('not ready without credentials', () => expect(b.isReady, isFalse));
    test('badge/kind', () {
      expect(b.badge, 'S3');
      expect(b.kind, EndpointKind.s3);
    });
    test('childPath appends key, dir adds slash', () {
      expect(b.childPath('', 'k.txt', false), 'k.txt');
      expect(b.childPath('a/', 'b', true), 'a/b/');
    });
    test('parentPath walks the prefix', () {
      expect(b.parentPath('a/b/'), 'a/');
      expect(b.parentPath('a/'), '');
    });
    test('displayPath uses s3:// scheme', () {
      expect(b.displayPath('k'), 's3://bk/k');
    });
    test('supportsMutation is true', () => expect(b.supportsMutation, isTrue));
  });

  group('SimulatedBackend (SFTP)', () {
    final conn = Connection(name: 'host', protocol: Protocol.sftp, username: 'u', remotePath: '/srv');
    final b = SimulatedBackend(conn);

    test('is read-only (no mutation, no transfer)', () {
      expect(b.supportsMutation, isFalse);
      expect(b.supportsTransfer, isFalse);
      expect(() => b.makeDir('/srv/x'), throwsUnsupportedError);
    });

    test('lists mock data', () async {
      final items = await b.list('/srv');
      expect(items, isNotEmpty);
    });
    test('transfers are unsupported (simulated)', () {
      expect(() => b.openRead('/srv/x'), throwsUnsupportedError);
      expect(() => b.write('/srv/x', const Stream.empty(), 0), throwsUnsupportedError);
    });
    test('badge & initial path', () {
      expect(b.badge, 'REMOTE');
      expect(b.initialPath, '/srv');
    });
    test('childPath / parentPath', () {
      expect(b.childPath('/srv', 'f', false), '/srv/f');
      expect(b.parentPath('/srv/sub'), '/srv');
    });
  });
}
