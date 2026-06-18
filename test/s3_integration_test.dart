// Real end-to-end S3 test against an S3-compatible server.
//
// Skipped unless an S3 endpoint is provided, so the normal `flutter test` run
// stays hermetic. To run it:
//
//   1. Start any S3-compatible server (MinIO, s3rver, …) with a bucket.
//   2. flutter test test/s3_integration_test.dart \
//        --dart-define=S3_ENDPOINT=127.0.0.1:9595 \
//        --dart-define=S3_BUCKET=test-bucket \
//        --dart-define=S3_KEY=S3RVER --dart-define=S3_SECRET=S3RVER
//
// It exercises the app's real S3Backend + TransferService: upload a local file
// to S3, list it back, then download it and assert the bytes round-trip.
import 'dart:io';

import 'package:filesync/fs/storage_backend.dart';
import 'package:filesync/fs/transfer_service.dart';
import 'package:filesync/models/connection.dart';
import 'package:filesync/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

const _endpoint = String.fromEnvironment('S3_ENDPOINT');
const _bucket = String.fromEnvironment('S3_BUCKET');
const _key = String.fromEnvironment('S3_KEY');
const _secret = String.fromEnvironment('S3_SECRET');
const _ssl = bool.fromEnvironment('S3_SSL', defaultValue: false);
const _bucket2 = String.fromEnvironment('S3_BUCKET2');

Connection _conn(String bucket) => Connection(
      name: bucket,
      protocol: Protocol.s3,
      endpoint: _endpoint,
      bucket: bucket,
      accessKeyId: _key,
      secretAccessKey: _secret,
      region: 'us-east-1',
      useSsl: _ssl,
    );

void main() {
  test('real S3 round-trip: upload → list → download', () async {
    final conn = Connection(
      name: 'integration',
      protocol: Protocol.s3,
      endpoint: _endpoint,
      bucket: _bucket,
      accessKeyId: _key,
      secretAccessKey: _secret,
      region: 'us-east-1',
      useSsl: _ssl,
    );
    final s3 = S3Backend(conn);
    final local = LocalBackend();
    final svc = TransferService();

    expect(s3.isReady, isTrue, reason: 'S3 connection should be ready with creds');

    final dir = await Directory.systemTemp.createTemp('filesync_s3');
    addTearDown(() => dir.delete(recursive: true));

    // A payload large enough to span several chunks.
    final payload = List<int>.generate(300 * 1024, (i) => (i * 7) % 256);
    final srcFile = File('${dir.path}/upload.bin');
    await srcFile.writeAsBytes(payload);

    // 1) Upload  Local → S3
    final up = Transfer(
      name: 'upload.bin',
      route: 'local → s3',
      direction: TransferDirection.upload,
      sizeBytes: payload.length,
      session: 's3',
      live: true,
    );
    await svc.run(
      t: up,
      src: local,
      srcPath: srcFile.path,
      dst: s3,
      dstPath: 'folder/upload.bin',
      onChange: () {},
    );
    expect(up.status, TransferStatus.done, reason: up.errorMessage ?? '');

    // 2) List the prefix and confirm the object shows up
    final listing = await s3.list('folder/');
    final names = listing.map((e) => e.name).toList();
    expect(names, contains('upload.bin'));

    // 3) Download  S3 → Local
    final outPath = '${dir.path}/download.bin';
    final down = Transfer(
      name: 'upload.bin',
      route: 's3 → local',
      direction: TransferDirection.download,
      sizeBytes: payload.length,
      session: 's3',
      live: true,
    );
    await svc.run(
      t: down,
      src: s3,
      srcPath: 'folder/upload.bin',
      dst: local,
      dstPath: outPath,
      onChange: () {},
    );
    expect(down.status, TransferStatus.done, reason: down.errorMessage ?? '');

    // 4) Bytes must match what we uploaded.
    expect(await File(outPath).readAsBytes(), payload);
  }, skip: _endpoint.isEmpty ? 'set --dart-define=S3_ENDPOINT to run' : false);

  // Use case #2: copy between two buckets (modelling two accounts). Each side
  // is its own S3Backend/Connection, and the copy is streamed through the
  // client — proving differing credentials/endpoints work.
  test('real S3 → S3 cross-bucket copy (two accounts)', () async {
    final svc = TransferService();
    final local = LocalBackend();
    final a = S3Backend(_conn(_bucket));
    final b = S3Backend(_conn(_bucket2));

    final dir = await Directory.systemTemp.createTemp('filesync_s3x');
    addTearDown(() => dir.delete(recursive: true));

    final payload = List<int>.generate(120 * 1024, (i) => (i * 13) % 256);
    final seed = File('${dir.path}/seed.bin');
    await seed.writeAsBytes(payload);

    // Seed bucket A.
    final t1 = Transfer(
        name: 'seed.bin', route: 'local→A', direction: TransferDirection.upload,
        sizeBytes: payload.length, session: 'A', live: true);
    await svc.run(t: t1, src: local, srcPath: seed.path, dst: a, dstPath: 'report.bin', onChange: () {});
    expect(t1.status, TransferStatus.done, reason: t1.errorMessage ?? '');

    // Copy A → B (cross-account, streamed).
    final t2 = Transfer(
        name: 'report.bin', route: 'A→B', direction: TransferDirection.upload,
        sizeBytes: payload.length, session: 'B', live: true);
    await svc.run(t: t2, src: a, srcPath: 'report.bin', dst: b, dstPath: 'copied/report.bin', onChange: () {});
    expect(t2.status, TransferStatus.done, reason: t2.errorMessage ?? '');

    // Confirm it now lives in bucket B with identical bytes.
    expect((await b.list('copied/')).map((e) => e.name), contains('report.bin'));
    final out = '${dir.path}/from_b.bin';
    final t3 = Transfer(
        name: 'report.bin', route: 'B→local', direction: TransferDirection.download,
        sizeBytes: payload.length, session: 'B', live: true);
    await svc.run(t: t3, src: b, srcPath: 'copied/report.bin', dst: local, dstPath: out, onChange: () {});
    expect(await File(out).readAsBytes(), payload);
  }, skip: (_endpoint.isEmpty || _bucket2.isEmpty) ? 'set S3_ENDPOINT + S3_BUCKET2 to run' : false);
}
