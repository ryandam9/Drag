<p align="center">
  <img src="assets/icons/drag.png" width="96" alt="Drag icon"/>
</p>

# Drag

[![CI](https://github.com/ryandam9/Drag/actions/workflows/ci.yml/badge.svg)](https://github.com/ryandam9/Drag/actions/workflows/ci.yml)

A cross-platform **file transfer client** built with Flutter for macOS, Linux
& Windows desktop — a dark, dense, developer-focused UI with drag-and-drop
transfers between **local disk, Amazon S3, and SFTP** endpoints.

## Endpoints

Either browser pane can point at any endpoint, so you can move files between
any combination:

- **Local ⇄ S3** — upload/download between your machine and an S3 bucket.
- **S3 ⇄ S3 (cross-account)** — copy between two buckets in *different* AWS
  accounts/regions. Copies are **streamed** through the client
  (`source.openRead → dest.write`), so each side can use its own credentials —
  no server-side copy and no shared-account requirement.
- **SFTP ⇄ Local / S3** — real SFTP via `dartssh2` (password or private-key
  auth); browse, upload and download against any SSH server, and stream
  to/from S3 or local with no temp files.

**S3 is real**, and talks to S3 through a **hand-written client** — there is no
official AWS SDK for Dart, so Drag ships its own AWS **Signature V4** signer
(`lib/fs/aws/sigv4.dart`) and a minimal S3 REST client (`lib/fs/aws/s3_client.dart`)
built on `dart:io` `HttpClient` (streamed `ListObjectsV2` / `GetObject` /
`PutObject`). No third-party S3 SDK is used. Configure an S3 connection in the
**Connection Manager** (Access Key, Secret, optional Session Token, Region,
Bucket, optional custom endpoint for S3-compatible services), hit **Connect**,
then pick it in a pane. The **Local** endpoint browses your real filesystem.

> The SigV4 implementation is verified against AWS's published signing-key test
> vector, and the full client is exercised end-to-end (upload/list/download +
> cross-bucket copy) in `test/s3_integration_test.dart`.

> Credentials are held in memory for the session and are not persisted to disk.

## Screens

| Screen | Description |
| --- | --- |
| **Browser** | Dual-pane file browser with **multiple session tabs** — connect to several servers at once and switch between them; each tab keeps its own Local ⇄ remote panes, paths and listings. **Each pane has an endpoint picker** (Local / any saved S3 or SFTP connection). Drag a file from either pane onto the other to start a transfer. **Multi-select** (Ctrl/Cmd-click to toggle, Shift-click for a range) drives multi-file drag and delete. **File operations** — new folder, rename, delete (with confirmation) on Local / S3 / SFTP, via toolbar, right-click context menu, or keyboard (F2 rename, Del delete, Backspace up); Back / Forward / Up navigation history per pane. Async listing with loading/error/not-connected states, breadcrumbs, live progress strip and a log console. |
| **Connection Manager** | Saved/recent sessions sidebar with online indicators. Form adapts to the protocol: SSH fields for SFTP, or **S3 credentials** (access key, secret, session token, region, bucket, endpoint, SSL) for S3. New / Save / Duplicate / Delete **persist to SQLite** (secrets excluded — see #16). |
| **Transfer Queue** | Active / queued / paused / done / error transfers with per-file progress, speed, ETA, a status filter, an aggregate stats bar and an adjustable parallel-thread count. |
| **History Dashboard** | Persistent transfer history backed by **SQLite** — stat cards (total / succeeded / failed / data transferred / avg speed) and a table of past transfers (file, route, size, time taken, speed, when, status). Refresh / clear. |
| **Preferences** | Categorised settings that **apply live and persist** (SQLite): accent color recolors the whole UI, UI font size rescales text, "show hidden files" filters dot-files in every pane, and the permissions-column / startup-log toggles take effect immediately. Window size & position are remembered across launches (`window_manager`). |

While a transfer runs, a floating **progress card** (animated ring + bar, live
speed/ETA, "big file" badge) appears. On completion an in-app **notification**
reports the destination path, size and time taken. Every finished transfer is
written to the SQLite history database.

## Highlights

- **Drag & drop** local files onto the remote pane to start a transfer.
- **Live transfer engine** (`TransfersNotifier`) streams real bytes through
  `TransferService` and fires completion toasts + history records.
- **Riverpod** state management end-to-end; **no dummy data** — connections,
  the queue and the panes all start empty/real.
- **Sessions persist** to SQLite: your open tabs and each pane's endpoint +
  path come back exactly as you left them on the next launch.
- Pixel-faithful dark theme ported from the mockup's CSS variables
  (`lib/theme.dart`), with Inter + JetBrains Mono via `google_fonts`.
- Resizable split between the two file panes.
- Pause / resume / clear-done queue controls and per-row pause/retry.

## Project layout

State is managed with **Riverpod** — each concern is an idiomatic `Notifier`
behind a provider, wired together in the root `ProviderScope`. There is **no
seed/dummy data**: the app starts with no connections and an empty transfer
queue, and every endpoint (Local / S3 / SFTP) is real.

```
lib/
  main.dart                    App entry: opens SQLite stores + ProviderScope overrides
  app_shell.dart               Title bar + nav rail + screen switcher + toasts
  theme.dart                   Colors, text styles, ThemeData
  state/
    app.dart                   Barrel export for the provider layer
    providers.dart             DI seams for the SQLite stores + startup data
    navigation_provider.dart   NavNotifier: the active screen
    toasts_provider.dart       ToastsNotifier: transient notifications
    settings_provider.dart     SettingsNotifier: appearance, applied live + persisted
    connections_provider.dart  ConnectionsNotifier: saved connections + selection (CRUD)
    sessions_provider.dart     SessionsNotifier: tabs, panes, backends, file ops, restore
    transfers_provider.dart    TransfersNotifier: the live transfer queue
    history_provider.dart      HistoryNotifier: SQLite-backed transfer history
    pane_controller.dart       Per-pane endpoint/path/listing/selection state
  fs/
    storage_backend.dart       StorageBackend interface + LocalBackend + S3Backend
    sftp_backend.dart          Real SFTP backend (dartssh2)
    transfer_service.dart      Streams source → dest with live progress (S3/local/SFTP)
    aws/
      sigv4.dart               Hand-written AWS Signature V4 signer
      s3_client.dart           Minimal S3 REST client (List/Get/Put) on HttpClient
  models/                      FileItem, Connection (incl. S3 fields), Transfer (timing)
  data/
    history_db.dart            SQLite history repository (sqflite_common_ffi)
    connection_store.dart      SQLite store for saved connections (no secrets)
    settings_store.dart        SQLite store for app settings + window geometry
    session_store.dart         SQLite store for open tabs (restored on next launch)
  widgets/                     Title bar, buttons, badges, nav, toasts,
                               transfer_progress (active-transfer card)
  screens/                     browser / connection_manager / transfer_queue /
                               dashboard / settings
```

## Running

```bash
flutter pub get

# Pick your desktop platform:
flutter run -d linux
flutter run -d macos
flutter run -d windows
```

## Building a release bundle

```bash
flutter build linux --release     # build/linux/x64/release/bundle/
flutter build macos --release
flutter build windows --release
```

## Tests & analysis

```bash
flutter analyze
flutter test                 # 195 hermetic tests
flutter test --coverage      # ~89% line coverage
```

Coverage spans the whole stack (≈89% of lines; the only thin spots are
`main()`'s window-manager bootstrap and the live-SSH paths of `SftpBackend`,
which need a real server). Test helpers live in `test/support/`:
`harness.dart` builds a `ProviderContainer` with the SQLite stores stubbed;
`memory_backend.dart` is an in-memory `StorageBackend` for widget tests (real
disk I/O can't resolve under `testWidgets`' fake-async clock);
`fake_remote_backend.dart` is a read-only remote stand-in.

| File | What it covers |
| --- | --- |
| `models_test.dart` | byte/date formatting, `FileItem`, `Connection` (S3 readiness), `Transfer` |
| `toast_test.dart` | `ToastKind` icon/colour/foreground styling, `ToastMessage` fields |
| `backends_test.dart` | `LocalBackend` (real temp-dir listing + byte round-trip), `S3Backend` path math, `FakeRemoteBackend` |
| `s3_client_test.dart` | `S3Client` + `S3Backend` against an **in-process mock S3 server**: ListObjectsV2 paging, get/put/delete/copy, error parsing, folder mapping |
| `sftp_backend_test.dart` | `SftpBackend` path helpers, readiness, and connection/key-file error paths |
| `pane_controller_test.dart` | listing, navigation (enter dir / `..` / up), selection, breadcrumb, not-ready short-circuit |
| `transfer_test.dart` / `transfer_service_test.dart` | `TransferService` streaming, progress/ETA, and error truncation |
| `app_state_test.dart` | provider layer: navigation, queue controls, toasts, endpoint switching, `connect`, and all `dropTransfer` decisions (incl. a real Local→Local transfer + history recording) |
| `provider_extra_test.dart` | toast auto-dismiss, settings persistence, history refresh/clear, backend caching, focus/switch edge cases |
| `connection_store_test.dart` | `Connection` JSON (no secrets), `ConnectionStore` SQLite CRUD, `ConnectionsNotifier` persistence |
| `session_store_test.dart` | `SessionStore` SQLite round-trip + `SessionsNotifier` tab restore/persistence |
| `sigv4_test.dart` | AWS SigV4 — signing key vs **AWS's published test vector**, header/encoding |
| `browser_screen_test.dart` | dual-pane browser: tabs, endpoint picker, file ops (new/rename/delete), folder open, drag-and-drop transfer, queue strip, log panel |
| `screens_widget_test.dart` | Connection Manager (S3 vs SSH form + empty state), Transfer Queue, Settings toggles, Dashboard, toasts |
| `transfer_progress_test.dart` | the floating active-transfer card (ring %, big-file badge, ETA, multi-transfer summary) |
| `settings_store_test.dart` | `AppSettings` JSON round-trip, `SettingsStore` SQLite save/load, and the `SettingsNotifier` applying/persisting settings (accent, font size, hidden-file filter, reset) |
| `widget_test.dart` | app boot (Local ⇄ Local) + nav rail |

Real end-to-end S3 tests live in `s3_integration_test.dart` and **auto-skip**
unless an S3 server is supplied:

```bash
flutter test test/s3_integration_test.dart \
  --dart-define=S3_ENDPOINT=127.0.0.1:9000 \
  --dart-define=S3_BUCKET=bucket-a --dart-define=S3_BUCKET2=bucket-b \
  --dart-define=S3_KEY=... --dart-define=S3_SECRET=...
```
