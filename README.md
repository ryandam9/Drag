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
**Connection Manager** (Region, Bucket, optional custom endpoint for
S3-compatible services), choose a **credential source**, hit **Connect** (or
**🔌 Test**), then pick it in a pane. The **Local** endpoint browses your real
filesystem.

**Credentials — two sources:**

- **Typed** — Access Key, Secret and optional Session Token entered in the form
  (held in memory only, never written to disk).
- **AWS profile** — tick *"Load credentials from `~/.aws/credentials`"* and give
  a profile name (default `default`, or `$AWS_PROFILE`). The access key, secret
  and **session token** are read from the shared credentials file
  (`lib/fs/aws/aws_profile.dart`) **fresh on every request**, so when an external
  process refreshes your temporary STS credentials on disk, Drag picks them up
  automatically — no re-pasting. Region falls back to `~/.aws/config` if the form
  field is blank.

**Bucket discovery (multi-bucket / multi-region).** Leave the **Bucket** field
blank and the connection lists **all buckets in the account** (`ListBuckets`) as
folders at the root; navigate into any one to browse it. Each bucket's region is
resolved automatically (`GetBucketLocation`, cached) and a region-correct client
is used for its objects, so an account with buckets spread across regions works
from a single connection. Set a Bucket to pin the connection to just that one.

A connection is **verified** by a real, SigV4-signed `ListObjectsV2` (or
`ListBuckets` in discovery mode); the **🔌 Test** button reports success or AWS's
actual error (`ExpiredToken`, `AccessDenied`, `NoSuchBucket`, …).

> The SigV4 implementation is verified against AWS's published signing-key test
> vector, and the full client is exercised end-to-end (upload/list/download +
> cross-bucket copy) in `test/s3_integration_test.dart`. Large objects upload via
> **multipart** (CreateMultipartUpload → UploadPart → Complete, with
> AbortMultipartUpload on failure) above a size threshold; smaller objects use a
> single PUT.

> Typed secrets are held in memory for the session and are not persisted to disk.
> S3 connections can instead use the **AWS credential chain** — environment
> variables (`AWS_ACCESS_KEY_ID` / …) take precedence, falling back to the named
> `~/.aws/credentials` profile — resolved per request so rotated temporary
> credentials are picked up automatically. A connection can also **assume an IAM
> role** (STS `AssumeRole`): set a role ARN and the base credentials are
> exchanged for temporary, auto-refreshed credentials scoped to that role.

> SFTP host keys are verified **trust-on-first-use**: the server's key is
> remembered on first connect (SQLite) and a later change is rejected as a
> possible man-in-the-middle. Manage trusted keys in Settings → Fingerprints.

## Screens

