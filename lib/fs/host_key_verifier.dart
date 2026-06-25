import '../data/known_hosts_store.dart';

/// The result of checking a presented host key against the known-hosts store.
enum HostKeyOutcome {
  /// Never seen before — trusted and remembered (trust-on-first-use).
  trustedFirstUse,

  /// Matches the remembered fingerprint — safe to proceed.
  matched,

  /// Differs from the remembered fingerprint — possible MITM; rejected.
  mismatch,
}

/// Verifies SSH host keys against a persistent known-hosts store using
/// trust-on-first-use: a never-seen host is remembered and accepted; a matching
/// fingerprint is accepted; a changed fingerprint is rejected (the connection
/// is refused) so a key swap can't go unnoticed.
class HostKeyVerifier {
  HostKeyVerifier(this.store, {this.onOutcome});

  final KnownHostsStore store;

  /// Optional observer for surfacing outcomes (e.g. logging first-use / a
  /// mismatch in the connection log).
  final void Function(HostKeyOutcome outcome, KnownHost host)? onOutcome;

  /// Checks (and, on first use, remembers) the host key. Does NOT update a
  /// remembered key on mismatch — that requires the user to forget it first.
  Future<HostKeyOutcome> check(String host, int port, String type, String fingerprint) async {
    final presented = KnownHost(host: host, port: port, type: type, fingerprint: fingerprint);
    final existing = await store.find(host, port);
    final HostKeyOutcome outcome;
    if (existing == null) {
      await store.trust(presented);
      outcome = HostKeyOutcome.trustedFirstUse;
    } else if (existing.fingerprint == fingerprint) {
      outcome = HostKeyOutcome.matched;
    } else {
      outcome = HostKeyOutcome.mismatch;
    }
    onOutcome?.call(outcome, presented);
    return outcome;
  }

  /// Convenience for `onVerifyHostKey`: accept unless the key changed.
  Future<bool> verify(String host, int port, String type, String fingerprint) async =>
      (await check(host, port, type, fingerprint)) != HostKeyOutcome.mismatch;
}

/// The app-wide verifier, wired by `main()` from the opened [KnownHostsStore].
/// When null (e.g. the store failed to open, or in tests), [SftpBackend]
/// falls back to accepting host keys as before.
HostKeyVerifier? globalHostKeyVerifier;
