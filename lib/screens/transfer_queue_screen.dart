import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TransferQueueScreen extends ConsumerWidget {
  const TransferQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transfersProvider);
    final notifier = ref.read(transfersProvider.notifier);
    return Column(children: [
      _filterBar(state, notifier),
      Expanded(child: _table(state, notifier)),
      _statsBar(state, notifier),
    ]);
  }

  // ── Status filter chips + free text filter ──
  Widget _filterBar(TransfersState s, TransfersNotifier n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        StatusBadge('● Active  ${s.activeCount}', bg: FsColors.badgeLocalBg, fg: FsColors.accentHi),
        const SizedBox(width: 6),
        StatusBadge('⊡ Queued  ${s.queuedCount}', bg: FsColors.badgeQueuedBg, fg: FsColors.badgeQueuedFg),
        const SizedBox(width: 6),
        StatusBadge('✓ Done  ${s.doneCount}', bg: FsColors.badgeDoneBg, fg: FsColors.badgeDoneFg),
        const SizedBox(width: 6),
        StatusBadge('✕ Error  ${s.errorCount}', bg: FsColors.badgeErrorBg, fg: FsColors.badgeErrorFg),
        const Spacer(),
        TbButton('⏸ Pause all', onTap: n.pauseAll),
        TbButton('▶ Resume all', onTap: n.resumeAll),
        TbButton('⊗ Clear done', onTap: n.clearDone),
        const SizedBox(width: 8),
        const FsTextField(hint: 'Filter transfers…', mono: false, width: 180, height: 28),
      ]),
    );
  }

  // ── Transfer table ──
  Widget _table(TransfersState s, TransfersNotifier n) {
    if (s.transfers.isEmpty) {
      return Container(
        color: FsColors.bgSurface,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.swap_vert_rounded, size: 36, color: FsColors.text3),
          const SizedBox(height: 10),
          Text('No transfers yet',
              style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
          const SizedBox(height: 4),
          Text('Drag a file between panes in the Browser to start one.',
              style: FsType.sans(size: 12, color: FsColors.text2)),
        ]),
      );
    }
    return Container(
      color: FsColors.bgSurface,
      child: Column(children: [
        _head(),
        Expanded(
          child: ListView.builder(
            itemCount: s.transfers.length,
            itemBuilder: (context, i) => _row(n, s.transfers[i]),
          ),
        ),
      ]),
    );
  }

  Widget _head() {
    Widget cell(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t,
              style: FsType.sans(size: 10, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 0.7)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 24),
        cell('FILE', 32),
        cell('PROGRESS', 20),
        cell('SIZE', 10),
        cell('SPEED', 11),
        cell('ETA', 9),
        cell('SESSION', 14),
        cell('STATUS', 12),
      ]),
    );
  }

  ({Color bg, Color fg, String label}) _badge(TransferStatus s) => switch (s) {
        TransferStatus.active => (bg: FsColors.badgeLocalBg, fg: FsColors.accentHi, label: '● Active'),
        TransferStatus.done => (bg: FsColors.badgeDoneBg, fg: FsColors.badgeDoneFg, label: '✓ Done'),
        TransferStatus.queued => (bg: FsColors.badgeQueuedBg, fg: FsColors.badgeQueuedFg, label: '⊡ Queued'),
        TransferStatus.error => (bg: FsColors.badgeErrorBg, fg: FsColors.badgeErrorFg, label: '✕ Error'),
        TransferStatus.paused => (bg: FsColors.badgePausedBg, fg: FsColors.badgePausedFg, label: '⏸ Paused'),
      };

  Widget _row(TransfersNotifier app, Transfer t) {
    final dirGlyph = switch (t.status) {
      TransferStatus.done => '✓',
      TransferStatus.error => '!',
      TransferStatus.paused => '↕',
      _ => t.direction == TransferDirection.upload ? '↑' : '↓',
    };
    final dirColor = switch (t.status) {
      TransferStatus.done => FsColors.green,
      TransferStatus.error => FsColors.red,
      TransferStatus.paused => FsColors.amber,
      _ => FsColors.text3,
    };
    final badge = _badge(t.status);
    final fillColor = switch (t.status) {
      TransferStatus.done => FsColors.green,
      TransferStatus.paused => FsColors.amber,
      _ => FsColors.accent,
    };

    // Per-row live ticks repaint just this row, not the whole table.
    return ValueListenableBuilder<int>(
      valueListenable: t.liveTick,
      builder: (context, _, _) => Hoverable(builder: (hover) {
        return Opacity(
          opacity: t.status == TransferStatus.done ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: hover ? FsColors.bgHover : Colors.transparent,
            border: const Border(bottom: BorderSide(color: Color(0x662A3550))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: 24,
              child: Text(dirGlyph, textAlign: TextAlign.center, style: FsType.sans(size: 12, color: dirColor)),
            ),
            // File + route.
            Expanded(
              flex: 32,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: FsType.sans(size: 12, weight: FontWeight.w500, color: FsColors.text1)),
                const SizedBox(height: 2),
                Text(t.route, overflow: TextOverflow.ellipsis, style: FsType.mono(size: 10, color: FsColors.text3)),
              ]),
            ),
            // Progress.
            Expanded(
              flex: 20,
              child: t.status == TransferStatus.error
                  ? Text(t.errorMessage ?? 'Error', style: FsType.sans(size: 10, color: FsColors.red))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 120,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: t.progress,
                            minHeight: 6,
                            backgroundColor: FsColors.bgPanel,
                            valueColor: AlwaysStoppedAnimation(fillColor),
                          ),
                        ),
                      ),
                      if (t.progress > 0 && t.status != TransferStatus.queued) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${(t.progress * 100).round()}% · ${formatBytes(t.sizeBytes * t.progress)} / ${formatBytes(t.sizeBytes)}',
                          style: FsType.mono(size: 10, color: FsColors.text3),
                        ),
                      ],
                    ]),
            ),
            Expanded(flex: 10, child: Text(formatBytes(t.sizeBytes), style: FsType.mono(size: 10, color: FsColors.text3))),
            Expanded(
              flex: 11,
              child: Text(t.speed,
                  style: FsType.mono(size: 10, color: t.speed == '—' ? FsColors.text3 : FsColors.accentHi)),
            ),
            Expanded(flex: 9, child: Text(t.eta, style: FsType.mono(size: 10, color: FsColors.text3))),
            Expanded(flex: 14, child: Text(t.session, style: FsType.sans(size: 11, color: FsColors.text2))),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: t.status == TransferStatus.error
                    ? StatusBadge(badge.label, bg: badge.bg, fg: badge.fg, onTap: () => app.retry(t))
                    : StatusBadge(badge.label, bg: badge.bg, fg: badge.fg, onTap: () => app.togglePause(t)),
              ),
            ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Aggregate stats footer ──
  Widget _statsBar(TransfersState s, TransfersNotifier n) {
    // "Transferred" aggregates live progress, so rebuild on any transfer's
    // live tick.
    return ListenableBuilder(
      listenable: Listenable.merge([for (final t in s.transfers) t.liveTick]),
      builder: (context, _) => _statsBarBody(s, n),
    );
  }

  Widget _statsBarBody(TransfersState s, TransfersNotifier n) {
    final transfers = s.transfers;
    final total = transfers.fold<int>(0, (sum, t) => sum + t.sizeBytes);
    final transferred = transfers.fold<double>(0, (sum, t) => sum + t.sizeBytes * t.progress);

    // Live aggregate speed / ETA come from the active transfers, not a mock.
    final active = transfers.where((t) => t.status == TransferStatus.active).toList();
    final speed = active.isEmpty
        ? '—'
        : (active.length == 1 ? active.first.speed : '${active.length} active');
    final eta = active.length == 1 ? active.first.eta : '—';

    Widget stat(String label, String value, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: FsType.sans(size: 11, color: FsColors.text3)),
          const SizedBox(width: 6),
          Text(value, style: FsType.mono(size: 11, weight: FontWeight.w500, color: color ?? FsColors.text1)),
        ]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        stat('Total queued', formatBytes(total)),
        const SizedBox(width: 24),
        stat('Transferred', formatBytes(transferred), color: FsColors.green),
        const SizedBox(width: 24),
        stat('Speed', speed),
        const SizedBox(width: 24),
        stat('ETA', eta, color: FsColors.amber),
        const SizedBox(width: 24),
        stat('Parallel threads', '${s.activeCount} / ${s.maxThreads}'),
        const Spacer(),
        Text('Threads:', style: FsType.sans(size: 11, color: FsColors.text2)),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: FsTextField(
            value: '${s.maxThreads}',
            align: TextAlign.center,
            height: 24,
            onChanged: (v) {
              final num = int.tryParse(v);
              if (num != null) n.setMaxThreads(num);
            },
          ),
        ),
      ]),
    );
  }
}
