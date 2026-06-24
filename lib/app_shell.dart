import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/browser_screen.dart';
import 'screens/connection_manager_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfer_queue_screen.dart';
import 'state/app.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/nav_rail.dart';
import 'widgets/toast_overlay.dart';
import 'widgets/transfer_progress.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navProvider);
    final nav = ref.read(navProvider.notifier);

    final (title, actions) = switch (screen) {
      AppScreen.browser => (
          _browserTitle(ref),
          [TbButton('⊕ New Session', onTap: () => nav.go(AppScreen.connections))],
        ),
      AppScreen.connections => ('Connection Manager', <Widget>[]),
      // Queue & Dashboard render their own bulk actions in the screen header,
      // so the title bar stays clean (no duplicate buttons).
      AppScreen.queue => ('Transfer Queue', <Widget>[]),
      AppScreen.dashboard => ('History Dashboard', <Widget>[]),
      AppScreen.settings => ('Preferences', <Widget>[]),
    };

    final body = switch (screen) {
      AppScreen.browser => const BrowserScreen(),
      AppScreen.connections => const ConnectionManagerScreen(),
      AppScreen.queue => const TransferQueueScreen(),
      AppScreen.dashboard => const DashboardScreen(),
      AppScreen.settings => const SettingsScreen(),
    };

    return Scaffold(
      backgroundColor: FsColors.bgScaffold,
      body: Stack(children: [
        Column(children: [
          TitleBar(title: title, actions: actions),
          Expanded(
            child: Row(children: [
              const NavRail(),
              Expanded(
                child: Container(
                  color: FsColors.bgScaffold,
                  child: _MinSize(
                    minWidth: 820,
                    minHeight: 520,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: KeyedSubtree(key: ValueKey(screen), child: body),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
        const ActiveTransferOverlay(),
        const ToastOverlay(),
      ]),
    );
  }

  String _browserTitle(WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    final count = state.sessions.length;
    return 'Drag — ${ref.read(sessionsProvider.notifier).activeSession.title}'
        '${count > 1 ? '  ($count sessions)' : ''}';
  }
}

/// Keeps [child] at a usable minimum size: when the window shrinks below the
/// app's design minimum, the content stops squashing (which would overflow the
/// dense dual-pane / table layouts) and becomes scroll-able in the cramped axis
/// instead. At or above the minimum it just fills the space.
class _MinSize extends StatelessWidget {
  final double minWidth;
  final double minHeight;
  final Widget child;
  const _MinSize({required this.minWidth, required this.minHeight, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final tooNarrow = c.maxWidth < minWidth;
      final tooShort = c.maxHeight < minHeight;
      if (!tooNarrow && !tooShort) return child;
      final w = tooNarrow ? minWidth : c.maxWidth;
      final h = tooShort ? minHeight : c.maxHeight;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: SizedBox(width: w, height: h, child: child),
        ),
      );
    });
  }
}
