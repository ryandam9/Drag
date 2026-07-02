import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app.dart';
import '../theme.dart';

/// Top-right stack of transient notifications (newest on top).
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastsProvider);
    // Comfortably wide, but never wider than a narrow window allows.
    final maxW = MediaQuery.of(context).size.width - 56;
    final width = maxW < 420.0 ? maxW : 420.0;
    return Positioned(
      // Clear the 44px title bar.
      top: 56,
      right: 24,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Newest first, so a fresh toast slides in at the top.
          for (final t in toasts.reversed) _ToastCard(t),
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        // Slide down + in from the top-right as it appears.
        child: Transform.translate(
          offset: Offset((1 - v) * 26, (1 - v) * -10),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: FsColors.bgPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.kind.color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: t.kind.color.withValues(alpha: 0.10),
              blurRadius: 14,
              spreadRadius: -2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Coloured accent rail down the left edge.
                  Container(width: 4, color: t.kind.color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.kind.color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              t.kind.icon,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: FsType.sans(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: t.kind.fg,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  t.subtitle,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: FsType.sans(
                                    size: 12.5,
                                    height: 1.35,
                                    color: t.kind.fg.withValues(alpha: 0.88),
                                  ),
                                ),
                                if (t.detail != null) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    t.detail!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: FsType.sans(
                                      size: 11,
                                      color: t.kind.fg.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          _CloseButton(
                            onTap: () =>
                                ref.read(toastsProvider.notifier).dismiss(t.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // A thin bar that depletes over the toast's lifetime.
            _CountdownBar(color: t.kind.color),
          ],
        ),
      ),
    );
  }
}

/// A 2px progress bar that shrinks from full to empty over [kToastDuration],
/// giving a visible sense of how long the toast will linger.
class _CountdownBar extends StatelessWidget {
  final Color color;
  const _CountdownBar({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2.5,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: kToastDuration,
        builder: (context, v, _) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v.clamp(0, 1),
            child: Container(color: color.withValues(alpha: 0.55)),
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
