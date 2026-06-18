enum Protocol { sftp, ftp, ftps, scp }

extension ProtocolLabel on Protocol {
  String get label => switch (this) {
        Protocol.sftp => 'SFTP',
        Protocol.ftp => 'FTP',
        Protocol.ftps => 'FTPS',
        Protocol.scp => 'SCP',
      };
}

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
  });
}
