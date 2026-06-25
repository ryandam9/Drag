import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import '../models/transfer.dart';
import 'rate_limiter.dart';
import 'storage_backend.dart';

/// A cooperative cancellation handle for an in-flight transfer. Calling [abort]
/// makes the streaming loop stop at the next chunk; the partial destination is
/// then removed. Used by pause and cancel in the queue.
class TransferControl {
  bool _aborted = false;
  void abort() => _aborted = true;
  bool get isAborted => _aborted;
}

/// Thrown internally when a transfer is aborted via its [TransferControl].
class _Aborted implements Exception {
  const _Aborted();
}

/// Performs a real transfer by streaming bytes from a source backend into a
/// destination backend, reporting live progress/speed onto the [Transfer].
///
/// Because everything goes through a byte stream, the same routine covers:
///   • Local → S3   (upload)
///   • S3 → Local   (download)
///   • S3 → S3       (copy across accounts / regions — streamed, no server-side
///                    copy, so differing credentials are fine)
class TransferService {
  TransferService({RateLimiter? limiter}) : limiter = limiter ?? RateLimiter();

  /// Shared across every [run] call on this service, so a bandwidth cap limits
  /// aggregate throughput across all concurrent transfers, not each one.
  final RateLimiter limiter;

  /// Runs [t] from [srcPath] on [src] to [dstPath] on [dst].
  ///
  /// [onStatus] fires on structural changes (active / done / error) that the
  /// rest of the app cares about (queue counts, toasts, history). [onProgress]
  /// fires on high-frequency progress/speed/eta updates and should only repaint
  /// the small progress widgets — keep it off the global notifier.
  /// [verify] controls the post-transfer integrity check:
  ///   • `'off'`      — trust the write.
  ///   • `'size'`     — confirm the destination's byte count matches the source.
  ///   • `'checksum'` — also compare MD5 digests (source hashed in-flight,
  ///                     destination re-read afterwards).
  /// A failed check throws, which marks the transfer as errored so the retry
  /// machinery can re-attempt it.
  Future<void> run({
    required Transfer t,
    required StorageBackend src,
    required String srcPath,
    required StorageBackend dst,
    required String dstPath,
    required void Function() onStatus,
    void Function()? onProgress,
    String verify = 'off',
    int? bytesPerSecond,
    TransferControl? control,
  }) async {
    // Apply the (shared) bandwidth cap; null/0 ⇒ unlimited.
    limiter.bytesPerSecond = bytesPerSecond;
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

      // For a checksum verify, hash the source bytes as they stream past so we
      // never read the (possibly remote) source twice.
      final wantChecksum = verify == 'checksum';
      Digest? srcDigest;
      ByteConversionSink? hasher;
      if (wantChecksum) {
        final out = ChunkedConversionSink<Digest>.withCallback(
            (digests) => srcDigest = digests.single);
        hasher = md5.startChunkedConversion(out);
      }

      // Throttle on the read side: each chunk waits for bandwidth tokens before
      // it flows downstream, so progress tracks the actual (capped) throughput.
      Stream<Uint8List> pump() async* {
        await for (final chunk in handle.stream) {
          if (control?.isAborted ?? false) throw const _Aborted();
          await limiter.acquire(chunk.length);
          if (control?.isAborted ?? false) throw const _Aborted();
          hasher?.add(chunk);
          report(sent + chunk.length);
          yield chunk;
        }
      }

      await dst.write(dstPath, pump(), total, onProgress: (s) => report(s));
      hasher?.close();

      if (verify != 'off') {
        await _verify(verify, dst, dstPath, total, srcDigest, onStatus, t);
      }

      t.progress = 1.0;
      t.status = TransferStatus.done;
      t.eta = 'Done';
      if (t.speed == '—') t.speed = '${formatBytes(total)}/s';
    } on _Aborted {
      // Stopped by the user (pause/cancel). Drop any partial bytes and settle
      // as paused — the queue decides whether to resume or discard it.
      await _safeDelete(dst, dstPath);
      t.status = TransferStatus.paused;
      t.speed = '—';
      t.eta = '—';
    } catch (e) {
      t.status = TransferStatus.error;
      t.errorMessage = _friendly(e);
    } finally {
      t.finishedAt = DateTime.now();
      onStatus();
    }
  }

  /// Confirms the destination received the file intact. Throws a descriptive
  /// [Exception] on any mismatch so [run]'s catch marks the transfer errored.
  Future<void> _verify(
    String level,
    StorageBackend dst,
    String dstPath,
    int total,
    Digest? srcDigest,
    void Function() onStatus,
    Transfer t,
  ) async {
    t.eta = 'Verifying…';
    onStatus();

    final destSize = await dst.sizeOf(dstPath);
    if (destSize != null && destSize != total) {
      throw Exception(
          'Verification failed: destination is ${formatBytes(destSize)}, '
          'expected ${formatBytes(total)}');
    }

    if (level == 'checksum' && srcDigest != null) {
      final handle = await dst.openRead(dstPath);
      final destDigest = await md5.bind(handle.stream).single;
      if (destDigest != srcDigest) {
        throw Exception('Checksum mismatch: the copy does not match the source');
      }
    }
  }

  /// Best-effort removal of a partial destination file after an abort.
  Future<void> _safeDelete(StorageBackend dst, String path) async {
    try {
      await dst.delete(path, isDir: false);
    } catch (_) {
      // Backend may not support delete, or there's nothing to remove.
    }
  }

  String _friendly(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    return msg.length > 90 ? '${msg.substring(0, 90)}…' : msg;
  }
}
