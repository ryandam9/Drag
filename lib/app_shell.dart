import 'package:flutter/material.dart';

import 'models/connection.dart';
import 'screens/browser_screen.dart';
import 'screens/connection_manager_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfer_queue_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/nav_rail.dart';
import 'widgets/toast_overlay.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    final (title, actions) = switch (app.screen) {
      AppScreen.browser => (
          'FileSync — ${app.selectedConnection.name} · ${app.selectedConnection.protocol.label}',
          [TbButton('⊕ New Session', onTap: () => app.go(AppScreen.connections))],
        ),
      AppScreen.connections => ('Connection Manager', <Widget>[]),
      AppScreen.queue => (
          'Transfer Queue',
          [
            TbButton('⏸ Pause all', onTap: app.pauseAll),
            TbButton('▶ Resume all', onTap: app.resumeAll),
            TbButton('⊗ Clear done', onTap: app.clearDone),
          ],
        ),
      AppScreen.settings => ('Preferences', <Widget>[]),
    };

    final body = switch (app.screen) {
      AppScreen.browser => const BrowserScreen(),
      AppScreen.connections => const ConnectionManagerScreen(),
      AppScreen.queue => const TransferQueueScreen(),
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
                  color: FsColors.bgSurface,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: KeyedSubtree(key: ValueKey(app.screen), child: body),
                  ),
                ),
              ),
            ]),
          ),
        ]),
        const ToastOverlay(),
      ]),
    );
  }
}
