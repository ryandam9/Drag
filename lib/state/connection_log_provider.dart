import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'toast.dart';

/// One timestamped line in the Connection Manager's diagnostics log.
class ConnLogLine {
  final DateTime time;
  final String message;
  final ToastKind kind;
  const ConnLogLine(this.time, this.message, this.kind);
}

/// A persistent, timestamped log of connection attempts (Connect / Test),
/// shown in the Connection Manager so the messages don't vanish like toasts do.
class ConnectionLogNotifier extends Notifier<List<ConnLogLine>> {
  static const _cap = 300;

  @override
  List<ConnLogLine> build() => const [];

  void _add(String message, ToastKind kind) {
    final next = [...state, ConnLogLine(DateTime.now(), message, kind)];
    state = next.length > _cap ? next.sublist(next.length - _cap) : next;
  }

  void info(String message) => _add(message, ToastKind.info);
  void success(String message) => _add(message, ToastKind.success);
  void error(String message) => _add(message, ToastKind.error);
  void clear() => state = const [];
}

final connectionLogProvider =
    NotifierProvider<ConnectionLogNotifier, List<ConnLogLine>>(
      ConnectionLogNotifier.new,
    );
