import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/connection.dart';
import '../models/file_item.dart';
import 'host_key_verifier.dart';
import 'storage_backend.dart';

/// Real SFTP endpoint backed by `dartssh2`. Connects lazily on first use and
/// reuses the session for subsequent operations, so it composes with the
/// streamed [TransferService] (SFTP↔Local, SFTP↔S3) like the other backends.
///
/// Auth: password or private key (with optional passphrase). Host keys are
/// checked trust-on-first-use via [globalHostKeyVerifier]: the first key seen
/// for a host is remembered and accepted, a later mismatch is rejected. When
/// no verifier is wired (e.g. the known-hosts store failed to open) the key is
/// accepted — see [_verifyHostKey].
class SftpBackend extends StorageBackend {
  SftpBackend(this.connection);

  final Connection connection;

  SSHClient? _client;
  SftpClient? _sftp;
  Future<SftpClient>? _connecting;

  @override
  EndpointKind get kind => EndpointKind.sftp;

  @override
  String get badge => 'SFTP';

  @override
  bool get isReady => connection.host.isNotEmpty && connection.username.isNotEmpty;

  @override
  String get initialPath => connection.remotePath.isEmpty ? '/' : connection.remotePath;

  @override
  String displayPath(String path) =>
      'sftp://${connection.username}@${connection.host}$path';

  // ── Connection (lazy, shared) ──
  Future<SftpClient> _ensure() {
    if (_sftp != null) return Future.value(_sftp!);
    return _connecting ??= _connect();
  }

  Future<SftpClient> _connect() async {
    try {
      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: Duration(seconds: connection.timeout.clamp(1, 60)),
      );
      final client = SSHClient(
        socket,
        username: connection.username,
        identities: await _identities(),
        onPasswordRequest: connection.auth == AuthMethod.password
            ? () => connection.password
            : null,
        // Host-key verification: prompt to confirm an unknown host's
        // fingerprint on first connect, accept a matching one, reject a changed
        // key (possible MITM). A null verifier (e.g. tests) accepts the key.
        onVerifyHostKey: _verifyHostKey,
      );
      _client = client;
      _sftp = await client.sftp();
      return _sftp!;
    } catch (e) {
      _connecting = null; // allow retry on next attempt
      rethrow;
    }
  }

  /// dartssh2 passes the host-key algorithm and the OpenSSH-style fingerprint
  /// bytes (`SHA256:…`). Defer to the global verifier; accept when there's none.
  Future<bool> _verifyHostKey(String type, Uint8List fingerprint) async {
    final verifier = globalHostKeyVerifier;
    if (verifier == null) return true;
    return verifier.verify(connection.host, connection.port, type, utf8.decode(fingerprint));
  }

  Future<List<SSHKeyPair>?> _identities() async {
    if (connection.auth != AuthMethod.privateKey) return null;

    String? path;
    if (connection.keyFile.isNotEmpty) {
      path = _expandHome(connection.keyFile);
      if (!await File(path).exists()) {
        throw Exception('Key file not found: $path');
      }
    } else {
      // No explicit key → fall back to the user's default SSH keys, like the
      // `ssh` command does. This lets a connection that works in the terminal
      // work here too, without having to point at the key by hand.
      for (final name in const ['id_ed25519', 'id_rsa', 'id_ecdsa']) {
        final candidate = _expandHome('~/.ssh/$name');
        if (await File(candidate).exists()) {
          path = candidate;
          break;
        }
      }
      if (path == null) return null; // nothing to offer → password / none
    }

    final pem = await File(path).readAsString();
    return SSHKeyPair.fromPem(
      pem,
      connection.passphrase.isEmpty ? null : connection.passphrase,
    );
  }

  static String _expandHome(String path) {
    if (!path.startsWith('~')) return path;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    return path.replaceFirst('~', home);
  }

  // ── Listing ──
  @override
  Future<List<FileItem>> list(String path) async {
    final sftp = await _ensure();
    final dir = path.isEmpty ? '/' : path;
    final names = await sftp.listdir(dir);

    final items = <FileItem>[];
    if (dir != '/') items.add(const FileItem(name: '..', isDir: true));

    for (final entry in names) {
      final name = entry.filename;
      if (name == '.' || name == '..') continue;
      final attr = entry.attr;
      final longname = entry.longname;
      final isDir = attr.type == SftpFileType.directory ||
          (longname.isNotEmpty && longname.startsWith('d'));
      items.add(FileItem(
        name: name,
        isDir: isDir,
        sizeBytes: isDir ? null : attr.size,
        modified: attr.modifyTime != null
            ? formatModified(DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000))
            : '',
        perms: longname.length >= 10 ? longname.substring(0, 10) : '',
      ));
    }
    items.sort(StorageBackend.dirsFirst);
    return items;
  }

  // ── Read / write ──
  @override
  Future<ReadHandle> openRead(String path) async {
    final sftp = await _ensure();
    final file = await sftp.open(path);
    final stat = await file.stat();
    // Pass the size through as-is: null means the server didn't report one, so
    // the transfer streams the upload instead of declaring a 0-byte length.
    return ReadHandle(file.read(), stat.size);
  }

  @override
  Future<void> write(
    String path,
    Stream<Uint8List> data,
    int length, {
    void Function(int sent)? onProgress,
  }) async {
    final sftp = await _ensure();
    final file = await sftp.open(
      path,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      final writer = file.write(data, onProgress: onProgress);
      await writer.done;
    } finally {
      await file.close();
    }
  }

  // ── Mutations ──
  @override
  Future<void> makeDir(String path) async {
    final sftp = await _ensure();
    await sftp.mkdir(path);
  }

  @override
  Future<void> rename(String fromPath, String toPath) async {
    final sftp = await _ensure();
    await sftp.rename(fromPath, toPath);
  }

  @override
  Future<void> delete(String path, {required bool isDir}) async {
    final sftp = await _ensure();
    if (!isDir) {
      await sftp.remove(path);
      return;
    }
    await _removeDir(sftp, path);
  }

  Future<void> _removeDir(SftpClient sftp, String dir) async {
    for (final entry in await sftp.listdir(dir)) {
      final name = entry.filename;
      if (name == '.' || name == '..') continue;
      final child = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
      final isDir = entry.attr.type == SftpFileType.directory;
      if (isDir) {
        await _removeDir(sftp, child);
      } else {
        await sftp.remove(child);
      }
    }
    await sftp.rmdir(dir);
  }

  // ── Path helpers (POSIX) ──
  @override
  String childPath(String path, String name, bool isDir) {
    final base = path.endsWith('/') ? path : '$path/';
    return '$base$name';
  }

  @override
  String parentPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }

  @override
  String parseInputPath(String input) {
    var s = input.trim();
    // Accept a full sftp://user@host/path location: keep only the path part.
    if (s.startsWith('sftp://')) {
      final rest = s.substring(7);
      final slash = rest.indexOf('/');
      s = slash < 0 ? '/' : rest.substring(slash);
    }
    if (s.isEmpty) return '/';
    if (!s.startsWith('/')) s = '/$s'; // SFTP paths are absolute
    return s;
  }

  @override
  void dispose() {
    _sftp?.close();
    _client?.close();
  }
}
