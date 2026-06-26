import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'toast.dart';

export 'toast.dart' show ToastMessage, ToastKind, ToastKindStyle, ToastSink;

/// How long each notification stays on screen before auto-dismissing. Shared
/// with the overlay so its countdown bar matches the actual lifetime.
const kToastDuration = Duration(seconds: 10);

/// The stack of transient notifications shown top-right. Each toast
/// auto-dismisses after [kToastDuration].
class ToastsNotifier extends Notifier<List<ToastMessage>> {
  int _seq = 0;
  bool _disposed = false;

  @override
  List<ToastMessage> build() {
    ref.onDispose(() => _disposed = true);
    return const [];
  }

  void push(String title, String sub, ToastKind kind, {String? detail}) {
    final msg = ToastMessage(_seq++, title, sub, kind, detail: detail);
    state = [...state, msg];
    Future.delayed(kToastDuration, () {
      if (_disposed) return;
      state = state.where((m) => m.id != msg.id).toList();
    });
  }

  /// Dismiss a toast immediately (the in-card close button).
  void dismiss(int id) {
    if (_disposed) return;
    state = state.where((m) => m.id != id).toList();
  }
}

final toastsProvider =
    NotifierProvider<ToastsNotifier, List<ToastMessage>>(ToastsNotifier.new);
