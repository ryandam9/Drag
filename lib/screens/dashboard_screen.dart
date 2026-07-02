import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_csv.dart';
import '../data/history_db.dart';
import '../models/file_item.dart';
import '../state/app.dart';
import '../state/history_filter.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _search = TextEditingController();
  String _query = '';
  HistoryStatusFilter _status = HistoryStatusFilter.all;
  HistoryDirectionFilter _direction = HistoryDirectionFilter.all;
  HistoryDateFilter _date = HistoryDateFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);
    final s = history.stats;
    final since = historySince(_date, DateTime.now());
    final filtered = filterHistory(
      history.records,
      query: _query,
      status: _status,
      direction: _direction,
      since: since,
    );
    final breakdown = breakdownByEndpoint(filtered);
    final filtering =
        _query.trim().isNotEmpty ||
        _status != HistoryStatusFilter.all ||
        _direction != HistoryDirectionFilter.all ||
        _date != HistoryDateFilter.all;
    return Container(
      color: FsColors.bgScaffold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfer History',
                        style: FsType.sans(
                          size: 22,
                          weight: FontWeight.w700,
                          color: FsColors.text1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        history.hasDb
                            ? 'SQLite · ${s.total} record${s.total == 1 ? '' : 's'}'
                            : 'SQLite unavailable',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FsType.sans(
                          size: 13,
                          color: history.hasDb
                              ? FsColors.text2
                              : FsColors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FsButton('⬇ Export CSV', onTap: () => _exportCsv(ref)),
                const SizedBox(width: 10),
                FsButton('↺ Refresh', onTap: notifier.refresh),
                const SizedBox(width: 10),
                FsButton(
                  '⊗ Clear history',
                  kind: FsButtonKind.danger,
                  onTap: notifier.clear,
                ),
              ],
            ),
          ),

          // ── Stat cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                _StatCard(
                  'Total transfers',
                  '${s.total}',
                  Icons.swap_vert_rounded,
                  FsColors.accent,
                ),
                _StatCard(
                  'Succeeded',
                  '${s.succeeded}',
                  Icons.check_circle_outline,
                  FsColors.green,
                ),
                _StatCard(
                  'Failed',
                  '${s.failed}',
                  Icons.error_outline,
                  FsColors.red,
                ),
                _StatCard(
                  'Data transferred',
                  formatBytes(s.totalBytes),
                  Icons.data_usage,
                  FsColors.purple,
                ),
                _StatCard(
                  'Avg speed',
                  s.avgBytesPerSecond > 0
                      ? '${formatBytes(s.avgBytesPerSecond.round())}/s'
                      : '—',
                  Icons.speed,
                  FsColors.amber,
                  last: true,
                ),
              ],
            ),
          ),

          // ── Throughput-over-time sparkline ──
          if (filtered.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: _throughputChart(filtered),
            ),

          // ── Per-endpoint breakdown (only when there's more than one) ──
          if (breakdown.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: _breakdownBar(breakdown),
            ),

          // ── Filter / search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _filterBar(filtered.length, filtering),
          ),

          // ── History table ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: FsColors.bgSurface,
                  borderRadius: BorderRadius.circular(FsColors.rCard),
                  border: Border.all(color: FsColors.border),
                  boxShadow: FsColors.cardShadow,
                ),
                clipBehavior: Clip.antiAlias,
                child: _HistoryTable(records: filtered, filtering: filtering),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(int shown, bool filtering) {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: FsTextField(
            controller: _search,
            hint: 'Search name, path or endpoint…',
            height: 34,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 10),
        _dropdown<HistoryStatusFilter>(_status, const {
          HistoryStatusFilter.all: 'All status',
          HistoryStatusFilter.succeeded: 'Succeeded',
          HistoryStatusFilter.failed: 'Failed',
        }, (v) => setState(() => _status = v)),
        const SizedBox(width: 8),
        _dropdown<HistoryDirectionFilter>(_direction, const {
          HistoryDirectionFilter.all: 'All directions',
          HistoryDirectionFilter.upload: 'Uploads',
          HistoryDirectionFilter.download: 'Downloads',
        }, (v) => setState(() => _direction = v)),
        const SizedBox(width: 8),
        _dropdown<HistoryDateFilter>(_date, const {
          HistoryDateFilter.all: 'All time',
          HistoryDateFilter.last24h: 'Last 24h',
          HistoryDateFilter.last7d: 'Last 7 days',
          HistoryDateFilter.last30d: 'Last 30 days',
        }, (v) => setState(() => _date = v)),
        const Spacer(),
        if (filtering)
          Text(
            '$shown match${shown == 1 ? '' : 'es'}',
            style: FsType.sans(size: 11, color: FsColors.text3),
          ),
      ],
    );
  }

  Widget _dropdown<T>(
    T value,
    Map<T, String> options,
    ValueChanged<T> onChanged,
  ) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rField),
        border: Border.all(color: FsColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: FsColors.bgPanel,
          icon: Icon(Icons.expand_more, size: 16, color: FsColors.text2),
          style: FsType.sans(size: 12, color: FsColors.text1),
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _throughputChart(List<TransferRecord> shown) {
    // Span the window from the oldest to the newest shown transfer. A flat
    // (zero-width) span — e.g. everything finished at once — has nothing
    // meaningful to plot.
    var lo = shown.first.finishedAt;
    var hi = shown.first.finishedAt;
    for (final r in shown) {
      if (r.finishedAt.isBefore(lo)) lo = r.finishedAt;
      if (r.finishedAt.isAfter(hi)) hi = r.finishedAt;
    }
    if (!hi.isAfter(lo)) return const SizedBox.shrink();
    final series = bytesOverTime(
      shown,
      start: lo,
      end: hi.add(const Duration(milliseconds: 1)),
      buckets: 32,
    );
    final peak = series.fold<int>(0, (m, v) => v > m ? v : m);
    if (peak == 0) return const SizedBox.shrink();
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'THROUGHPUT',
                style: FsType.sans(
                  size: 9,
                  weight: FontWeight.w700,
                  color: FsColors.text3,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'peak ${formatBytes(peak)}',
                style: FsType.sans(
                  size: 11,
                  color: FsColors.text2,
                  tabular: true,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: CustomPaint(
              painter: _SparklinePainter(series, FsColors.accent),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownBar(List<EndpointStat> stats) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = stats[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FsColors.bgSurface,
              borderRadius: BorderRadius.circular(FsColors.rPill),
              border: Border.all(color: FsColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.dns_outlined, size: 13, color: FsColors.accentHi),
                const SizedBox(width: 6),
                Text(
                  e.endpoint,
                  style: FsType.sans(
                    size: 11,
                    weight: FontWeight.w600,
                    color: FsColors.text1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.count} · ${formatBytes(e.totalBytes)}',
                  style: FsType.sans(
                    size: 11,
                    color: FsColors.text3,
                    tabular: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Export the current history to CSV. Lets the user pick the destination via a
/// native save dialog; if the picker is unavailable (headless) it writes to the
/// home directory, and if even that fails it falls back to the clipboard.
Future<void> _exportCsv(WidgetRef ref) async {
  final history = ref.read(historyProvider);
  final toasts = ref.read(toastsProvider.notifier);
  if (history.records.isEmpty) {
    toasts.push('Nothing to export', 'No transfer history yet', ToastKind.info);
    return;
  }
  final csv = historyToCsv(history.records);
  final count = history.records.length;
  final rowsLabel = '$count row${count == 1 ? '' : 's'}';
  final suggested = csvFileName(DateTime.now());

  // 1) Native save dialog (user chooses the location).
  try {
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return; // user cancelled — do nothing
    await File(location.path).writeAsString(csv);
    toasts.push(
      'History exported',
      '$rowsLabel → ${location.path}',
      ToastKind.success,
    );
    return;
  } catch (_) {
    // Picker unavailable in this environment — fall through.
  }

  // 2) Home directory, then 3) the clipboard.
  try {
    final env = Platform.environment;
    final dir = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    final sep = dir.endsWith('/') || dir.endsWith(r'\') ? '' : '/';
    final path = '$dir$sep$suggested';
    await File(path).writeAsString(csv);
    toasts.push('History exported', '$rowsLabel → $path', ToastKind.success);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: csv));
    toasts.push('Copied to clipboard', '$rowsLabel of CSV', ToastKind.info);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool last;
  const _StatCard(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: last ? 0 : 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: FsColors.bgSurface,
          borderRadius: BorderRadius.circular(FsColors.rCard),
          border: Border.all(color: FsColors.border),
          boxShadow: FsColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color.lerp(color, FsColors.bgSurface, 0.82),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: FsType.sans(
                  size: 22,
                  weight: FontWeight.w800,
                  color: FsColors.text1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FsType.sans(size: 12, color: FsColors.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  final List<TransferRecord> records;
  final bool filtering;
  const _HistoryTable({required this.records, this.filtering = false});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      final noMatches = filtering;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Color.lerp(FsColors.accent, FsColors.bgSurface, 0.82),
                borderRadius: BorderRadius.circular(FsColors.rField),
              ),
              child: Icon(
                noMatches ? Icons.search_off : Icons.history,
                size: 28,
                color: FsColors.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              noMatches ? 'No matching transfers' : 'No transfers yet',
              style: FsType.sans(
                size: 16,
                weight: FontWeight.w700,
                color: FsColors.text1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              noMatches
                  ? 'Try adjusting the search or filters.'
                  : 'Completed transfers will appear here.',
              style: FsType.sans(size: 13, color: FsColors.text2),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _head(),
        Expanded(
          child: ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, i) => _row(records[i]),
          ),
        ),
      ],
    );
  }

  Widget _head() {
    Widget cell(String t, int flex, {TextAlign align = TextAlign.left}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              t,
              textAlign: align,
              style: FsType.sans(
                size: 11,
                weight: FontWeight.w700,
                color: FsColors.text2,
                letterSpacing: 0.6,
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(
        children: [
          cell('', 3),
          cell('FILE', 26),
          cell('ROUTE', 30),
          cell('SIZE', 11, align: TextAlign.right),
          cell('TIME', 10, align: TextAlign.right),
          cell('SPEED', 12, align: TextAlign.right),
          cell('WHEN', 16),
          cell('STATUS', 12),
        ],
      ),
    );
  }

  Widget _row(TransferRecord r) {
    return Hoverable(
      builder: (hover) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: hover ? FsColors.bgHover : Colors.transparent,
            border: Border(bottom: BorderSide(color: FsColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Icon(
                  r.isUpload ? Icons.north_rounded : Icons.south_rounded,
                  size: 13,
                  color: r.isUpload ? FsColors.accentHi : FsColors.purple,
                ),
              ),
              Expanded(
                flex: 26,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SelectableText(
                    r.name,
                    style: FsType.sans(
                      size: 13,
                      weight: FontWeight.w500,
                      color: FsColors.text1,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 30,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SelectableText(
                    '${r.sourcePath} → ${r.destPath}',
                    style: FsType.sans(size: 12, color: FsColors.text2),
                  ),
                ),
              ),
              _mono(formatBytes(r.sizeBytes), 11, TextAlign.right),
              _mono(formatDurationMs(r.durationMs), 10, TextAlign.right),
              _mono(
                r.bytesPerSecond > 0
                    ? '${formatBytes(r.bytesPerSecond.round())}/s'
                    : '—',
                12,
                TextAlign.right,
              ),
              Expanded(
                flex: 16,
                child: Text(
                  _relative(r.finishedAt),
                  style: FsType.sans(
                    size: 11,
                    color: FsColors.text2,
                    tabular: true,
                  ),
                ),
              ),
              Expanded(
                flex: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: r.success
                      ? StatusBadge(
                          '✓ Done',
                          bg: FsColors.badgeDoneBg,
                          fg: FsColors.badgeDoneFg,
                        )
                      : StatusBadge(
                          '✕ Failed',
                          bg: FsColors.badgeErrorBg,
                          fg: FsColors.badgeErrorFg,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mono(String t, int flex, TextAlign align) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Text(
        t,
        textAlign: align,
        style: FsType.sans(size: 11, color: FsColors.text2, tabular: true),
      ),
    ),
  );

  String _relative(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Paints a filled sparkline of the [values] series, scaled to the tallest
/// bucket. Degenerate input (empty or all-zero) paints nothing.
class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color color;
  const _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final peak = values.fold<int>(0, (m, v) => v > m ? v : m);
    if (peak == 0) return;
    final dx = size.width / (values.length - 1);
    Offset at(int i) =>
        Offset(i * dx, size.height - (values[i] / peak) * size.height);

    final line = Path()..moveTo(0, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// Formats a raw millisecond duration for the history table.
String formatDurationMs(int ms) {
  if (ms <= 0) return '—';
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}
