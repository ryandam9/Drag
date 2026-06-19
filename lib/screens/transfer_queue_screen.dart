import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../state/app_state.dart';
import '../state/scopes.dart';
import '../state/transfers_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TransferQueueScreen extends StatelessWidget {
  const TransferQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Subscribe to the transfer queue only — toasts, settings and session
    // changes no longer rebuild this screen.
    final app = TransfersScope.of(context);
    return Column(children: [
      _filterBar(app),
      Expanded(child: _table(app)),
      _statsBar(app),
    ]);
  }

  // ── Status filter chips + free text filter ──
  Widget _filterBar(TransfersController app) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        StatusBadge('● Active  ${app.activeCount}', bg: FsColors.badgeLocalBg, fg: FsColors.accentHi),
        const SizedBox(width: 6),
        StatusBadge('⊡ Queued  ${app.queuedCount}', bg: FsColors.badgeQueuedBg, fg: FsColors.badgeQueuedFg),
        const SizedBox(width: 6),
        StatusBadge('✓ Done  ${app.doneCount}', bg: FsColors.badgeDoneBg, fg: FsColors.badgeDoneFg),
        const SizedBox(width: 6),
        StatusBadge('✕ Error  ${app.errorCount}', bg: FsColors.badgeErrorBg, fg: FsColors.badgeErrorFg),
        const Spacer(),
        TbButton('⏸ Pause all', onTap: app.pauseAll),
        TbButton('▶ Resume all', onTap: app.resumeAll),
        TbButton('⊗ Clear done', onTap: app.clearDone),
        const SizedBox(width: 8),
        const FsTextField(hint: 'Filter transfers…', mono: false, width: 180, height: 28),
      ]),
    );
  }

  // ── Transfer table ──
  Widget _table(TransfersController app) {
    return Container(
      color: FsColors.bgSurface,
      child: Column(children: [
        _head(),
        Expanded(
          child: ListView.builder(
            itemCount: app.transfers.length,
            itemBuilder: (context, i) => _row(app, app.transfers[i]),
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

  Widget _row(TransfersController app, Transfer t) {
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
  Widget _statsBar(TransfersController app) {
    // "Transferred" aggregates live progress, so rebuild on any transfer's
    // live tick (this footer is only mounted on the queue screen).
    return ListenableBuilder(
      listenable: Listenable.merge([for (final t in app.transfers) t.liveTick]),
      builder: (context, _) => _statsBarBody(app),
    );
  }

  Widget _statsBarBody(TransfersController app) {
    final total = app.transfers.fold<int>(0, (s, t) => s + t.sizeBytes);
    final transferred = app.transfers.fold<double>(0, (s, t) => s + t.sizeBytes * t.progress);

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
        stat('Speed', '1.6 MB/s'),
        const SizedBox(width: 24),
        stat('ETA', '1:02', color: FsColors.amber),
        const SizedBox(width: 24),
        stat('Parallel threads', '${app.activeCount} / ${app.maxThreads}'),
        const Spacer(),
        Text('Threads:', style: FsType.sans(size: 11, color: FsColors.text2)),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: FsTextField(
            value: '${app.maxThreads}',
            align: TextAlign.center,
            height: 24,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null) app.setMaxThreads(n);
            },
          ),
        ),
      ]),
    );
  }
}
