import '../models/connection.dart';
import 'pane_controller.dart';

/// One open workspace tab: a Local ⇄ remote dual-pane view with its own
/// navigation/listing state, so multiple servers stay connected at once and
/// the user can switch between them without losing place.
class Session {
  final int id;
  final PaneController left;
  final PaneController right;

  Session({required this.id, required this.left, required this.right});

  /// The remote endpoint this tab represents (falls back to a local pane).
  Connection? get connection => right.connection ?? left.connection;

  /// Tab label — the remote server name, or "Local" for a local-only tab.
  String get title => connection?.name ?? 'Local';

  /// Local endpoints are always reachable; remotes follow their online flag.
  bool get online => connection?.online ?? true;
}
