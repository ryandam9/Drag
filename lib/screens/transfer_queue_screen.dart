import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return Container(
      color: FsColors.bgScaffold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(state, notifier),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: _statsCard(state, notifier),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _queueCard(ref, state, notifier),
            ),
          ),
        ],
      ),
    );
  }

  // ── Title + status pills + bulk actions ──
  Widget _header(TransfersState s, TransfersNotifier n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Transfers',
                style: FsType.sans(size: 22, weight: FontWeight.w700, color: FsColors.text1)),
            const Spacer(),
            TbButton('⏸ Pause all', onTap: n.pauseAll),
            TbButton('▶ Resume all', onTap: n.resumeAll),
            if (s.errorCount > 0) TbButton('↺ Retry failed', onTap: n.retryAllFailed),
            TbButton('⊗ Clear done', onTap: n.clearDone),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  StatusBadge('● Active  ${s.activeCount}', bg: FsColors.badgeLocalBg, fg: FsColors.accentHi),
                  const SizedBox(width: 6),
                  StatusBadge('⊡ Queued  ${s.queuedCount}', bg: FsColors.badgeQueuedBg, fg: FsColors.badgeQueuedFg),
                  const SizedBox(width: 6),
                  StatusBadge('✓ Done  ${s.doneCount}', bg: FsColors.badgeDoneBg, fg: FsColors.badgeDoneFg),
                  const SizedBox(width: 6),
                  StatusBadge('✕ Error  ${s.errorCount}', bg: FsColors.badgeErrorBg, fg: FsColors.badgeErrorFg),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            const FsTextField(hint: 'Filter transfers…', mono: false, width: 200, height: 32),
          ]),
        ],
      ),
    );
  }

  // ── Stats card: tinted icon chip + big number + label per status ──
  Widget _statsCard(TransfersState s, TransfersNotifier n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
        boxShadow: FsColors.cardShadow,
      ),
      child: Row(children: [
        _stat('Active', s.activeCount, Icons.swap_vert_rounded, FsColors.accent),
        _statDivider(),
        _stat('Queued', s.queuedCount, Icons.schedule_rounded, FsColors.badgeQueuedFg),
        _statDivider(),
        _stat('Done', s.doneCount, Icons.check_circle_outline, FsColors.green),
        _statDivider(),
        _stat('Error', s.errorCount, Icons.error_outline, FsColors.red),
      ]),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: FsColors.border,
      );

  Widget _stat(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(color, FsColors.bgSurface, 0.82),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value', style: FsType.sans(size: 22, weight: FontWeight.w800, color: FsColors.text1)),
            Text(label, style: FsType.sans(size: 12, color: FsColors.text2)),
          ],
        ),
      ]),
    );
  }

  // ── Transfer table card ──
  Widget _queueCard(WidgetRef ref, TransfersState s, TransfersNotifier n) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
        boxShadow: FsColors.cardShadow,
      ),
      child: Column(children: [
        Expanded(child: _table(ref, s, n)),
        _statsBar(s, n),
      ]),
    );
  }

  // ── Transfer table ──
  Widget _table(WidgetRef ref, TransfersState s, TransfersNotifier n) {
    if (s.transfers.isEmpty) {
      return Container(
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.lerp(FsColors.accent, FsColors.bgSurface, 0.82),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.swap_vert_rounded, size: 28, color: FsColors.accent),
          ),
          const SizedBox(height: 14),
          Text('No transfers yet',
              style: FsType.sans(size: 16, weight: FontWeight.w700, color: FsColors.text1)),
          const SizedBox(height: 6),
          Text('Drag a file between panes in the Browser to start one.',
              style: FsType.sans(size: 12, color: FsColors.text2)),
        ]),
      );
    }
    return Column(children: [
      _head(),
      Expanded(
        child: ListView.builder(
          itemCount: s.transfers.length,
          itemBuilder: (context, i) => _row(context, ref, n, s.transfers[i]),
        ),
      ),
    ]);
  }

  Widget _head() {
    Widget cell(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t,
              style: FsType.sans(size: 10, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 0.7)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
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

  Widget _row(BuildContext context, WidgetRef ref, TransfersNotifier app, Transfer t) {
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showDetails(context, ref, app, t),
          child: MouseRegion(
          cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: hover ? FsColors.bgHover : Colors.transparent,
            border: Border(bottom: BorderSide(color: FsColors.border)),
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
                Text(t.route, overflow: TextOverflow.ellipsis, style: FsType.sans(size: 10, color: FsColors.text3)),
              ]),
            ),
            // Progress.
            Expanded(
              flex: 20,
              child: t.status == TransferStatus.error
                  ? Text(
                      '${t.errorMessage ?? 'Error'} · ${t.attempts}/${TransfersNotifier.maxAttempts} tries',
                      style: FsType.sans(size: 10, color: FsColors.red))
                  : (t.status == TransferStatus.queued && t.attempts > 0)
                      ? Text('Retrying… (attempt ${t.attempts + 1}/${TransfersNotifier.maxAttempts})',
                          style: FsType.sans(size: 10, color: FsColors.amber))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 120,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: t.progress,
                            minHeight: 6,
                            backgroundColor: FsColors.bgHover,
                            valueColor: AlwaysStoppedAnimation(fillColor),
                          ),
                        ),
                      ),
                      if (t.progress > 0 && t.status != TransferStatus.queued) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${(t.progress * 100).round()}% · ${formatBytes(t.sizeBytes * t.progress)} / ${formatBytes(t.sizeBytes)}',
                          style: FsType.sans(size: 10, color: FsColors.text3, tabular: true),
                        ),
                      ],
                    ]),
            ),
            Expanded(flex: 10, child: Text(formatBytes(t.sizeBytes), style: FsType.sans(size: 10, color: FsColors.text3, tabular: true))),
            Expanded(
              flex: 11,
              child: Text(t.speed,
                  style: FsType.sans(size: 10, color: t.speed == '—' ? FsColors.text3 : FsColors.accentHi, tabular: true)),
            ),
            Expanded(flex: 9, child: Text(t.eta, style: FsType.sans(size: 10, color: FsColors.text3, tabular: true))),
            Expanded(flex: 14, child: Text(t.session, style: FsType.sans(size: 11, color: FsColors.text2))),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: t.status == TransferStatus.error
                    ? StatusBadge('↺ Retry', bg: badge.bg, fg: badge.fg, onTap: () => app.retry(t))
                    : StatusBadge(badge.label, bg: badge.bg, fg: badge.fg, onTap: () => app.togglePause(t)),
              ),
            ),
            ]),
          ),
          ),
          ),
        );
      }),
    );
  }

  // ── Per-transfer details panel ──
  Future<void> _showDetails(
      BuildContext context, WidgetRef ref, TransfersNotifier app, Transfer t) {
    Future<void> copy(String label, String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      ref.read(toastsProvider.notifier).push('Copied', label, ToastKind.info);
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FsColors.bgPanel,
        title: Row(children: [
          Expanded(
            child: Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
          ),
          () {
            final b = _badge(t.status);
            return StatusBadge(b.label, bg: b.bg, fg: b.fg);
          }(),
        ]),
        content: SizedBox(
          width: 520,
          // Live-update while the transfer is active.
          child: ValueListenableBuilder<int>(
            valueListenable: t.liveTick,
            builder: (_, _, _) => _detailsBody(t),
          ),
        ),
        actions: [
          if (t.sourcePath.isNotEmpty)
            FsButton('Copy source', onTap: () => copy('Source path', t.sourcePath)),
          if (t.destPath.isNotEmpty)
            FsButton('Copy destination', onTap: () => copy('Destination path', t.destPath)),
          if (t.status == TransferStatus.active || t.status == TransferStatus.queued)
            FsButton('Pause', onTap: () => app.togglePause(t)),
          if (t.status == TransferStatus.paused)
            FsButton('Resume', onTap: () => app.togglePause(t)),
          if (t.status == TransferStatus.error)
            FsButton('Retry', kind: FsButtonKind.primary, onTap: () {
              app.retry(t);
              Navigator.pop(ctx);
            }),
          if (t.status != TransferStatus.done)
            FsButton('Cancel transfer', kind: FsButtonKind.danger, onTap: () {
              app.cancel(t);
              Navigator.pop(ctx);
            }),
          FsButton('Close', onTap: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  Widget _detailsBody(Transfer t) {
    final done = formatBytes(t.sizeBytes * t.progress);
    final rows = <(String, String)>[
      ('Direction', t.direction == TransferDirection.upload ? 'Upload' : 'Download'),
      ('Source', t.sourcePath.isEmpty ? '—' : t.sourcePath),
      ('Destination', t.destPath.isEmpty ? '—' : t.destPath),
      ('Size', formatBytes(t.sizeBytes)),
      ('Transferred', '$done (${(t.progress * 100).round()}%)'),
      ('Speed', t.speed),
      ('ETA', t.eta),
      ('Elapsed', t.elapsedLabel),
      ('Session', t.session),
      ('Attempts', '${t.attempts} / ${TransfersNotifier.maxAttempts}'),
      if (t.errorMessage != null) ('Error', t.errorMessage!),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 110,
                child: Text(label,
                    style: FsType.sans(size: 11, weight: FontWeight.w600, color: FsColors.text3)),
              ),
              Expanded(
                child: SelectableText(value,
                    style: FsType.sans(
                        size: 12,
                        color: label == 'Error' ? FsColors.red : FsColors.text1,
                        height: 1.4)),
              ),
            ]),
          ),
      ],
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
          Text(value, style: FsType.sans(size: 11, weight: FontWeight.w500, color: color ?? FsColors.text1, tabular: true)),
        ]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
            ]),
          ),
        ),
        const SizedBox(width: 16),
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
