import 'package:drag/models/connection.dart';
import 'package:drag/models/file_item.dart';
import 'package:drag/models/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('handles each unit', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(248 * 1024 * 1024), '248.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('negative / zero collapses to 0 B', () {
      expect(formatBytes(-5), '0 B');
    });
  });

  group('formatModified', () {
    test('zero-pads to the table format', () {
      expect(formatModified(DateTime(2025, 6, 9, 8, 4)), '2025-06-09  08:04');
      expect(formatModified(DateTime(2025, 12, 19, 22, 11)), '2025-12-19  22:11');
    });

    test('null → empty', () => expect(formatModified(null), ''));
  });

  group('FileItem', () {
    test('directory shows dash size and folder icon', () {
      const dir = FileItem(name: 'src', isDir: true);
      expect(dir.sizeLabel, '—');
      expect(dir.icon, '📁');
      expect(dir.isParent, isFalse);
    });

    test('file shows formatted size and default icon', () {
      const f = FileItem(name: 'a.txt', sizeBytes: 2048);
      expect(f.sizeLabel, '2.0 KB');
      expect(f.icon, '📄');
    });

    test('glyph override and parent detection', () {
      const archive = FileItem(name: 'b.tar.gz', sizeBytes: 10, glyph: '🗄');
      expect(archive.icon, '🗄');
      const parent = FileItem(name: '..', isDir: true);
      expect(parent.isParent, isTrue);
    });

    test('icon is type-specific by extension (case-insensitive)', () {
      expect(const FileItem(name: 'pic.PNG').icon, '🖼');
      expect(const FileItem(name: 'clip.mp4').icon, '🎬');
      expect(const FileItem(name: 'song.flac').icon, '🎵');
      expect(const FileItem(name: 'bundle.zip').icon, '🗜');
      expect(const FileItem(name: 'report.pdf').icon, '📕');
      expect(const FileItem(name: 'data.csv').icon, '📊');
      expect(const FileItem(name: 'main.dart').icon, '📜');
      expect(const FileItem(name: 'config.yaml').icon, '🧾');
      // Unknown / no extension fall back to the generic document glyph.
      expect(const FileItem(name: 'notes.txt').icon, '📄');
      expect(const FileItem(name: 'README').icon, '📄');
      // A directory is always a folder regardless of a dotted name.
      expect(const FileItem(name: 'my.config', isDir: true).icon, '📁');
    });
  });

  group('Connection', () {
    test('protocol & auth labels', () {
      expect(Protocol.sftp.label, 'SFTP');
      expect(Protocol.s3.label, 'S3');
      expect(AuthMethod.password.label, 'Password');
      expect(AuthMethod.privateKey.label, 'Private Key');
      // Only the implemented protocols/auth methods are exposed.
      expect(Protocol.values, [Protocol.sftp, Protocol.s3]);
      expect(AuthMethod.values, [AuthMethod.password, AuthMethod.privateKey]);
    });

    test('S3 kind & credential readiness', () {
      final s3 = Connection(name: 'x', protocol: Protocol.s3);
      expect(s3.isS3, isTrue);
      expect(s3.kind, EndpointKind.s3);
      expect(s3.hasS3Credentials, isFalse);

      // Bucket is optional — credentials alone are enough (discovery mode).
      s3
        ..accessKeyId = 'AKIA'
        ..secretAccessKey = 'secret';
      expect(s3.hasS3Credentials, isTrue);
      s3.bucket = 'b';
      expect(s3.hasS3Credentials, isTrue);

      // The "use AWS profile" toggle satisfies readiness without typed keys.
      final prof = Connection(name: 'p', protocol: Protocol.s3, useAwsProfile: true);
      expect(prof.hasS3Credentials, isTrue);
    });

    test('SFTP connection is not S3', () {
      final sftp = Connection(name: 'y', protocol: Protocol.sftp);
      expect(sftp.isS3, isFalse);
      expect(sftp.kind, EndpointKind.sftp);
    });

    test('JSON round-trips the assume-role fields (non-secret)', () {
      final c = Connection(
        name: 'role',
        protocol: Protocol.s3,
        useAwsProfile: true,
        assumeRoleArn: 'arn:aws:iam::1:role/R',
        roleSessionName: 'drag-session',
        roleExternalId: 'ext-123',
      );
      final back = Connection.fromJson(c.toJson());
      expect(back.assumeRoleArn, 'arn:aws:iam::1:role/R');
      expect(back.roleSessionName, 'drag-session');
      expect(back.roleExternalId, 'ext-123');
      // Defaults when absent.
      expect(Connection.fromJson(const {'name': 'x'}).assumeRoleArn, '');
    });
  });

  group('formatDuration', () {
    test('ms / seconds / minutes', () {
      expect(formatDuration(null), '—');
      expect(formatDuration(const Duration(milliseconds: 800)), '800ms');
      expect(formatDuration(const Duration(milliseconds: 12300)), '12.3s');
      expect(formatDuration(const Duration(minutes: 2, seconds: 5)), '2m 05s');
    });
  });

  group('Transfer', () {
    test('elapsed + elapsedLabel', () {
      final t = Transfer(name: 'f', route: 'r', direction: TransferDirection.upload, sizeBytes: 1, session: 's')
        ..startedAt = DateTime(2025, 1, 1, 0, 0, 0)
        ..finishedAt = DateTime(2025, 1, 1, 0, 0, 3);
      expect(t.elapsed, const Duration(seconds: 3));
      expect(t.elapsedLabel, '3.0s');
    });

    test('defaults', () {
      final t = Transfer(
        name: 'f',
        route: 'r',
        direction: TransferDirection.upload,
        sizeBytes: 100,
        session: 's',
      );
      expect(t.status, TransferStatus.queued);
      expect(t.progress, 0);
      expect(t.live, isFalse);
      expect(t.speed, '—');
    });
  });
}
