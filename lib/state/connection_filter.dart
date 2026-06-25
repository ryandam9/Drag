import '../models/connection.dart';

/// The label for a group of connections shown together in the sidebar.
typedef ConnectionGroup = ({String label, List<Connection> items});

/// Sentinel group label for connections without a [Connection.tag].
const kUngroupedLabel = 'Ungrouped';

/// True when [c] matches the free-text [query] (case-insensitive substring over
/// name, tag, host, bucket, region and username). A blank query matches all.
bool connectionMatches(Connection c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  for (final field in [c.name, c.tag, c.host, c.bucket, c.region, c.username]) {
    if (field.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// Filters [all] by [query], preserving order.
List<Connection> filterConnections(List<Connection> all, String query) =>
    [for (final c in all) if (connectionMatches(c, query)) c];

/// Groups [conns] by their [Connection.tag], preserving each connection's
/// original order within a group. Tagged groups come first in case-insensitive
/// alphabetical order; untagged connections fall under [kUngroupedLabel], which
/// is always listed last. Empty groups are omitted.
List<ConnectionGroup> groupConnections(List<Connection> conns) {
  final byTag = <String, List<Connection>>{};
  for (final c in conns) {
    byTag.putIfAbsent(c.tag.trim(), () => []).add(c);
  }
  final untagged = byTag.remove('');
  final labels = byTag.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final label in labels) (label: label, items: byTag[label]!),
    if (untagged != null) (label: kUngroupedLabel, items: untagged),
  ];
}