| Screen | Description |
| --- | --- |
| **Browser** | Dual-pane file browser with **multiple session tabs** — connect to several servers at once and switch between them; each tab keeps its own Local ⇄ remote panes, paths and listings. **Each pane has an endpoint picker** (Local / any saved S3 or SFTP connection). Drag a file from either pane onto the other to start a transfer. **Multi-select** (Ctrl/Cmd-click to toggle, Shift-click for a range) drives multi-file drag and delete. **File operations** — new folder, rename, delete (with confirmation) on Local / S3 / SFTP, via toolbar, right-click context menu, or keyboard. **Full keyboard navigation** — ↑/↓ move the selection, Home/End jump to the ends, PageUp/PageDown page through, Enter opens a folder, type-ahead jumps to a matching name, Tab switches the focused pane, Space previews the selected file, plus F2 rename, Del delete and Backspace up; Back / Forward / Up navigation history per pane. **Quick preview** (toolbar, right-click or Space) peeks at a file in a popup — a bounded text excerpt, an inline image, or a metadata notice for binary/oversized files — streaming only a bounded amount from any backend. Async listing with loading/error/not-connected states, **clickable breadcrumbs** (jump up any number of levels), **sortable columns** (name / size / modified / perms, click to sort, click again to reverse), **type-specific file icons** (by extension) and a **live in-pane filter** (filters the focused pane by name), plus a live progress strip and a log console. |
| **Connection Manager** | Saved-sessions sidebar with online indicators, a **live search box** (filters by name, tag, host, bucket, region or username) and **tag grouping** (set a "Group / tag" like _Production_ on each connection; the sidebar folds them into sections, untagged last). Form adapts to the protocol: SSH fields for SFTP, or **S3 credentials** (access key, secret, session token, region, bucket, endpoint, SSL) for S3. New / Save / Duplicate / Delete **persist to SQLite** (secrets excluded — see #16). |
| **Transfer Queue** | Active / queued / paused / done / error transfers with per-file progress, speed, ETA, a status filter, an aggregate stats bar and an adjustable parallel-thread count. **Click any row** for a details panel: full source → destination paths, size, bytes done, speed, ETA, elapsed, attempts and the error message, with per-transfer **Pause / Resume / Cancel** / Retry and copy-path actions (live-updating while active). Pause and cancel really **abort the in-flight byte stream** (cancel discards the partial destination file); resume restarts the transfer. |
| **History Dashboard** | Persistent transfer history backed by **SQLite** — stat cards (total / succeeded / failed / data transferred / avg speed) and a table of past transfers (file, route, size, time taken, speed, when, status). **Search** across name / path / endpoint plus **status** (succeeded / failed), **direction** (upload / download) and **date-window** (last 24h / 7d / 30d) filters, with a live match count, a throughput-over-time sparkline, and a per-endpoint breakdown bar (transfers + bytes, busiest first). **Export CSV** writes every record (name, source, dest, size, direction, duration, speed, success, error, session, timestamp) to a timestamped file (falling back to the clipboard). Refresh / clear. |
| **Preferences** | Categorised settings that **apply live and persist** (SQLite), including a **Fingerprints** pane that lists trusted SSH host keys (with per-host and bulk *Forget*): a **Light / Dark / System** brightness mode (each bird palette has a coherent dark variant; System follows the OS live), a **transfer speed limit** (a shared token-bucket caps the combined throughput of all active transfers; unlimited by default), accent color recolors the whole UI, UI font size rescales text, "show hidden files" filters dot-files in every pane, and the permissions-column / startup-log toggles take effect immediately. Window size & position are remembered across launches (`window_manager`). |

While a transfer runs, a floating **progress card** (animated ring + bar, live
speed/ETA, "big file" badge) appears. On completion an in-app **notification**
reports the destination path, size and time taken. When the window is
unfocused, a finished transfer also raises an **OS desktop notification**
(`local_notifier`); clicking it refocuses Drag and opens the queue. (Toggle in
Settings → Transfers.) Every finished transfer is
written to the SQLite history database.

## Highlights

- **Drag & drop** local files onto the remote pane to start a transfer.
- **Live transfer engine** (`TransfersNotifier`) streams real bytes through
  `TransferService` and fires completion toasts + history records. Transient
  failures **auto-retry with backoff**, and a retried download **resumes from
  the partial file** (HTTP Range / file seek) instead of restarting.
- **Riverpod** state management end-to-end; **no dummy data** — connections,
  the queue and the panes all start empty/real.
- **Sessions persist** to SQLite: your open tabs and each pane's endpoint +
  path come back exactly as you left them on the next launch.
- Deep-navy dark theme using the **Feathers "Rainbow Bee-eater"** palette
  (`lib/theme.dart`) — navy surfaces with bright-blue / cyan accents, matching
  the `attendance-register` app, with Inter + JetBrains Mono via `google_fonts`.
- Resizable split between the two file panes.
- Pause / resume / clear-done queue controls and per-row pause/retry.
- **Concurrency limiter**: at most *N* transfers (the "Threads" setting) run at
  once; the rest queue and start as slots free. Raising the limit starts more
  immediately; pausing/cancelling an active one frees a slot.

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

## Building from source

Drag is a Flutter **desktop** app. It is developed and CI-tested against
**Flutter 3.44.2** (Dart 3.12) — match that version (e.g. with `fvm`) for a
reproducible build. macOS and Linux are both first-class targets.

### Common steps

```bash
git clone https://github.com/ryandam9/Drag.git
cd Drag
flutter --version            # should report 3.44.2 (channel stable)
flutter pub get
```

Make sure desktop support is enabled (on by default in recent Flutter):

```bash
flutter config --enable-macos-desktop --enable-linux-desktop
flutter devices              # macOS / Linux should be listed
```

### 🐧 Linux

**Toolchain prerequisites** (Debian/Ubuntu — adjust for your distro):

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev \
  libsqlite3-0 libsqlite3-dev \    # SQLite is used for history/connections/settings/sessions
  libsecret-1-dev \                # OS keychain for connection secrets (flutter_secure_storage)
  libnotify-dev                    # desktop notifications (local_notifier)
```

**Build a `.deb` installer** (installs to `/usr/lib/drag` with a launcher,
`.desktop` entry and icon):

```bash
flutter build linux --release
scripts/package-linux-deb.sh build/linux/x64/release/bundle 1.0.0 drag-linux-x64.deb
```

Tagged releases (`v*`) attach both `drag-linux-x64.tar.gz` and
`drag-linux-x64.deb` via the release workflow.

**Run from source:**

```bash
flutter run -d linux
```

**Build a release binary:**

```bash
flutter build linux --release
```

Output bundle (self-contained — ships its Flutter engine, plugins and
`libsqlite3.so`):

```
build/linux/x64/release/bundle/
├── drag                     ← the executable
├── data/                    ← Flutter assets + ICU
└── lib/                     ← engine + plugin .so files (incl. libsqlite3.so)
```

Run it directly or zip/tar the whole `bundle/` directory to distribute:

```bash
./build/linux/x64/release/bundle/drag
```

### 🍎 macOS

**Toolchain prerequisites:**

- **Xcode** (full install from the App Store) + command-line tools:
  `xcode-select --install`
- **CocoaPods**: `sudo gem install cocoapods` (Flutter regenerates
  `macos/Podfile` and runs `pod install` automatically on first build)
- Minimum deployment target: **macOS 10.15**

**Run from source:**

```bash
flutter run -d macos
```

**Build a release `.app`:**

```bash
flutter build macos --release
```

Output:

```
build/macos/Build/Products/Release/Drag.app
```

Launch it with `open build/macos/Build/Products/Release/Drag.app`.

> **App Sandbox is intentionally disabled** (`macos/Runner/*.entitlements`).
> Drag is a file manager that browses the *whole* filesystem from the Local
> pane and opens outbound **S3 / SFTP** connections — neither is possible under
> the sandbox without security-scoped bookmarks, so the sandbox is turned off
> and `com.apple.security.network.client` is granted. This suits **direct
> distribution**; a Mac App Store build would need the sandbox re-enabled with
> a different file-access model.

**Distribution (optional):** sign and notarize for Gatekeeper-friendly
delivery:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: <YOUR NAME> (<TEAMID>)" \
  build/macos/Build/Products/Release/Drag.app
xcrun notarytool submit Drag.zip --apple-id <id> --team-id <TEAMID> --wait
xcrun stapler staple build/macos/Build/Products/Release/Drag.app
```

### Windows

```bash
flutter build windows --release   # build/windows/x64/runner/Release/
```

### CI

`.github/workflows/ci.yml` runs `flutter analyze` + `flutter test` and then
builds release bundles for **Linux, macOS and Windows** on every push/PR, so
all three targets are verified to compile on each change.

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
