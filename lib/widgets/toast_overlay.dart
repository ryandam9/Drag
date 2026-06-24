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
    return Positioned(
      right: 18,
      bottom: 18,
      width: 280,
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

class _ToastCard extends StatelessWidget {
  final ToastMessage t;
  const _ToastCard(this.t);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(t.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset((1 - v) * 24, 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.kind.color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.kind.color.withValues(alpha: 0.27)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.kind.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: FsType.sans(size: 12, weight: FontWeight.w600, color: t.kind.fg)),
                  const SizedBox(height: 2),
                  Text(t.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FsType.sans(size: 11, color: t.kind.fg.withValues(alpha: 0.85))),
                  if (t.detail != null) ...[
                    const SizedBox(height: 3),
                    Text(t.detail!, style: FsType.sans(size: 10, color: t.kind.fg.withValues(alpha: 0.7))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
