import 'package:flutter/material.dart';

import '../theme.dart';

class ToastMessage {
  final String title;
  final String subtitle;
  final String? detail;
  final ToastKind kind;
  final int id;
  ToastMessage(this.id, this.title, this.subtitle, this.kind, {this.detail});
}

enum ToastKind { success, error, info }

extension ToastKindStyle on ToastKind {
  String get icon => switch (this) {
        ToastKind.success => '✅',
        ToastKind.error => '❌',
        ToastKind.info => 'ℹ️',
      };

  Color get color => switch (this) {
        ToastKind.success => FsColors.green,
        ToastKind.error => FsColors.red,
        ToastKind.info => FsColors.accent,
      };

  Color get fg => switch (this) {
        ToastKind.success => FsColors.badgeDoneFg,
        ToastKind.error => FsColors.badgeErrorFg,
        ToastKind.info => FsColors.accentHi,
      };
}

/// Signature for emitting a toast from a controller back up to the coordinator.
typedef ToastSink = void Function(String title, String sub, ToastKind kind, {String? detail});
