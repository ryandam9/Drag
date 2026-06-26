import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'toast.dart';

export 'toast.dart' show ToastMessage, ToastKind, ToastKindStyle, ToastSink;

/// The stack of transient notifications shown bottom-right. Each toast
/// auto-dismisses after a few seconds.
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
    Future.delayed(const Duration(seconds: 5), () {
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
