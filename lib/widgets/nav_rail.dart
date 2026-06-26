import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app.dart';
import '../theme.dart';
import 'common.dart';

/// The left navigation sidebar. Expanded it shows the logo, labelled
/// destinations, a Settings entry, the active-session card and a Collapse
/// toggle; collapsed it shrinks to an icon-only rail. The collapsed state is
/// persisted in [AppSettings.sidebarCollapsed].
class NavRail extends ConsumerWidget {
  const NavRail({super.key});

  static const _expandedWidth = 232.0;
  static const _collapsedWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navProvider);
    final collapsed = ref.watch(settingsProvider.select((s) => s.sidebarCollapsed));
    final transfers = ref.watch(transfersProvider);
    final queueBadge = transfers.activeCount + transfers.queuedCount;
    final nav = ref.read(navProvider.notifier);

    Widget destination(IconData icon, String label, AppScreen screen, {int? badge}) =>
        _NavItem(
          icon: icon,
          label: label,
          collapsed: collapsed,
          selected: current == screen,
          badge: badge,
          onTap: () => nav.go(screen),
        );

    final targetWidth = collapsed ? _collapsedWidth : _expandedWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: targetWidth,
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(right: BorderSide(color: FsColors.border)),
      ),
      // While the width animates, lay the content out at the stable target
      // width and clip — otherwise the rows momentarily overflow the shrinking
      // constraint.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: targetWidth,
          maxWidth: targetWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(collapsed),
              const SizedBox(height: 8),
              destination(Icons.folder_copy_outlined, 'Browser', AppScreen.browser),
              destination(Icons.lan_outlined, 'Connections', AppScreen.connections),
              destination(Icons.swap_vert_rounded, 'Transfer Queue', AppScreen.queue, badge: queueBadge),
              destination(Icons.insights_outlined, 'History', AppScreen.dashboard),
              const Spacer(),
              Divider(height: 1, color: FsColors.border),
              const SizedBox(height: 6),
              destination(Icons.settings_outlined, 'Settings', AppScreen.settings),
              destination(Icons.info_outline, 'About', AppScreen.about),
              _sessionCard(ref, collapsed),
              _collapseToggle(ref, collapsed),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // App logo + name (name hidden when collapsed).
  Widget _header(bool collapsed) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset('assets/icons/drag_256.png',
          width: 32, height: 32, filterQuality: FilterQuality.medium),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 16 : 16, 16, 16, 8),
      child: Row(
        children: [
          logo,
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text('Drag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
            ),
          ],
        ],
      ),
    );
  }

  // A card at the bottom showing the active session's endpoint (parallels the
  // reference's "active office" card). Tapping it jumps to the Browser.
  Widget _sessionCard(WidgetRef ref, bool collapsed) {
    ref.watch(sessionsProvider);
    final label = ref.read(sessionsProvider.notifier).activeSession.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Tooltip(
        message: collapsed ? 'Active session · $label' : '',
        child: Hoverable(builder: (hover) {
          return GestureDetector(
            onTap: () => ref.read(navProvider.notifier).go(AppScreen.browser),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 8),
                decoration: BoxDecoration(
                  color: hover ? FsColors.bgHover : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment:
                      collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(Icons.dns_outlined, size: 18, color: FsColors.text2),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FsType.sans(
                                    size: 12, weight: FontWeight.w600, color: FsColors.text1)),
                            Text('Active session',
                                style: FsType.sans(size: 10, color: FsColors.text3)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _collapseToggle(WidgetRef ref, bool collapsed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Hoverable(builder: (hover) {
        return GestureDetector(
          onTap: () => ref.read(settingsProvider.notifier).toggleSidebar(),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 9),
              decoration: BoxDecoration(
                color: hover ? FsColors.bgHover : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment:
                    collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(collapsed ? Icons.chevron_right : Icons.chevron_left,
                      size: 20, color: FsColors.text2),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Text('Collapse', style: FsType.sans(size: 12, color: FsColors.text2)),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A single navigation row: full-width labelled pill when expanded, a centered
/// icon tile when collapsed. Selected = soft [FsColors.bgActive] pill.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool collapsed;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? FsColors.accentHi : FsColors.text2;
    final iconWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 20, color: selected ? FsColors.accentHi : FsColors.text2),
        if (badge != null && badge! > 0)
          Positioned(
            top: -4,
            right: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: FsColors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('$badge',
                  style: FsType.sans(size: 8, weight: FontWeight.w700, color: FsColors.scheme.onPrimary)),
            ),
          ),
      ],
    );

    return Hoverable(builder: (hover) {
      final bg = selected
          ? FsColors.bgActive
          : hover
              ? FsColors.bgHover
              : Colors.transparent;
      final row = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            iconWithBadge,
            if (!collapsed) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FsType.sans(
                        size: 13, weight: selected ? FontWeight.w600 : FontWeight.w500, color: fg)),
              ),
            ],
          ],
        ),
      );
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: collapsed
              ? Tooltip(message: label, waitDuration: const Duration(milliseconds: 400), child: row)
              : row,
        ),
      );
    });
  }
}
