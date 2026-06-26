import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app.dart';
import '../theme.dart';

/// Bottom-right stack of transient notifications.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastsProvider);
    // Keep the cards comfortably wide but never overflow a narrow window.
    final maxW = MediaQuery.of(context).size.width - 56;
    final width = maxW < 420.0 ? maxW : 420.0;
    return Positioned(
      right: 24,
      bottom: 24,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in toasts) _ToastCard(t),
        ],
      ),
    );
  }
}

class _ToastCard extends ConsumerWidget {
  final ToastMessage t;
  const _ToastCard(this.t);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(t.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset((1 - v) * 28, 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: FsColors.bgPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.kind.color.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Coloured accent rail down the left edge.
              Container(width: 4, color: t.kind.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.kind.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(t.kind.icon, style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                style: FsType.sans(
                                    size: 14, weight: FontWeight.w700, color: t.kind.fg)),
                            const SizedBox(height: 3),
                            Text(t.subtitle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: FsType.sans(
                                    size: 12.5,
                                    height: 1.35,
                                    color: t.kind.fg.withValues(alpha: 0.88))),
                            if (t.detail != null) ...[
                              const SizedBox(height: 5),
                              Text(t.detail!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: FsType.sans(
                                      size: 11, color: t.kind.fg.withValues(alpha: 0.7))),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _CloseButton(onTap: () => ref.read(toastsProvider.notifier).dismiss(t.id)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(Icons.close, size: 15, color: FsColors.text3),
        ),
      ),
    );
  }
}
