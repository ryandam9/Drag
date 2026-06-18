/// A single entry in a local or remote directory listing.
class FileItem {
  final String name;
  final bool isDir;

  /// Size in bytes. `null` for directories / the `..` entry.
  final int? sizeBytes;
  final String modified; // pre-formatted, matches the mockup
  final String perms;

  /// Optional emoji glyph override (e.g. archive 🗄).
  final String? glyph;

  const FileItem({
    required this.name,
    this.isDir = false,
    this.sizeBytes,
    this.modified = '',
    this.perms = '',
    this.glyph,
  });

  bool get isParent => name == '..';

  String get icon => glyph ?? (isDir ? '📁' : '📄');

  String get sizeLabel {
    if (isDir || sizeBytes == null) return '—';
    return formatBytes(sizeBytes!);
  }
}

/// Formats a timestamp the way the file tables display it: `2025-06-19  08:11`.
String formatModified(DateTime? dt) {
  if (dt == null) return '';
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
}

String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double value = bytes.toDouble();
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  final fixed = i == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return '$fixed ${units[i]}';
}
