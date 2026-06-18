enum Protocol { sftp, ftp, ftps, scp, s3 }

extension ProtocolLabel on Protocol {
  String get label => switch (this) {
        Protocol.sftp => 'SFTP',
        Protocol.ftp => 'FTP',
        Protocol.ftps => 'FTPS',
        Protocol.scp => 'SCP',
        Protocol.s3 => 'S3',
      };
}

/// How a pane talks to its storage. Drives which backend is built.
enum EndpointKind { local, sftp, s3 }

enum AuthMethod { password, privateKey, sshAgent, gssapi }

extension AuthMethodLabel on AuthMethod {
  String get label => switch (this) {
        AuthMethod.password => 'Password',
        AuthMethod.privateKey => 'Private Key',
        AuthMethod.sshAgent => 'SSH Agent',
        AuthMethod.gssapi => 'GSSAPI',
      };
}

enum ConnGroup { recent, saved }

class Connection {
  String name;
  String host;
  int port;
  String username;
  Protocol protocol;
  AuthMethod auth;
  String keyFile;
  String passphrase;
  String remotePath;
  String localPath;
  int timeout;
  bool online;
  bool keepAlive;
  bool openInNewTab;
  ConnGroup group;
  String details; // e.g. "Ubuntu 22.04 · OpenSSH 9.3"
  String lastConnected;

  // ── Amazon S3 / S3-compatible settings (used when protocol == s3) ──
  String accessKeyId;
  String secretAccessKey;
  String sessionToken;
  String region;
  String bucket;

  /// Custom endpoint host (e.g. for MinIO or another S3-compatible service).
  /// Empty → derived from [region] as `s3.<region>.amazonaws.com`.
  String endpoint;
  bool useSsl;

  EndpointKind get kind => protocol == Protocol.s3 ? EndpointKind.s3 : EndpointKind.sftp;
  bool get isS3 => protocol == Protocol.s3;

  /// Enough S3 settings present to attempt a real connection.
  bool get hasS3Credentials =>
      accessKeyId.isNotEmpty && secretAccessKey.isNotEmpty && bucket.isNotEmpty;

  Connection({
    required this.name,
    this.host = '',
    this.port = 22,
    this.username = '',
    this.protocol = Protocol.sftp,
    this.auth = AuthMethod.privateKey,
    this.keyFile = '',
    this.passphrase = '',
    this.remotePath = '/',
    this.localPath = '',
    this.timeout = 30,
    this.online = false,
    this.keepAlive = true,
    this.openInNewTab = false,
    this.group = ConnGroup.saved,
    this.details = '',
    this.lastConnected = '',
    this.accessKeyId = '',
    this.secretAccessKey = '',
    this.sessionToken = '',
    this.region = 'us-east-1',
    this.bucket = '',
    this.endpoint = '',
    this.useSsl = true,
  });
}
