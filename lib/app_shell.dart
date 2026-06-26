import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fs/host_key_verifier.dart';
import 'screens/about_screen.dart';
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

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // Register the SFTP host-key confirmation here — AppShell is mounted for
    // the whole app session, so the prompt is available no matter which screen
    // (Browser, Connection Manager, …) initiates a connection. Without this an
    // unknown key could be auto-trusted when connecting before the browser
    // screen ever mounts.
    globalHostKeyVerifier?.prompt = _promptHostKey;
  }

  @override
  void dispose() {
    globalHostKeyVerifier?.prompt = null;
    super.dispose();
  }

  /// Shows an unknown SFTP host's fingerprint and asks whether to trust it.
  /// Defaults to Cancel (reject) if the shell is gone.
  Future<HostKeyDecision> _promptHostKey(HostKeyInfo info) async {
    if (!mounted) return HostKeyDecision.cancel;
    final decision = await showDialog<HostKeyDecision>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FsColors.bgPanel,
        title: Text('Unknown SFTP host key',
            style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("You're connecting to a host Drag hasn't seen before. Verify its "
              'fingerprint out-of-band before trusting it — an unexpected key can '
              'mean a man-in-the-middle.',
              style: FsType.sans(size: 12, color: FsColors.text2, height: 1.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FsColors.bgScaffold,
              borderRadius: BorderRadius.circular(FsColors.rField),
              border: Border.all(color: FsColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${info.host}:${info.port}  ·  ${info.type}',
                  style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.text1)),
              const SizedBox(height: 4),
              SelectableText(info.fingerprint, style: FsType.mono(size: 11, color: FsColors.text2)),
            ]),
          ),
        ]),
        actions: [
          FsButton('Cancel', onTap: () => Navigator.pop(ctx, HostKeyDecision.cancel)),
          FsButton('Trust once', onTap: () => Navigator.pop(ctx, HostKeyDecision.trustOnce)),
          FsButton('Trust & remember',
              kind: FsButtonKind.primary,
              onTap: () => Navigator.pop(ctx, HostKeyDecision.trustAndRemember)),
        ],
      ),
    );
    return decision ?? HostKeyDecision.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final screen = ref.watch(navProvider);
    final nav = ref.read(navProvider.notifier);

    final (title, actions) = switch (screen) {
      AppScreen.browser => (
          _browserTitle(),
          [TbButton('⊕ New Session', onTap: () => nav.go(AppScreen.connections))],
        ),
      AppScreen.connections => ('Connection Manager', <Widget>[]),
      // Queue & Dashboard render their own bulk actions in the screen header,
      // so the title bar stays clean (no duplicate buttons).
      AppScreen.queue => ('Transfer Queue', <Widget>[]),
      AppScreen.dashboard => ('History Dashboard', <Widget>[]),
      AppScreen.settings => ('Preferences', <Widget>[]),
      AppScreen.about => ('About Drag', <Widget>[]),
    };

    final body = switch (screen) {
      AppScreen.browser => const BrowserScreen(),
      AppScreen.connections => const ConnectionManagerScreen(),
      AppScreen.queue => const TransferQueueScreen(),
      AppScreen.dashboard => const DashboardScreen(),
      AppScreen.settings => const SettingsScreen(),
      AppScreen.about => const AboutScreen(),
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

  String _browserTitle() {
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
