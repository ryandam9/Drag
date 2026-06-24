import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app.dart';
import '../theme.dart';
import 'common.dart';

/// Far-left vertical navigation switching between the five screens.
class NavRail extends ConsumerWidget {
  const NavRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navProvider);
    final transfers = ref.watch(transfersProvider);
    final queueBadge = transfers.activeCount + transfers.queuedCount;

    Widget item(IconData icon, String tip, AppScreen screen, {int? badge}) {
      final selected = current == screen;
      return Hoverable(builder: (hover) {
        return Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 400),
          child: GestureDetector(
            onTap: () => ref.read(navProvider.notifier).go(screen),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? FsColors.bgActive
                      : hover
                          ? FsColors.bgHover
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon,
                        size: 19,
                        color: selected ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2)),
                    if (badge != null && badge > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: FsColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$badge',
                              style: FsType.sans(size: 8, weight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    }

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(right: BorderSide(color: FsColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          // App icon / logo mark.
          Tooltip(
            message: 'Drag',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icons/drag_256.png', width: 32, height: 32, filterQuality: FilterQuality.medium),
            ),
          ),
          const SizedBox(height: 18),
          item(Icons.folder_copy_outlined, 'Browser', AppScreen.browser),
          item(Icons.lan_outlined, 'Connections', AppScreen.connections),
          item(Icons.swap_vert_rounded, 'Transfer Queue', AppScreen.queue, badge: queueBadge),
          item(Icons.insights_outlined, 'History Dashboard', AppScreen.dashboard),
          const Spacer(),
          item(Icons.settings_outlined, 'Preferences', AppScreen.settings),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
