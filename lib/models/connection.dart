enum Protocol { sftp, s3 }

extension ProtocolLabel on Protocol {
  String get label => switch (this) {
        Protocol.sftp => 'SFTP',
        Protocol.s3 => 'S3',
      };
}

/// How a pane talks to its storage. Drives which backend is built.
enum EndpointKind { local, sftp, s3 }

enum AuthMethod { password, privateKey }

extension AuthMethodLabel on AuthMethod {
  String get label => switch (this) {
        AuthMethod.password => 'Password',
        AuthMethod.privateKey => 'Private Key',
      };
}

enum ConnGroup { recent, saved }

int _idSeq = 0;

class Connection {
  /// Stable identifier used for persistence (and, later, keychain lookups).
  String id;
  String name;
  String host;
  int port;
  String username;
  Protocol protocol;
  AuthMethod auth;
  String keyFile;
  String passphrase;
  String password;
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
    this.id = '',
    required this.name,
    this.host = '',
    this.port = 22,
    this.username = '',
    this.protocol = Protocol.sftp,
    this.auth = AuthMethod.privateKey,
    this.keyFile = '',
    this.passphrase = '',
    this.password = '',
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

  /// Generates a process-unique id for a new connection.
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  /// Serializes everything EXCEPT secrets (password, passphrase, secret access
  /// key, session token). Secrets belong in the OS keychain — see issue #16.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'protocol': protocol.name,
        'auth': auth.name,
        'keyFile': keyFile,
        'remotePath': remotePath,
        'localPath': localPath,
        'timeout': timeout,
        'keepAlive': keepAlive,
        'openInNewTab': openInNewTab,
        'group': group.name,
        'details': details,
        'lastConnected': lastConnected,
        'accessKeyId': accessKeyId,
        'region': region,
        'bucket': bucket,
        'endpoint': endpoint,
        'useSsl': useSsl,
      };

  factory Connection.fromJson(Map<String, Object?> m) {
    T byName<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.firstWhere((e) => e.name == v, orElse: () => fallback);
    return Connection(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      host: (m['host'] as String?) ?? '',
      port: (m['port'] as int?) ?? 22,
      username: (m['username'] as String?) ?? '',
      protocol: byName(Protocol.values, m['protocol'], Protocol.sftp),
      auth: byName(AuthMethod.values, m['auth'], AuthMethod.privateKey),
      keyFile: (m['keyFile'] as String?) ?? '',
      remotePath: (m['remotePath'] as String?) ?? '/',
      localPath: (m['localPath'] as String?) ?? '',
      timeout: (m['timeout'] as int?) ?? 30,
      keepAlive: (m['keepAlive'] as bool?) ?? true,
      openInNewTab: (m['openInNewTab'] as bool?) ?? false,
      group: byName(ConnGroup.values, m['group'], ConnGroup.saved),
      details: (m['details'] as String?) ?? '',
      lastConnected: (m['lastConnected'] as String?) ?? '',
      accessKeyId: (m['accessKeyId'] as String?) ?? '',
      region: (m['region'] as String?) ?? 'us-east-1',
      bucket: (m['bucket'] as String?) ?? '',
      endpoint: (m['endpoint'] as String?) ?? '',
      useSsl: (m['useSsl'] as bool?) ?? true,
    );
  }
}
