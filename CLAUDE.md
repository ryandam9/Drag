# CLAUDE.md

Drag is a Flutter **desktop** file-transfer client (macOS / Linux / Windows)
with two browser panes that each point at a **Local**, **Amazon S3**, or
**SFTP** endpoint; files move between panes by drag-and-drop, streamed through
the client.

## Repo map

- `lib/fs/` — storage backends behind a common `StorageBackend` interface
  (`storage_backend.dart` has Local + S3, `sftp_backend.dart` SFTP via
  dartssh2) plus `transfer_service.dart` (streaming copy engine).
  - `lib/fs/aws/` — **hand-written S3 client**: AWS Signature V4 signer
    (`sigv4.dart`) and a minimal S3 REST client (`s3_client.dart`) over
    `dart:io` HttpClient. No AWS SDK — keep it that way.
- `lib/state/` — Riverpod-style providers (sessions, panes, transfers,
  connections, settings, toasts, history).
- `lib/data/` — SQLite stores via `sqflite_common_ffi` (history, connections,
  bookmarks, settings, known hosts, sessions) + `secret_store.dart` (keychain).
- `lib/screens/` — top-level screens (browser, transfer queue, connection
  manager, dashboard, settings, about).
- `lib/models/`, `lib/widgets/`, `lib/platform/`, `lib/theme.dart` — models,
  shared widgets, platform glue, theming.
- `test/` — hermetic unit/widget tests plus gated integration tests
  (`s3_integration_test.dart`, `sftp_integration_test.dart`) that auto-skip
  without `--dart-define` endpoints.

## Build & test

```bash
flutter pub get
flutter test              # hermetic; CI enforces an 80% line-coverage floor
dart format .             # CI has a format gate
flutter analyze
flutter build linux|macos|windows --release
```

Setup details, Linux native deps, and docker one-liners for the gated
integration tests: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Key conventions

- **Secrets never go in SQLite.** Connection records exclude secret fields;
  secrets live in the OS keychain (`flutter_secure_storage` — libsecret /
  Keychain), with a warned memory-only fallback.
- **Staged writes:** Local/SFTP destinations write to a `.drag-partial`
  sibling and rename on success, so failed transfers never truncate the
  target. S3 publishes atomically.
- **SSH host keys are trust-on-first-use** (prompt on first connect, pinned in
  the known-hosts store afterwards).
- Release tags (`v*`) must match `pubspec.yaml` `version:`; bump the version
  and `CHANGELOG.md` together.
