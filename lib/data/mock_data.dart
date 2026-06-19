import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';

const kB = 1024;
const mB = 1024 * 1024;

final localFiles = <FileItem>[
  const FileItem(name: '..', isDir: true),
  const FileItem(name: 'src', isDir: true, modified: '2025-06-18  14:02', perms: 'drwxr-xr-x'),
  const FileItem(name: 'tests', isDir: true, modified: '2025-06-17  09:44', perms: 'drwxr-xr-x'),
  FileItem(name: 'config.yaml', sizeBytes: (4.2 * kB).round(), modified: '2025-06-19  08:11', perms: '-rw-r--r--'),
  FileItem(name: 'deploy.sh', sizeBytes: (1.8 * kB).round(), modified: '2025-06-15  16:30', perms: '-rwxr-xr-x'),
  const FileItem(name: 'Dockerfile', sizeBytes: 890, modified: '2025-06-12  11:05', perms: '-rw-r--r--'),
  FileItem(name: 'package.json', sizeBytes: (3.1 * kB).round(), modified: '2025-06-10  19:55', perms: '-rw-r--r--'),
  FileItem(name: 'README.md', sizeBytes: (12.4 * kB).round(), modified: '2025-06-08  10:00', perms: '-rw-r--r--'),
  FileItem(
      name: 'backup.tar.gz',
      sizeBytes: 248 * mB,
      modified: '2025-06-01  00:00',
      perms: '-rw-------',
      glyph: '🗄'),
];

final remoteFiles = <FileItem>[
  const FileItem(name: '..', isDir: true),
  const FileItem(name: 'config', isDir: true, modified: '2025-06-18  22:10', perms: 'drwxr-xr-x'),
  const FileItem(name: 'logs', isDir: true, modified: '2025-06-19  07:55', perms: 'drwxrwxr-x'),
  const FileItem(name: 'public', isDir: true, modified: '2025-06-16  11:40', perms: 'drwxr-xr-x'),
  FileItem(name: 'config.yaml', sizeBytes: (3.9 * kB).round(), modified: '2025-06-14  09:30', perms: '-rw-r--r--'),
  FileItem(name: 'server.js', sizeBytes: (22.1 * kB).round(), modified: '2025-06-18  20:01', perms: '-rw-r--r--'),
  const FileItem(name: '.env', sizeBytes: 512, modified: '2025-06-10  14:00', perms: '-rw-------'),
  FileItem(name: 'pm2.config.js', sizeBytes: (1.2 * kB).round(), modified: '2025-06-09  18:44', perms: '-rw-r--r--'),
];

List<Connection> buildConnections() {
  final list = _seedConnections();
  // Stable ids so persisted edits map back to the right seed entry.
  for (var i = 0; i < list.length; i++) {
    list[i].id = 'seed-$i';
  }
  return list;
}

List<Connection> _seedConnections() => [
      Connection(
        name: 'prod-server-01',
        host: 'prod-server-01.example.com',
        port: 22,
        username: 'deploy',
        protocol: Protocol.sftp,
        auth: AuthMethod.privateKey,
        keyFile: '~/.ssh/prod_rsa',
        remotePath: '/var/www/app',
        localPath: '/Users/marco/projects/backend',
        online: true,
        group: ConnGroup.recent,
        details: 'Ubuntu 22.04 · OpenSSH 9.3',
        lastConnected: 'Last connected 08:14 today',
      ),
      Connection(
        name: 'staging-db',
        host: 'staging-db.example.com',
        username: 'admin',
        protocol: Protocol.sftp,
        online: true,
        group: ConnGroup.recent,
        details: 'Debian 12 · OpenSSH 9.2',
      ),
      Connection(
        name: 's3-prod (Account A)',
        protocol: Protocol.s3,
        region: 'us-east-1',
        bucket: 'acme-prod-assets',
        group: ConnGroup.recent,
        details: 'Amazon S3 · us-east-1',
      ),
      Connection(
        name: 's3-archive (Account B)',
        protocol: Protocol.s3,
        region: 'eu-west-1',
        bucket: 'acme-archive',
        group: ConnGroup.saved,
        details: 'Amazon S3 · eu-west-1',
      ),
      Connection(name: 'backup-nas', host: '10.0.0.12', username: 'backup', group: ConnGroup.recent),
      Connection(name: 'office-fileserver', host: 'files.office.local', username: 'marco'),
      Connection(name: 'dev-box-local', host: '127.0.0.1', port: 2222, username: 'dev'),
      Connection(name: 'cdn-edge-01', host: 'cdn-edge-01.example.com', username: 'edge', online: true),
      Connection(name: 'analytics-worker', host: 'analytics.example.com', username: 'worker'),
    ];

List<Transfer> buildTransfers() => [
      Transfer(
        name: 'backup_2025-06-19.tar.gz',
        route: 'Local → sftp://prod-server-01/backups/',
        direction: TransferDirection.upload,
        progress: 0.62,
        sizeBytes: 248 * mB,
        speed: '1.4 MB/s',
        eta: '0:41',
        session: 'prod-server-01',
        status: TransferStatus.active,
      ),
      Transfer(
        name: 'config.yaml',
        route: 'Local → sftp://prod-server-01/var/www/app/',
        direction: TransferDirection.upload,
        progress: 0.88,
        sizeBytes: (4.2 * kB).round(),
        speed: '210 KB/s',
        eta: '0:02',
        session: 'prod-server-01',
        status: TransferStatus.active,
      ),
      Transfer(
        name: 'deploy.sh',
        route: 'Local → sftp://prod-server-01/var/www/app/',
        direction: TransferDirection.upload,
        progress: 0,
        sizeBytes: (1.8 * kB).round(),
        session: 'prod-server-01',
        status: TransferStatus.queued,
      ),
      Transfer(
        name: 'dist.zip',
        route: 'Local → sftp://staging-db/releases/',
        direction: TransferDirection.upload,
        progress: 0.34,
        sizeBytes: 35 * mB,
        session: 'staging-db',
        status: TransferStatus.paused,
      ),
      Transfer(
        name: '.env',
        route: 'Local → sftp://prod-server-01/var/www/app/',
        direction: TransferDirection.upload,
        progress: 0,
        sizeBytes: 512,
        session: 'prod-server-01',
        status: TransferStatus.error,
        errorMessage: 'Permission denied — target is read-only',
      ),
      Transfer(
        name: 'server.js',
        route: 'sftp://prod-server-01/var/www/app/ → Local',
        direction: TransferDirection.download,
        progress: 1.0,
        sizeBytes: (22.1 * kB).round(),
        speed: '890 KB/s',
        eta: 'Done',
        session: 'prod-server-01',
        status: TransferStatus.done,
      ),
    ];
