# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-02

### Fixed

Data safety:

- Transfer conflict prompt now defaults to the safe choice instead of
  overwriting the destination.
- S3 downloads validate ranged-GET responses, so a server ignoring the
  `Range` header can no longer corrupt a resumed download.
- Reconnecting a pane rebuilds the correct backend instead of silently
  reusing the previous one.
- Keychain reads no longer race app startup, so saved secrets are reliably
  available when the first connection opens.
- Pausing a transfer preserves the partial `.drag-partial` progress instead of
  discarding it.

UI:

- Filter box no longer swallows keys meant for the file list.
- Transfer-queue filter is actually wired to the queue view.
- Folders can be dragged between panes, not just files.
- Deleting a saved connection now asks for confirmation.
- Live log panel streams connection activity as it happens.

### Changed

Performance:

- `credential_process` results are cached asynchronously instead of being
  re-executed on every request.
- Object metadata is fetched with S3 `HeadObject` rather than listing the
  prefix.
- Transient network errors are retried with backoff instead of failing the
  transfer immediately.
- Bucket discovery is bounded so misconfigured accounts can't hang the
  connection flow.
- History refresh is debounced to avoid redundant SQLite reads during busy
  transfers.

### Added

CI / tooling:

- S3 integration job running the gated end-to-end tests against a MinIO
  container.
- Test matrix on macOS and Windows in addition to the existing Linux
  analyze/coverage job.
- `dart format` gate in CI.
- Dependabot updates for pub packages and GitHub Actions.
- Release workflow: SHA256SUMS attached to releases, generated release notes,
  and a guard that the release tag matches the pubspec version.

## [1.0.0]

Initial versioned release of Drag — a cross-platform desktop file-transfer
client (Flutter) for Local, Amazon S3 and SFTP endpoints, with a hand-written
S3 SigV4 client, drag-and-drop transfers between panes, transfer history,
bookmarks, OS-keychain secret storage and TOFU SSH host-key verification.
Covers all previously unversioned history.

[1.1.0]: https://github.com/ryandam9/Drag/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ryandam9/Drag/releases/tag/v1.0.0
