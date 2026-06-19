import 'package:flutter/foundation.dart';

enum TransferStatus { active, queued, paused, error, done }

enum TransferDirection { upload, download }

class Transfer {
  final String name;
  final String route; // e.g. "Local → sftp://prod-server-01/backups/"
  final TransferDirection direction;
  double progress; // 0..1
  final int sizeBytes;
  String speed; // pre-formatted, "1.4 MB/s" or "—"
  String eta; // "0:41" or "—" or "Done"
  final String session;
  TransferStatus status;
  String? errorMessage;

  /// Real (S3 / local) transfers are driven by [TransferService]; simulated
  /// ones (seed data, SFTP demo) are advanced by the AppState ticker.
  final bool live;

  /// Full source / destination paths (for the completion notice and history).
  final String sourcePath;
  final String destPath;

  /// Wall-clock timing, set by [TransferService].
  DateTime? startedAt;
  DateTime? finishedAt;

  /// High-frequency "live" updates (progress / speed / eta) ping this notifier
  /// instead of the global [AppState] one, so only the small progress widgets
  /// rebuild — not the file tables. Status transitions (queued → active → done)
  /// still go through the global notifier. See [touchLive].
  final ValueNotifier<int> liveTick = ValueNotifier<int>(0);

  /// Signal that progress/speed/eta changed (rebuilds progress widgets only).
  void touchLive() => liveTick.value++;

  void dispose() => liveTick.dispose();

  Transfer({
    required this.name,
    required this.route,
    required this.direction,
    this.progress = 0,
    required this.sizeBytes,
    this.speed = '—',
    this.eta = '—',
    required this.session,
    this.status = TransferStatus.queued,
    this.errorMessage,
    this.live = false,
    this.sourcePath = '',
    this.destPath = '',
  });

  /// Elapsed transfer time, once finished.
  Duration? get elapsed =>
      (startedAt != null && finishedAt != null) ? finishedAt!.difference(startedAt!) : null;

  /// Human-friendly elapsed time, e.g. "0.8s", "1m 04s".
  String get elapsedLabel => formatDuration(elapsed);
}

/// Formats a [Duration] like "0.8s" / "12.3s" / "2m 05s".
String formatDuration(Duration? d) {
  if (d == null) return '—';
  final ms = d.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

