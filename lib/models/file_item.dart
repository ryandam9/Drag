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

  String get icon => glyph ?? (isDir ? '📁' : glyphForName(name));

  String get sizeLabel {
    if (isDir || sizeBytes == null) return '—';
    return formatBytes(sizeBytes!);
  }
}

/// Lower-cased extension of [name] without the dot (empty if none).
String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// A type-specific emoji glyph for a file [name], chosen by extension. Falls
/// back to a generic document glyph. (Directories are handled by [FileItem.icon].)
String glyphForName(String name) {
  switch (_extOf(name)) {
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'svg':
    case 'ico':
    case 'tiff':
      return '🖼';
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'avi':
    case 'webm':
    case 'm4v':
      return '🎬';
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'm4a':
    case 'aac':
      return '🎵';
    case 'zip':
    case 'tar':
    case 'gz':
    case 'tgz':
    case 'rar':
    case '7z':
    case 'bz2':
    case 'xz':
    case 'zst':
      return '🗜';
    case 'pdf':
      return '📕';
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'tsv':
      return '📊';
    case 'dart':
    case 'js':
    case 'ts':
    case 'jsx':
    case 'tsx':
    case 'py':
    case 'go':
    case 'rs':
    case 'java':
    case 'kt':
    case 'c':
    case 'h':
    case 'cpp':
    case 'hpp':
    case 'cc':
    case 'rb':
    case 'swift':
    case 'php':
    case 'sh':
    case 'bash':
    case 'sql':
      return '📜';
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'toml':
    case 'ini':
    case 'conf':
    case 'cfg':
    case 'env':
      return '🧾';
    default:
      return '📄';
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
  final fixed = i == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(decimals);
  return '$fixed ${units[i]}';
}
