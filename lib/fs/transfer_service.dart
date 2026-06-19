import '../models/file_item.dart';
import '../models/transfer.dart';
import 'storage_backend.dart';

/// Performs a real transfer by streaming bytes from a source backend into a
/// destination backend, reporting live progress/speed onto the [Transfer].
///
/// Because everything goes through a byte stream, the same routine covers:
///   • Local → S3   (upload)
///   • S3 → Local   (download)
///   • S3 → S3       (copy across accounts / regions — streamed, no server-side
///                    copy, so differing credentials are fine)
class TransferService {
  /// Runs [t] from [srcPath] on [src] to [dstPath] on [dst].
  ///
  /// [onStatus] fires on structural changes (active / done / error) that the
  /// rest of the app cares about (queue counts, toasts, history). [onProgress]
  /// fires on high-frequency progress/speed/eta updates and should only repaint
  /// the small progress widgets — keep it off the global notifier.
  Future<void> run({
    required Transfer t,
    required StorageBackend src,
    required String srcPath,
    required StorageBackend dst,
    required String dstPath,
    required void Function() onStatus,
    void Function()? onProgress,
  }) async {
    t.status = TransferStatus.active;
    t.startedAt = DateTime.now();
    onStatus();

    final stopwatch = Stopwatch()..start();
    var sent = 0;
    var lastBytes = 0;
    var lastMs = 0;

    void report(int total) {
      sent = total;
      final size = t.sizeBytes;
      if (size > 0) t.progress = (sent / size).clamp(0.0, 1.0);

      final ms = stopwatch.elapsedMilliseconds;
      if (ms - lastMs >= 400) {
        final bytesPerSec = (sent - lastBytes) * 1000 / (ms - lastMs);
        t.speed = '${formatBytes(bytesPerSec.round())}/s';
        if (bytesPerSec > 0 && size > sent) {
          final secs = ((size - sent) / bytesPerSec).round();
          t.eta = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
        }
        lastBytes = sent;
        lastMs = ms;
        onProgress?.call();
      }
    }

    try {
      final handle = await src.openRead(srcPath);
      // Prefer the real content length; fall back to whatever the queue knew.
      final total = handle.length > 0 ? handle.length : t.sizeBytes;

      final counting = handle.stream.map((chunk) {
        report(sent + chunk.length);
        return chunk;
      });

      await dst.write(dstPath, counting, total, onProgress: (s) => report(s));

      t.progress = 1.0;
      t.status = TransferStatus.done;
      t.eta = 'Done';
      if (t.speed == '—') t.speed = '${formatBytes(total)}/s';
    } catch (e) {
      t.status = TransferStatus.error;
      t.errorMessage = _friendly(e);
    } finally {
      t.finishedAt = DateTime.now();
      onStatus();
    }
  }

  String _friendly(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    return msg.length > 90 ? '${msg.substring(0, 90)}…' : msg;
  }
}
