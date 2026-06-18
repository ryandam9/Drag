# FileSync

A cross-platform **SFTP/FTP file transfer client** built with Flutter for
macOS, Linux & Windows desktop. This is a faithful, fully-interactive
implementation of the FileSync mockup — a dark, dense, developer-focused UI
with drag-and-drop transfers.

> The networking layer is simulated (no real SSH connection is opened). The
> focus is a polished, production-quality desktop **UI** with realistic mock
> data and a live transfer engine.

## Screens

| Screen | Description |
| --- | --- |
| **Browser** | Dual-pane local ⇄ remote file browser. Drag a local file onto the remote pane to enqueue an upload. Session tabs, breadcrumbs, toolbar, live progress strip and an SFTP log console. |
| **Connection Manager** | Saved/recent sessions sidebar with online indicators, plus a full connection form (protocol, host, port, auth method tabs, key file, paths, options). |
| **Transfer Queue** | Active / queued / paused / done / error transfers with per-file progress, speed, ETA, a status filter, an aggregate stats bar and an adjustable parallel-thread count. |
| **Preferences** | Categorised settings with theme, accent-color swatches, fonts and toggles. |

In-app toast notifications surface transfer events (success / error / info).

## Highlights

- **Drag & drop** local files onto the remote pane to start a transfer.
- **Live transfer engine** (`AppState`) advances active transfers, promotes
  queued ones up to the thread budget, and fires completion toasts.
- Pixel-faithful dark theme ported from the mockup's CSS variables
  (`lib/theme.dart`), with Inter + JetBrains Mono via `google_fonts`.
- Resizable split between the two file panes.
- Pause / resume / clear-done queue controls and per-row pause/retry.

## Project layout

```
lib/
  main.dart                 App entry + AppScope wiring
  app_shell.dart            Title bar + nav rail + screen switcher + toasts
  theme.dart                Colors, text styles, ThemeData
  state/app_state.dart      ChangeNotifier: navigation, panes, queue, toasts
  models/                   FileItem, Connection, Transfer
  data/mock_data.dart       Seed data matching the mockup
  widgets/                  Reusable chrome (title bar, buttons, badges, nav, toasts)
  screens/                  browser / connection_manager / transfer_queue / settings
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
flutter test
```
