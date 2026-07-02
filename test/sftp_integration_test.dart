// Real end-to-end SFTP test against a live SSH server.
//
// Skipped unless SFTP_HOST is provided, so `flutter test` stays hermetic.
// Example:
//   flutter test test/sftp_integration_test.dart \
//     --dart-define=SFTP_HOST=127.0.0.1 --dart-define=SFTP_PORT=2222 \
//     --dart-define=SFTP_USER=sftptest --dart-define=SFTP_PASS=testpass123 \
//     --dart-define=SFTP_DIR=/home/sftptest
//
// Exercises the real SftpBackend + TransferService: connect, list, upload a
// local file, list it back, download it, and assert the bytes round-trip.
import 'dart:io';
import 'dart:typed_data';

import 'package:drag/fs/sftp_backend.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/fs/transfer_service.dart';
import 'package:drag/models/connection.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = String.fromEnvironment('SFTP_HOST');
const _port = int.fromEnvironment('SFTP_PORT', defaultValue: 22);
const _user = String.fromEnvironment('SFTP_USER');
const _pass = String.fromEnvironment('SFTP_PASS');
const _dir = String.fromEnvironment('SFTP_DIR', defaultValue: '/tmp');

void main() {
  test(
    'real SFTP round-trip: connect → upload → list → download',
    () async {
      final conn = Connection(
        name: 'sftp-it',
        protocol: Protocol.sftp,
        host: _host,
        port: _port,
        username: _user,
        auth: AuthMethod.password,
        password: _pass,
        remotePath: _dir,
      );
      final sftp = SftpBackend(conn);
      final local = LocalBackend();
      final svc = TransferService();
      addTearDown(sftp.dispose);

      expect(sftp.isReady, isTrue);

      final tmp = await Directory.systemTemp.createTemp('drag_sftp');
      addTearDown(() => tmp.delete(recursive: true));
      final payload = List<int>.generate(200 * 1024, (i) => (i * 31) % 256);
      final srcFile = File('${tmp.path}/upload.bin');
      await srcFile.writeAsBytes(payload);

      final remotePath = '$_dir/drag_test_upload.bin';

      // 1) Upload Local → SFTP
      final up = Transfer(
        name: 'upload.bin',
        route: 'local → sftp',
        direction: TransferDirection.upload,
        sizeBytes: payload.length,
        session: 'sftp',
        live: true,
      );
      await svc.run(
        t: up,
        src: local,
        srcPath: srcFile.path,
        dst: sftp,
        dstPath: remotePath,
        onStatus: () {},
      );
      expect(up.status, TransferStatus.done, reason: up.errorMessage ?? '');

      // 2) List and confirm
      final names = (await sftp.list(_dir)).map((e) => e.name).toList();
      expect(names, contains('drag_test_upload.bin'));

      // 3) Download SFTP → Local
      final outPath = '${tmp.path}/download.bin';
      final down = Transfer(
        name: 'drag_test_upload.bin',
        route: 'sftp → local',
        direction: TransferDirection.download,
        sizeBytes: payload.length,
        session: 'sftp',
        live: true,
      );
      await svc.run(
        t: down,
        src: sftp,
        srcPath: remotePath,
        dst: local,
        dstPath: outPath,
        onStatus: () {},
      );
      expect(down.status, TransferStatus.done, reason: down.errorMessage ?? '');

      // 4) Bytes must match
      expect(await File(outPath).readAsBytes(), payload);
    },
    skip: _host.isEmpty ? 'set --dart-define=SFTP_HOST to run' : false,
  );

  test(
    'real SFTP file operations: mkdir, rename, delete',
    () async {
      final conn = Connection(
        name: 'sftp-ops',
        protocol: Protocol.sftp,
        host: _host,
        port: _port,
        username: _user,
        auth: AuthMethod.password,
        password: _pass,
        remotePath: _dir,
      );
      final sftp = SftpBackend(conn);
      addTearDown(sftp.dispose);

      final base = '$_dir/drag_ops';
      await sftp.delete(base, isDir: true).catchError((_) {}); // clean slate

      await sftp.makeDir(base);
      expect((await sftp.list(_dir)).map((e) => e.name), contains('drag_ops'));

      await sftp.write(
        '$base/a.txt',
        Stream.value(Uint8List.fromList([9, 9, 9])),
        3,
      );
      await sftp.rename('$base/a.txt', '$base/b.txt');
      final names = (await sftp.list(base)).map((e) => e.name).toList();
      expect(names, contains('b.txt'));
      expect(names, isNot(contains('a.txt')));

      await sftp.delete(base, isDir: true);
      expect(
        (await sftp.list(_dir)).map((e) => e.name),
        isNot(contains('drag_ops')),
      );
    },
    skip: _host.isEmpty ? 'set --dart-define=SFTP_HOST to run' : false,
  );
}
