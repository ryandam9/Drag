import 'package:filesync/models/connection.dart';
import 'package:filesync/models/file_item.dart';
import 'package:filesync/models/transfer.dart';
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
  });

  group('Connection', () {
    test('protocol & auth labels', () {
      expect(Protocol.sftp.label, 'SFTP');
      expect(Protocol.s3.label, 'S3');
      expect(AuthMethod.privateKey.label, 'Private Key');
      expect(AuthMethod.sshAgent.label, 'SSH Agent');
    });

    test('S3 kind & credential readiness', () {
      final s3 = Connection(name: 'x', protocol: Protocol.s3);
      expect(s3.isS3, isTrue);
      expect(s3.kind, EndpointKind.s3);
      expect(s3.hasS3Credentials, isFalse);

      s3
        ..accessKeyId = 'AKIA'
        ..secretAccessKey = 'secret'
        ..bucket = 'b';
      expect(s3.hasS3Credentials, isTrue);
    });

    test('SFTP connection is not S3', () {
      final sftp = Connection(name: 'y', protocol: Protocol.sftp);
      expect(sftp.isS3, isFalse);
      expect(sftp.kind, EndpointKind.sftp);
    });
  });

  group('Transfer', () {
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
