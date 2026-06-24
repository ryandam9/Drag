import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_db.dart';
import '../models/file_item.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final notifier = ref.read(historyProvider.notifier);
    final s = history.stats;
    return Container(
      color: FsColors.bgScaffold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Transfer History',
                      style: FsType.sans(size: 22, weight: FontWeight.w700, color: FsColors.text1)),
                  const SizedBox(height: 4),
                  Text(
                      history.hasDb
                          ? 'SQLite · ${s.total} record${s.total == 1 ? '' : 's'}'
                          : 'SQLite unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FsType.sans(size: 13, color: history.hasDb ? FsColors.text2 : FsColors.amber)),
                ]),
              ),
              const SizedBox(width: 12),
              FsButton('↺ Refresh', onTap: notifier.refresh),
              const SizedBox(width: 10),
              FsButton('⊗ Clear history', kind: FsButtonKind.danger, onTap: notifier.clear),
            ]),
          ),

          // ── Stat cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(children: [
              _StatCard('Total transfers', '${s.total}', Icons.swap_vert_rounded, FsColors.accent),
              _StatCard('Succeeded', '${s.succeeded}', Icons.check_circle_outline, FsColors.green),
              _StatCard('Failed', '${s.failed}', Icons.error_outline, FsColors.red),
              _StatCard('Data transferred', formatBytes(s.totalBytes), Icons.data_usage, FsColors.purple),
              _StatCard('Avg speed',
                  s.avgBytesPerSecond > 0 ? '${formatBytes(s.avgBytesPerSecond.round())}/s' : '—',
                  Icons.speed, FsColors.amber, last: true),
            ]),
          ),

          // ── History table ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: FsColors.bgSurface,
                  borderRadius: BorderRadius.circular(FsColors.rCard),
                  border: Border.all(color: FsColors.border),
                  boxShadow: FsColors.cardShadow,
                ),
                clipBehavior: Clip.antiAlias,
                child: _HistoryTable(records: history.records),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool last;
  const _StatCard(this.label, this.value, this.icon, this.color, {this.last = false});

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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            child: Text(value,
                maxLines: 1, style: FsType.sans(size: 22, weight: FontWeight.w800, color: FsColors.text1)),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FsType.sans(size: 12, color: FsColors.text2)),
        ]),
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  final List<TransferRecord> records;
  const _HistoryTable({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Color.lerp(FsColors.accent, FsColors.bgSurface, 0.82),
              borderRadius: BorderRadius.circular(FsColors.rField),
            ),
            child: Icon(Icons.history, size: 28, color: FsColors.accent),
          ),
          const SizedBox(height: 14),
          Text('No transfers yet', style: FsType.sans(size: 16, weight: FontWeight.w700, color: FsColors.text1)),
          const SizedBox(height: 6),
          Text('Completed transfers will appear here.',
              style: FsType.sans(size: 13, color: FsColors.text2)),
        ]),
      );
    }

    return Column(children: [
      _head(),
      Expanded(
        child: ListView.builder(
          itemCount: records.length,
          itemBuilder: (context, i) => _row(records[i]),
        ),
      ),
    ]);
  }

  Widget _head() {
    Widget cell(String t, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(t,
                textAlign: align,
                style: FsType.sans(size: 11, weight: FontWeight.w700, color: FsColors.text2, letterSpacing: 0.6)),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        cell('', 3),
        cell('FILE', 26),
        cell('ROUTE', 30),
        cell('SIZE', 11, align: TextAlign.right),
        cell('TIME', 10, align: TextAlign.right),
        cell('SPEED', 12, align: TextAlign.right),
        cell('WHEN', 16),
        cell('STATUS', 12),
      ]),
    );
  }

  Widget _row(TransferRecord r) {
    return Hoverable(builder: (hover) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: hover ? FsColors.bgHover : Colors.transparent,
          border: Border(bottom: BorderSide(color: FsColors.border)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            flex: 3,
            child: Icon(r.isUpload ? Icons.north_rounded : Icons.south_rounded,
                size: 13, color: r.isUpload ? FsColors.accentHi : FsColors.purple),
          ),
          Expanded(
            flex: 26,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SelectableText(r.name,
                  style: FsType.sans(size: 13, weight: FontWeight.w500, color: FsColors.text1)),
            ),
          ),
          Expanded(
            flex: 30,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SelectableText('${r.sourcePath} → ${r.destPath}',
                  style: FsType.sans(size: 12, color: FsColors.text2)),
            ),
          ),
          _mono(formatBytes(r.sizeBytes), 11, TextAlign.right),
          _mono(formatDurationMs(r.durationMs), 10, TextAlign.right),
          _mono(r.bytesPerSecond > 0 ? '${formatBytes(r.bytesPerSecond.round())}/s' : '—', 12, TextAlign.right),
          Expanded(flex: 16, child: Text(_relative(r.finishedAt), style: FsType.sans(size: 11, color: FsColors.text2, tabular: true))),
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: r.success
                  ? StatusBadge('✓ Done', bg: FsColors.badgeDoneBg, fg: FsColors.badgeDoneFg)
                  : StatusBadge('✕ Failed', bg: FsColors.badgeErrorBg, fg: FsColors.badgeErrorFg),
            ),
          ),
        ]),
      );
    });
  }

  Widget _mono(String t, int flex, TextAlign align) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(t, textAlign: align, style: FsType.sans(size: 11, color: FsColors.text2, tabular: true)),
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

/// Formats a raw millisecond duration for the history table.
String formatDurationMs(int ms) {
  if (ms <= 0) return '—';
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}
