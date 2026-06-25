import 'dart:convert';
import 'dart:typed_data';

import '../models/file_item.dart';
import 'storage_backend.dart';

/// What a [FilePreview] holds.
enum PreviewKind { text, image, tooLarge, binary, empty, error }

/// The result of peeking at a file: a bounded text excerpt, decoded image
/// bytes, or a reason we can't preview it. Produced by [loadPreview].
class FilePreview {
  final PreviewKind kind;

  /// Decoded text (for [PreviewKind.text]); a bounded excerpt of the file.
  final String? text;

  /// Raw image bytes (for [PreviewKind.image]).
  final Uint8List? bytes;

  /// Human-readable note for non-previewable kinds (too large / binary / error).
  final String? message;

  /// True when the file is larger than what we read, so [text] is only a head.
  final bool truncated;

  const FilePreview._(this.kind, {this.text, this.bytes, this.message, this.truncated = false});

  const FilePreview.text(String text, {bool truncated = false})
      : this._(PreviewKind.text, text: text, truncated: truncated);
  const FilePreview.image(Uint8List bytes) : this._(PreviewKind.image, bytes: bytes);
  const FilePreview.tooLarge(String message) : this._(PreviewKind.tooLarge, message: message);
  const FilePreview.binary(String message) : this._(PreviewKind.binary, message: message);
  const FilePreview.empty() : this._(PreviewKind.empty);
  const FilePreview.error(String message) : this._(PreviewKind.error, message: message);
}

/// File extensions we render as text (source, config, logs, data).
const _textExts = {
  'txt', 'md', 'markdown', 'log', 'json', 'yaml', 'yml', 'toml', 'ini', 'conf',
  'cfg', 'csv', 'tsv', 'xml', 'html', 'htm', 'css', 'js', 'ts', 'jsx', 'tsx',
  'dart', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'c', 'h', 'cpp', 'hpp', 'cc',
  'sh', 'bash', 'zsh', 'sql', 'env', 'properties', 'gradle', 'gitignore',
  'dockerfile', 'makefile', 'rst', 'tex', 'srt', 'vtt',
};

/// File extensions we render as an inline image.
const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'ico'};

/// Lower-cased extension of [name] without the dot (empty if none).
String _ext(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

bool isTextPreviewable(String name) => _textExts.contains(_ext(name));
bool isImagePreviewable(String name) => _imageExts.contains(_ext(name));

/// True when [name] is something [loadPreview] can show inline (text or image).
bool isPreviewable(String name) => isTextPreviewable(name) || isImagePreviewable(name);

/// Reads at most [max] bytes from [path] on [backend], stopping (and cancelling
/// the stream) as soon as the cap is reached — so a huge remote file never
/// streams in full just to be previewed.
Future<Uint8List> _readBounded(StorageBackend backend, String path, int max) async {
  final handle = await backend.openRead(path);
  final out = BytesBuilder(copy: false);
  await for (final chunk in handle.stream) {
    out.add(chunk);
    if (out.length >= max) break; // breaking the await-for cancels the subscription
  }
  final bytes = out.takeBytes();
  return bytes.length > max ? Uint8List.sublistView(bytes, 0, max) : bytes;
}

/// Peeks at [item] (at [path] on [backend]) and returns a bounded preview:
/// text for source/config files, an inline image for pictures, or a metadata
/// notice for binary / oversized files. Works for any backend (Local/S3/SFTP)
/// because it only uses [StorageBackend.openRead].
Future<FilePreview> loadPreview(
  StorageBackend backend,
  String path,
  FileItem item, {
  int maxTextBytes = 64 * 1024,
  int maxImageBytes = 8 * 1024 * 1024,
}) async {
  final name = item.name;
  final size = item.sizeBytes;
  try {
    if (isImagePreviewable(name)) {
      if (size != null && size > maxImageBytes) {
        return FilePreview.tooLarge('Image is ${formatBytes(size)} — too large to preview.');
      }
      // Read one byte past the cap so we can tell "exactly at cap" from "over".
      final bytes = await _readBounded(backend, path, maxImageBytes + 1);
      if (bytes.isEmpty) return const FilePreview.empty();
      if (bytes.length > maxImageBytes) {
        return FilePreview.tooLarge('Image exceeds ${formatBytes(maxImageBytes)} — too large to preview.');
      }
      return FilePreview.image(bytes);
    }

    if (isTextPreviewable(name)) {
      if (size == 0) return const FilePreview.empty();
      final bytes = await _readBounded(backend, path, maxTextBytes);
      if (bytes.isEmpty) return const FilePreview.empty();
      final text = utf8.decode(bytes, allowMalformed: true);
      final truncated = (size != null && size > maxTextBytes) || bytes.length >= maxTextBytes;
      return FilePreview.text(text, truncated: truncated);
    }

    return FilePreview.binary(
        'No inline preview for ${_ext(name).isEmpty ? 'this file' : '.${_ext(name)} files'}.');
  } catch (e) {
    return FilePreview.error(e.toString().replaceFirst('Exception: ', ''));
  }
}
