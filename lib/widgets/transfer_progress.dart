import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transfer.dart';
import '../state/app.dart';
import '../theme.dart';

/// Threshold above which a transfer is considered "big" and gets the
/// prominent progress card treatment.
const _bigFileBytes = 10 * 1024 * 1024;

/// A floating card that appears (bottom-left, above the toasts) while a
/// transfer is active — an animated ring + bar with live speed/ETA. Big files
/// get the spotlight; if nothing is active it renders nothing.
class ActiveTransferOverlay extends ConsumerWidget {
  const ActiveTransferOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navProvider);
    // Keep clear of screens whose bottom-left holds action buttons / forms.
    if (screen == AppScreen.connections || screen == AppScreen.settings) {
      return const SizedBox.shrink();
    }
    final active = ref.watch(transfersProvider).transfers
        .where((t) => t.status == TransferStatus.active)
        .toList()
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (active.isEmpty) return const SizedBox.shrink();

    final t = active.first;
    final others = active.length - 1;

    return Positioned(
      left: 18,
      bottom: 18,
      width: 340,
      child: _Card(transfer: t, othersActive: others),
    );
  }
}

class _Card extends StatelessWidget {
  final Transfer transfer;
  final int othersActive;
  const _Card({required this.transfer, required this.othersActive});

  @override
  Widget build(BuildContext context) {
    // Rebuild only on this transfer's live ticks (progress/speed/eta).
    return ValueListenableBuilder<int>(
      valueListenable: transfer.liveTick,
      builder: (context, _, _) => _build(),
    );
  }

  Widget _build() {
    final t = transfer;
    final big = t.sizeBytes >= _bigFileBytes;
    final indeterminate = t.progress <= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FsColors.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FsColors.borderHi),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Ring(progress: t.progress, indeterminate: indeterminate),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      t.direction == TransferDirection.upload
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_download_outlined,
                      size: 14,
                      color: FsColors.accentHi,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FsType.sans(size: 13, weight: FontWeight.w600, color: FsColors.text1)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(t.route,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FsType.mono(size: 10, color: FsColors.text3)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Animated linear bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: t.progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => LinearProgressIndicator(
                value: indeterminate ? null : value,
                minHeight: 6,
                backgroundColor: FsColors.bgDeep,
                valueColor: AlwaysStoppedAnimation(FsColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _chip(big ? '⬆ Big file' : (t.direction == TransferDirection.upload ? 'Uploading' : 'Downloading')),
            const Spacer(),
            Text(t.speed, style: FsType.mono(size: 11, color: FsColors.accentHi)),
            if (t.eta != '—' && t.eta != 'Done') ...[
              const SizedBox(width: 10),
              Text('ETA ${t.eta}', style: FsType.mono(size: 11, color: FsColors.text3)),
            ],
          ]),
          if (othersActive > 0) ...[
            const SizedBox(height: 6),
            Text('+ $othersActive more transferring…', style: FsType.sans(size: 10, color: FsColors.text3)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: FsColors.bgActive, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: FsType.sans(size: 10, weight: FontWeight.w600, color: FsColors.accentHi)),
      );
}

/// A circular progress ring with the percentage in the middle; spins when the
/// transfer is still indeterminate (0%).
class _Ring extends StatelessWidget {
  final double progress;
  final bool indeterminate;
  const _Ring({required this.progress, required this.indeterminate});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, _) => SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                value: indeterminate ? null : value,
                strokeWidth: 4,
                backgroundColor: FsColors.bgDeep,
                valueColor: AlwaysStoppedAnimation(FsColors.accentHi),
              ),
            ),
          ),
          Text(
            indeterminate ? '…' : '${(progress * 100).round()}',
            style: FsType.sans(size: 11, weight: FontWeight.w700, color: FsColors.text1),
          ),
        ],
      ),
    );
  }
}
