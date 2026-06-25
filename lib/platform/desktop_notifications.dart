import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Whether a finished transfer should raise an OS notification: only when the
/// feature is [enabled] and the app window is **not** focused (so we never
/// notify about something the user is already watching). Pure + testable.
bool shouldNotify({required bool enabled, required bool windowFocused}) =>
    enabled && !windowFocused;

/// Thin, defensive wrapper around `local_notifier`. Every call is guarded so a
/// platform that can't post notifications never crashes a transfer. Created and
/// `setup()`-ed by `main()` on desktop; null elsewhere (tests) → a no-op.
class DesktopNotifications {
  bool _ready = false;

  Future<void> setup() async {
    try {
      await localNotifier.setup(appName: 'Drag');
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> show(String title, String body, {VoidCallback? onClick}) async {
    if (!_ready) return;
    try {
      final n = LocalNotification(title: title, body: body);
      if (onClick != null) n.onClick = onClick;
      await n.show();
    } catch (_) {
      // Best-effort — a failed notification must never break a transfer.
    }
  }
}

/// Live window-focus flag, updated by the app's window listener. Defaults to
/// focused so we don't notify on startup.
bool gWindowFocused = true;

/// The app-wide notifier, wired by `main()` on desktop (null in tests).
DesktopNotifications? gDesktopNotifications;

/// Brings the window to the foreground (wired by `main()` from window_manager).
void Function()? gFocusWindow;
