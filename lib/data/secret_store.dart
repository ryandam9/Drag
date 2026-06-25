import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/connection.dart';

/// Health of the secret backend, so the UI can warn when secrets won't
/// survive a restart.
enum SecretStoreStatus {
  /// Secrets are written to the OS keychain and persist across restarts.
  keychain,

  /// The keychain is unavailable; secrets are kept in memory only and are
  /// lost when the app closes.
  memoryFallback,
}

/// Persists a connection's secrets (SSH password / key passphrase, S3 secret
/// access key, session token) outside the plain SQLite store. Implementations
/// keep them in the OS keychain; a memory fallback is used when none is
/// available (and in tests).
abstract class SecretStore {
  /// Save [c]'s secrets, keyed by its `id`.
  Future<void> save(Connection c);

  /// Current backend health — whether secrets are persisted or memory-only.
  SecretStoreStatus get status;

  /// Load [c]'s secrets back into the connection (no-op if none stored).
  Future<void> load(Connection c);

  /// Remove the secrets for connection [id].
  Future<void> delete(String id);

  // ── Shared (de)serialisation of the secret subset ──
  static Map<String, String> secretsOf(Connection c) => {
        'password': c.password,
        'passphrase': c.passphrase,
        'secretAccessKey': c.secretAccessKey,
        'sessionToken': c.sessionToken,
      };

  static void apply(Connection c, Map<String, dynamic> m) {
    String s(String k) => (m[k] as String?) ?? '';
    c.password = s('password');
    c.passphrase = s('passphrase');
    c.secretAccessKey = s('secretAccessKey');
    c.sessionToken = s('sessionToken');
  }

  static bool _hasAny(Connection c) =>
      c.password.isNotEmpty ||
      c.passphrase.isNotEmpty ||
      c.secretAccessKey.isNotEmpty ||
      c.sessionToken.isNotEmpty;
}

/// In-memory secret store — the graceful fallback when no OS keychain is
/// available, and the implementation used by tests.
class MemorySecretStore implements SecretStore {
  final Map<String, String> _store = {};

  @override
  SecretStoreStatus get status => SecretStoreStatus.memoryFallback;

  @override
  Future<void> save(Connection c) async {
    if (c.id.isEmpty) return;
    _store[c.id] = jsonEncode(SecretStore.secretsOf(c));
  }

  @override
  Future<void> load(Connection c) async {
    final raw = _store[c.id];
    if (raw == null) return;
    SecretStore.apply(c, jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

/// Stores secrets in the OS keychain via `flutter_secure_storage` (libsecret on
/// Linux, Keychain on macOS). If the platform backend is unavailable it
/// transparently degrades to an in-memory map so the app keeps working.
class KeychainSecretStore implements SecretStore {
  KeychainSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _fallback = {};
  bool _degraded = false;

  @override
  SecretStoreStatus get status =>
      _degraded ? SecretStoreStatus.memoryFallback : SecretStoreStatus.keychain;

  String _key(String id) => 'drag_secret_$id';

  @override
  Future<void> save(Connection c) async {
    if (c.id.isEmpty) return;
    // Nothing secret to store → make sure no stale entry lingers.
    if (!SecretStore._hasAny(c)) return delete(c.id);
    final value = jsonEncode(SecretStore.secretsOf(c));
    if (_degraded) {
      _fallback[c.id] = value;
      return;
    }
    try {
      await _storage.write(key: _key(c.id), value: value);
    } catch (_) {
      _degraded = true;
      _fallback[c.id] = value;
    }
  }

  @override
  Future<void> load(Connection c) async {
    if (c.id.isEmpty) return;
    String? raw;
    if (_degraded) {
      raw = _fallback[c.id];
    } else {
      try {
        raw = await _storage.read(key: _key(c.id));
      } catch (_) {
        _degraded = true;
        raw = _fallback[c.id];
      }
    }
    if (raw == null) return;
    SecretStore.apply(c, jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) async {
    _fallback.remove(id);
    if (_degraded) return;
    try {
      await _storage.delete(key: _key(id));
    } catch (_) {
      _degraded = true;
    }
  }
}
