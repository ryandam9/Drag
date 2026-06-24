import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The top-level screens reachable from the navigation rail.
enum AppScreen { browser, connections, queue, dashboard, settings }

/// Which screen is currently shown.
class NavNotifier extends Notifier<AppScreen> {
  @override
  AppScreen build() => AppScreen.browser;

  void go(AppScreen screen) => state = screen;
}

final navProvider = NotifierProvider<NavNotifier, AppScreen>(NavNotifier.new);
