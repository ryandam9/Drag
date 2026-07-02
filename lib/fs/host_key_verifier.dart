import '../data/known_hosts_store.dart';

/// The result of checking a presented host key against the known-hosts store.
enum HostKeyOutcome {
  /// Never seen before — accepted on first use (and remembered, unless the
  /// user chose "trust once").
  trustedFirstUse,

  /// Matches the remembered fingerprint — safe to proceed.
  matched,

  /// Differs from the remembered fingerprint — possible MITM; rejected.
  mismatch,

  /// First use, but the user declined to trust the presented key; rejected.
  rejectedByUser,
}

/// The fingerprint of an unknown host, presented to the user for confirmation.
class HostKeyInfo {
  final String host;
  final int port;
  final String type;
  final String fingerprint;
  const HostKeyInfo(this.host, this.port, this.type, this.fingerprint);
}

/// What the user decided when prompted about an unknown host key.
enum HostKeyDecision {
  /// Refuse the connection.
  cancel,

  /// Accept for this connection only — don't persist it.
  trustOnce,

  /// Accept and remember, so future connections match silently.
  trustAndRemember,
}

/// Shows the unknown-host fingerprint and returns the user's [HostKeyDecision].
typedef HostKeyPrompt = Future<HostKeyDecision> Function(HostKeyInfo info);

/// Verifies SSH host keys against a persistent known-hosts store using
/// trust-on-first-use: a matching fingerprint is accepted; a changed
/// fingerprint is rejected (so a key swap can't go unnoticed). On the *first*
/// sighting of a host, it asks [prompt] (when a UI is registered) to confirm
/// the fingerprint before trusting it; with no prompt (headless/tests) it
/// falls back to remembering the key automatically.
class HostKeyVerifier {
  HostKeyVerifier(this.store, {this.onOutcome, this.prompt});

  final KnownHostsStore store;

  /// Optional observer for surfacing outcomes (e.g. logging first-use / a
  /// mismatch in the connection log).
  final void Function(HostKeyOutcome outcome, KnownHost host)? onOutcome;

  /// Registered by the UI to confirm an unknown host's fingerprint. Null →
  /// automatic trust-on-first-use (preserves headless / test behaviour).
  HostKeyPrompt? prompt;

  /// Checks (and, on first use, possibly remembers) the host key. Does NOT
  /// update a remembered key on mismatch — that requires the user to forget it.
  Future<HostKeyOutcome> check(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    final presented = KnownHost(
      host: host,
      port: port,
      type: type,
      fingerprint: fingerprint,
    );
    final existing = await store.find(host, port);

    if (existing != null) {
      final outcome = existing.fingerprint == fingerprint
          ? HostKeyOutcome.matched
          : HostKeyOutcome.mismatch;
      onOutcome?.call(outcome, presented);
      return outcome;
    }

    // First sighting of this host.
    final decision = prompt == null
        ? HostKeyDecision
              .trustAndRemember // no UI → auto-trust as before
        : await prompt!(HostKeyInfo(host, port, type, fingerprint));

    final HostKeyOutcome outcome;
    switch (decision) {
      case HostKeyDecision.trustAndRemember:
        await store.trust(presented);
        outcome = HostKeyOutcome.trustedFirstUse;
      case HostKeyDecision.trustOnce:
        outcome = HostKeyOutcome.trustedFirstUse; // accepted, not persisted
      case HostKeyDecision.cancel:
        outcome = HostKeyOutcome.rejectedByUser;
    }
    onOutcome?.call(outcome, presented);
    return outcome;
  }

  /// Convenience for `onVerifyHostKey`: accept only a match or a trusted first
  /// use; reject a changed key or a user-declined one.
  Future<bool> verify(
    String host,
    int port,
    String type,
    String fingerprint,
  ) async {
    final o = await check(host, port, type, fingerprint);
    return o == HostKeyOutcome.matched || o == HostKeyOutcome.trustedFirstUse;
  }
}

/// The app-wide verifier, wired by `main()` from the opened [KnownHostsStore].
/// When null (e.g. the store failed to open, or in tests), [SftpBackend]
/// falls back to accepting host keys as before.
HostKeyVerifier? globalHostKeyVerifier;
