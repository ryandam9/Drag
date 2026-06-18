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
  });
}
