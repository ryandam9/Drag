import 'package:flutter/material.dart';

import 'app_state.dart';

/// Per-controller [InheritedNotifier]s so a widget can subscribe to just the
/// slice of state it renders, instead of the whole [AppState] firehose. A
/// widget that depends on `SettingsScope.of(context)` rebuilds only when
/// settings change — not when a transfer ticks or a toast appears.

class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({super.key, required SettingsController controller, required super.child})
      : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(s != null, 'SettingsScope not found in widget tree');
    return s!.notifier!;
  }
}

class ConnectionsScope extends InheritedNotifier<ConnectionsController> {
  const ConnectionsScope({super.key, required ConnectionsController controller, required super.child})
      : super(notifier: controller);

  static ConnectionsController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ConnectionsScope>();
    assert(s != null, 'ConnectionsScope not found in widget tree');
    return s!.notifier!;
  }
}

class SessionsScope extends InheritedNotifier<SessionsController> {
  const SessionsScope({super.key, required SessionsController controller, required super.child})
      : super(notifier: controller);

  static SessionsController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<SessionsScope>();
    assert(s != null, 'SessionsScope not found in widget tree');
    return s!.notifier!;
  }
}

class TransfersScope extends InheritedNotifier<TransfersController> {
  const TransfersScope({super.key, required TransfersController controller, required super.child})
      : super(notifier: controller);

  static TransfersController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<TransfersScope>();
    assert(s != null, 'TransfersScope not found in widget tree');
    return s!.notifier!;
  }
}

/// Installs all four controller scopes (inside the global [AppScope]).
class AppScopes extends StatelessWidget {
  final AppState state;
  final Widget child;
  const AppScopes({super.key, required this.state, required this.child});

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: state.settingsController,
      child: ConnectionsScope(
        controller: state.connectionsController,
        child: SessionsScope(
          controller: state.sessionsController,
          child: TransfersScope(
            controller: state.transfersController,
            child: child,
          ),
        ),
      ),
    );
  }
}
