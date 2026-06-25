import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});
  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  double _split = 0.5;
  bool _dropHoverLeft = false;
  bool _dropHoverRight = false;

  /// Runtime override for the log panel; null = follow the "show log on
  /// startup" setting.
  bool? _showLogOverride;

  // ── Notifier shortcuts (actions only — reactive reads happen in build) ──
  SessionsNotifier get _sessions => ref.read(sessionsProvider.notifier);
  PaneController get _leftPane => _sessions.leftPane;
  PaneController get _rightPane => _sessions.rightPane;
  PaneController get _focusedPane => _sessions.focusedPane;

  void _toast(String t, String s, ToastKind k) => ref.read(toastsProvider.notifier).push(t, s, k);
  void _go(AppScreen s) => ref.read(navProvider.notifier).go(s);

  TransfersNotifier? _transfersRef;

  @override
  void initState() {
    super.initState();
    // Transfers ask us to resolve destination name clashes via a dialog.
    _transfersRef = ref.read(transfersProvider.notifier);
    _transfersRef!.setConflictResolver(_resolveConflict);
  }

  @override
  void dispose() {
    // Use the cached notifier — `ref` is unsafe in dispose().
    _transfersRef?.setConflictResolver(null);
    super.dispose();
  }

  /// Shows the Skip / Overwrite / Rename dialog for a name clash, with an
  /// "apply to all" option. Returns null if dismissed (treated as skip).
  Future<ConflictResolution?> _resolveConflict(ConflictPrompt p) async {
    if (!mounted) return const ConflictResolution(ConflictAction.overwrite);
    var all = false;
    return showDialog<ConflictResolution>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: FsColors.bgPanel,
          title: Text('File already exists',
              style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"${p.name}" already exists in ${p.destLabel}. What would you like to do?',
                style: FsType.sans(size: 12, color: FsColors.text2, height: 1.5)),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setLocal(() => all = !all),
              child: Row(children: [
                SizedBox(
                  width: 18, height: 18,
                  child: Checkbox(
                    value: all,
                    onChanged: (v) => setLocal(() => all = v ?? false),
                    activeColor: FsColors.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Apply to all remaining', style: FsType.sans(size: 12, color: FsColors.text2)),
              ]),
            ),
          ]),
          actions: [
            FsButton('Skip', onTap: () => Navigator.pop(ctx, ConflictResolution(ConflictAction.skip, applyToAll: all))),
            FsButton('Rename', onTap: () => Navigator.pop(ctx, ConflictResolution(ConflictAction.rename, applyToAll: all))),
            FsButton('Overwrite',
                kind: FsButtonKind.primary,
                onTap: () => Navigator.pop(ctx, ConflictResolution(ConflictAction.overwrite, applyToAll: all))),
          ],
        ),
      ),
    );
  }

  /// Copy a full endpoint location (s3://… , sftp://… , or a local absolute
  /// path) to the clipboard and confirm with a toast.
  Future<void> _copyLocation(String location) async {
    await Clipboard.setData(ClipboardData(text: location));
    _toast('Copied', location, ToastKind.info);
  }

  String _pathLabel(PaneController pane) {
    final segs = pane.path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? pane.displayPath : segs.last;
  }

  Future<void> _toggleBookmark(PaneController pane) async {
    final bm = ref.read(bookmarksProvider.notifier);
    final was = bm.isBookmarked(pane.connection?.id, pane.path);
    await bm.toggle(pane.connection?.id, pane.path, _pathLabel(pane));
    _toast(was ? 'Bookmark removed' : 'Bookmarked', pane.displayPath, ToastKind.info);
  }

  /// Quick-jump menu: this endpoint's bookmarks + recently visited paths.
  Future<void> _showQuickJump(BuildContext ctx, PaneController pane) async {
    final box = ctx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final connId = pane.connection?.id;
    final bookmarks = ref.read(bookmarksProvider.notifier).forEndpoint(connId);
    final recents = pane.recentPaths.take(6).toList();

    PopupMenuItem<String> pathItem(String label, String path) => PopupMenuItem(
          value: path,
          child: SizedBox(
            width: 260,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: FsType.sans(size: 12, color: FsColors.text1)),
              Text(pane.backend.displayPath(path), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: FsType.sans(size: 10, color: FsColors.text3)),
            ]),
          ),
        );

    final items = <PopupMenuEntry<String>>[];
    if (bookmarks.isEmpty && recents.isEmpty) {
      items.add(PopupMenuItem(enabled: false, child: _menuText('No bookmarks or recent paths')));
    } else {
      if (bookmarks.isNotEmpty) {
        items.add(PopupMenuItem(enabled: false, height: 28, child: _menuHeader('BOOKMARKS')));
        for (final b in bookmarks) {
          items.add(pathItem(b.label, b.path));
        }
      }
      if (recents.isNotEmpty) {
        if (bookmarks.isNotEmpty) items.add(const PopupMenuDivider());
        items.add(PopupMenuItem(enabled: false, height: 28, child: _menuHeader('RECENT')));
        for (final r in recents) {
          items.add(pathItem(_lastSegment(r), r));
        }
      }
    }

    final choice = await showMenu<String>(
      context: context,
      color: FsColors.bgPanel,
      position: RelativeRect.fromLTRB(origin.dx, origin.dy, overlay.size.width - origin.dx - 240, 0),
      items: items,
    );
    if (choice != null) await pane.navigateTo(choice);
  }

  String _lastSegment(String path) {
    final segs = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? path : segs.last;
  }

  Widget _menuHeader(String t) => Text(t,
      style: FsType.sans(size: 9, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1));

  @override
  Widget build(BuildContext context) {
    final sessionsState = ref.watch(sessionsProvider);
    ref.watch(connectionsProvider); // endpoint pickers
    ref.watch(bookmarksProvider); // star state + quick-jump menu
    final settings = ref.watch(settingsProvider);
    final showLog = _showLogOverride ?? settings.showLogOnStartup;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(event),
      child: Column(
        children: [
          _sessionTabs(sessionsState),
          _toolbar(settings.showLogOnStartup),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final leftW = (c.maxWidth - 5) * _split;
              return Row(
                children: [
                  SizedBox(width: leftW, child: _pane(_leftPane, settings.showPermsColumn, left: true)),
                  _divider(c.maxWidth),
                  Expanded(child: _pane(_rightPane, settings.showPermsColumn, left: false)),
                ],
              );
            }),
          ),
          _queueStrip(),
          if (showLog) _logPanel(),
        ],
      ),
    );
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pane = _focusedPane;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.f2:
        _renameSelected(pane);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        _deleteSelected(pane);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        pane.goUp();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── File-operation handlers (act on a pane + its selection) ──
  FileItem? _selected(PaneController pane) {
    final i = pane.selectedIndex;
    if (i == null || i < 0 || i >= pane.items.length) return null;
    final item = pane.items[i];
    return item.isParent ? null : item;
  }

  Future<void> _newFolder(PaneController pane) async {
    if (!pane.backend.supportsMutation) {
      _toast('Not supported', '${pane.endpointLabel} is read-only here', ToastKind.error);
      return;
    }
    final name = await _promptText(title: 'New folder', hint: 'Folder name', confirm: 'Create');
    if (name != null) await _sessions.createFolder(pane, name);
  }

  Future<void> _renameSelected(PaneController pane) async {
    final item = _selected(pane);
    if (item == null) {
      _toast('Nothing selected', 'Select an item to rename', ToastKind.info);
      return;
    }
    final name = await _promptText(title: 'Rename', initial: item.name, confirm: 'Rename');
    if (name != null) await _sessions.renameItem(pane, item, name);
  }

  Future<void> _deleteSelected(PaneController pane) async {
    final items = pane.selectedItems();
    if (items.isEmpty) {
      _toast('Nothing selected', 'Select an item to delete', ToastKind.info);
      return;
    }
    final ok = await _confirm(
      title: items.length == 1 ? 'Delete "${items.first.name}"?' : 'Delete ${items.length} items?',
      message: 'This permanently deletes the selected '
          '${items.length == 1 ? (items.first.isDir ? 'folder and its contents' : 'file') : 'items'}.',
    );
    if (ok) await _sessions.deleteItems(pane, items);
  }

  Future<void> _showRowMenu(PaneController pane, bool left, FileItem item, Offset pos) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      color: FsColors.bgPanel,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, overlay.size.width - pos.dx, 0),
      items: [
        PopupMenuItem(value: 'transfer', child: _menuText(left ? '⬆ Upload to other pane' : '⬇ Download to other pane')),
        PopupMenuItem(value: 'rename', child: _menuText('✎ Rename')),
        PopupMenuItem(value: 'delete', child: _menuText('⊗ Delete', color: FsColors.red)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'newFolder', child: _menuText('⊕ New folder')),
        PopupMenuItem(value: 'copyPath', child: _menuText('📋 Copy path')),
      ],
    );
    switch (choice) {
      case 'transfer':
        _sessions.dropTransfer(DragPayload(item, left), !left);
      case 'rename':
        final name = await _promptText(title: 'Rename', initial: item.name, confirm: 'Rename');
        if (name != null) await _sessions.renameItem(pane, item, name);
      case 'delete':
        await _deleteSelected(pane);
      case 'newFolder':
        await _newFolder(pane);
      case 'copyPath':
        // The full location (s3://bucket/key, sftp://host/path, or the local
        // absolute path) — not just the internal key.
        final loc = pane.backend.displayPath(pane.backend.childPath(pane.path, item.name, item.isDir));
        await _copyLocation(loc);
    }
  }

  Widget _menuText(String t, {Color? color}) =>
      Text(t, style: FsType.sans(size: 12, color: color ?? FsColors.text1));

  /// A small dot showing how an entry compares to the other pane (after
  /// Compare). Blue = only here, amber = differs, green = identical.
  Widget _compareDot(PaneController pane, FileItem f) {
    if (f.isParent || pane.compareMarks.isEmpty) return const SizedBox.shrink();
    final mark = pane.compareMarks[f.name];
    if (mark == null) return const SizedBox(width: 14);
    final (color, tip) = switch (mark) {
      CompareMark.onlyHere => (FsColors.accent, 'Only here'),
      CompareMark.differs => (FsColors.amber, 'Differs from the other pane'),
      CompareMark.same => (FsColors.green, 'Identical'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tip,
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ),
    );
  }

  /// Mirror dialog: pick a direction, preview what it'll do, optionally delete
  /// destination-only extras, then run.
  Future<void> _showMirrorDialog() async {
    var leftToRight = true;
    var deleteExtras = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final plan = _sessions.mirrorPlan(leftToRight: leftToRight, deleteExtras: deleteExtras);
        final srcLabel = leftToRight ? _leftPane.endpointLabel : _rightPane.endpointLabel;
        final dstLabel = leftToRight ? _rightPane.endpointLabel : _leftPane.endpointLabel;
        Widget dirChip(String label, bool value) => GestureDetector(
              onTap: () => setLocal(() => leftToRight = value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: leftToRight == value ? FsColors.bgActive : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FsColors.border),
                ),
                child: Text(label,
                    style: FsType.sans(
                        size: 12,
                        weight: FontWeight.w600,
                        color: leftToRight == value ? FsColors.accentHi : FsColors.text2)),
              ),
            );
        return AlertDialog(
          backgroundColor: FsColors.bgPanel,
          title: Text('Mirror folders',
              style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [dirChip('Left → Right', true), const SizedBox(width: 8), dirChip('Right → Left', false)]),
            const SizedBox(height: 14),
            Text('Make $dstLabel match $srcLabel (current folders):',
                style: FsType.sans(size: 12, color: FsColors.text2)),
            const SizedBox(height: 8),
            Text('· ${plan.fileCopies} file(s) + ${plan.folderCopies} folder(s) to copy',
                style: FsType.sans(size: 12, color: FsColors.text1)),
            Text('· ${plan.delete.length} extra item(s) to delete on $dstLabel',
                style: FsType.sans(size: 12, color: deleteExtras ? FsColors.red : FsColors.text3)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setLocal(() => deleteExtras = !deleteExtras),
              child: Row(children: [
                SizedBox(
                  width: 18, height: 18,
                  child: Checkbox(
                    value: deleteExtras,
                    onChanged: (v) => setLocal(() => deleteExtras = v ?? false),
                    activeColor: FsColors.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Delete destination-only extras', style: FsType.sans(size: 12, color: FsColors.text2)),
              ]),
            ),
          ]),
          actions: [
            FsButton('Cancel', onTap: () => Navigator.pop(ctx)),
            FsButton('Mirror',
                kind: FsButtonKind.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  if (plan.isEmpty) {
                    _toast('Nothing to mirror', 'The folders already match', ToastKind.info);
                  } else {
                    _sessions.runMirror(plan);
                  }
                }),
          ],
        );
      }),
    );
  }

  // ── Dialogs ──
  Future<String?> _promptText({
    required String title,
    String initial = '',
    String hint = '',
    String confirm = 'OK',
  }) {
    final ctl = TextEditingController(text: initial);
    ctl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FsColors.bgPanel,
        title: Text(title, style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctl,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
            style: FsType.sans(size: 13, color: FsColors.text1),
            cursorColor: FsColors.accent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: FsType.sans(size: 13, color: FsColors.text3),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: FsColors.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: FsColors.accent)),
            ),
          ),
        ),
        actions: [
          FsButton('Cancel', onTap: () => Navigator.pop(ctx)),
          FsButton(confirm, kind: FsButtonKind.primary, onTap: () => Navigator.pop(ctx, ctl.text)),
        ],
      ),
    );
  }

  Future<bool> _confirm({required String title, required String message}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FsColors.bgPanel,
        title: Text(title, style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
        content: Text(message, style: FsType.sans(size: 12, color: FsColors.text2, height: 1.5)),
        actions: [
          FsButton('Cancel', onTap: () => Navigator.pop(ctx, false)),
          FsButton('Delete', kind: FsButtonKind.danger, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return r ?? false;
  }

  // ── Session tabs — one open server per tab, switchable & closable ──
  Widget _sessionTabs(SessionsState state) {
    return Container(
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      padding: const EdgeInsets.only(left: 8),
      height: 38,
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final s in state.sessions) _tab(state, s)]),
          ),
        ),
        // New tab → pick a server to connect.
        Hoverable(builder: (hover) {
          return GestureDetector(
            onTap: () => _go(AppScreen.connections),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: 'New session',
                child: Container(
                  width: 30,
                  alignment: Alignment.center,
                  child: Text('＋',
                      style: FsType.sans(size: 15, color: hover ? FsColors.accentHi : FsColors.text3)),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _tab(SessionsState state, Session s) {
    final active = s.id == state.activeSessionId;
    final dot = s.online ? FsColors.green : FsColors.amber;
    return Hoverable(builder: (hover) {
      return GestureDetector(
        onTap: () => _sessions.switchSession(s.id),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              color: active ? FsColors.bgSurface : (hover ? FsColors.bgHover : Colors.transparent),
              border: Border(
                bottom: BorderSide(color: active ? FsColors.accent : Colors.transparent, width: 2),
              ),
            ),
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              StatusDot(dot, glow: s.online),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FsType.sans(size: 12, color: active ? FsColors.accentHi : FsColors.text2)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _sessions.closeSession(s.id),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Hoverable(builder: (h) => Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: h ? FsColors.bgPanel : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(Icons.close, size: 11, color: h ? FsColors.text1 : FsColors.text3),
                      )),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  // ── Toolbar ──
  Widget _toolbar(bool showLogOnStartup) {
    final pane = _focusedPane;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        // The button cluster scrolls horizontally on narrow windows instead of
        // overflowing; the filter stays pinned on the right.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ToolButton('← Back', onTap: pane.canGoBack ? pane.goBack : null),
              ToolButton('→ Fwd', onTap: pane.canGoForward ? pane.goForward : null),
              ToolButton('↑ Up', onTap: pane.goUp),
              const ToolSep(),
              ToolButton('⇄ Compare', onTap: () => _sessions.compareActivePanes()),
              ToolButton('⇉ Mirror', onTap: _showMirrorDialog),
              ToolButton('↯ Queue', onTap: () => _go(AppScreen.queue)),
              ToolButton('📋 Log',
                  active: _showLogOverride ?? showLogOnStartup,
                  onTap: () => setState(
                      () => _showLogOverride = !(_showLogOverride ?? showLogOnStartup))),
              const ToolSep(),
              ToolButton('⊕ New Folder', onTap: () => _newFolder(_focusedPane)),
              ToolButton('✎ Rename', onTap: () => _renameSelected(_focusedPane)),
              ToolButton('⊗ Delete', color: FsColors.red, onTap: () => _deleteSelected(_focusedPane)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Text('Filter:', style: FsType.sans(size: 10, color: FsColors.text3)),
        const SizedBox(width: 6),
        const FsTextField(hint: '*.log, *.conf…', width: 130, height: 26),
      ]),
    );
  }

  Widget _divider(double totalW) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => _split = (_split + d.delta.dx / totalW).clamp(0.25, 0.75)),
        child: Container(width: 5, color: FsColors.border),
      ),
    );
  }

  // ── A pane (drag source + drop target) ──
  Widget _pane(PaneController pane, bool showPerms, {required bool left}) {
    final hover = left ? _dropHoverLeft : _dropHoverRight;
    return DragTarget<DragPayload>(
      onWillAcceptWithDetails: (d) {
        if (d.data.fromLeft == left) return false;
        setState(() => left ? _dropHoverLeft = true : _dropHoverRight = true);
        return true;
      },
      onLeave: (_) => setState(() => left ? _dropHoverLeft = false : _dropHoverRight = false),
      onAcceptWithDetails: (d) {
        setState(() => left ? _dropHoverLeft = false : _dropHoverRight = false);
        _sessions.dropTransfer(d.data, left);
      },
      builder: (context, candidate, rejected) {
        final focused = ref.read(sessionsProvider).focusedLeft == left;
        return Listener(
          onPointerDown: (_) => _sessions.focusPane(left),
          child: Container(
            decoration: BoxDecoration(
              color: hover ? FsColors.accent.withValues(alpha: 0.06) : null,
              border: Border.all(
                color: hover
                    ? FsColors.accent
                    : (focused ? FsColors.borderHi : Colors.transparent),
                width: 2,
              ),
            ),
            child: Column(children: [
              _paneHeader(pane, left: left),
              _breadcrumb(pane.breadcrumb),
              Expanded(child: _paneBody(pane, showPerms, left: left)),
              _paneFooter(pane),
            ]),
          ),
        );
      },
    );
  }

  Widget _paneHeader(PaneController pane, {required bool left}) {
    final isS3 = pane.kind == EndpointKind.s3;
    final isLocal = pane.kind == EndpointKind.local;
    final badgeBg = isLocal
        ? FsColors.badgeLocalBg
        : isS3
            ? FsColors.badgePausedBg
            : FsColors.badgeRemoteBg;
    final badgeFg = isLocal
        ? FsColors.accentHi
        : isS3
            ? FsColors.amber
            : FsColors.badgeRemoteFg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        _endpointPicker(pane, left: left, badgeBg: badgeBg, badgeFg: badgeFg),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: 'Click to copy this location',
            waitDuration: const Duration(milliseconds: 500),
            child: GestureDetector(
              onTap: () => _copyLocation(pane.displayPath),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  height: 24,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: FsColors.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FsColors.border),
                  ),
                  child: Text(pane.displayPath,
                      overflow: TextOverflow.ellipsis, style: FsType.sans(size: 11, color: FsColors.text2)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _paneIconBtn(
          ref.read(bookmarksProvider.notifier).isBookmarked(pane.connection?.id, pane.path) ? '★' : '☆',
          onTap: () => _toggleBookmark(pane),
        ),
        const SizedBox(width: 4),
        Builder(builder: (ctx) => _paneIconBtn('▾', onTap: () => _showQuickJump(ctx, pane))),
        const SizedBox(width: 4),
        _paneIconBtn('📋', onTap: () => _copyLocation(pane.displayPath)),
        const SizedBox(width: 4),
        _paneIconBtn('↑', onTap: pane.goUp),
        const SizedBox(width: 4),
        _paneIconBtn('↺', onTap: pane.refresh),
      ]),
    );
  }

  Widget _endpointPicker(PaneController pane,
      {required bool left, required Color badgeBg, required Color badgeFg}) {
    final badge = pane.badge;
    final connections = ref.read(connectionsProvider).connections;
    return Container(
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Connection?>(
          value: pane.connection,
          isDense: true,
          dropdownColor: FsColors.bgPanel,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          borderRadius: BorderRadius.circular(8),
          icon: Icon(Icons.expand_more, size: 14, color: badgeFg),
          selectedItemBuilder: (context) => [
            _pickerLabel(badge, pane.endpointLabel, badgeFg),
            ...connections.map((c) => _pickerLabel(badge, c.name, badgeFg)),
          ],
          items: [
            DropdownMenuItem<Connection?>(value: null, child: _menuRow('🖥', 'Local')),
            ...connections.map((c) => DropdownMenuItem<Connection?>(
                  value: c,
                  child: _menuRow(c.isS3 ? '🪣' : '🌐', c.name),
                )),
          ],
          onChanged: (c) => _sessions.setPaneEndpoint(left, c),
        ),
      ),
    );
  }

  Widget _pickerLabel(String badge, String name, Color fg) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(badge, style: FsType.sans(size: 10, weight: FontWeight.w700, color: fg)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(name, overflow: TextOverflow.ellipsis, style: FsType.sans(size: 11, color: fg)),
          ),
        ]),
      );

  Widget _menuRow(String glyph, String name) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(glyph, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text(name, style: FsType.sans(size: 12, color: FsColors.text1)),
      ]);

  Widget _paneIconBtn(String glyph, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FsColors.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FsColors.border),
            ),
            child: Text(glyph, style: FsType.sans(size: 11, color: FsColors.text2)),
          ),
        ),
      );

  Widget _breadcrumb(List<String> segs) {
    final children = <Widget>[];
    for (var i = 0; i < segs.length; i++) {
      final active = i == segs.length - 1;
      children.add(Flexible(
        child: Text(segs[i],
            overflow: TextOverflow.ellipsis,
            style: FsType.sans(
                size: 11,
                color: active ? FsColors.text1 : FsColors.text2,
                weight: active ? FontWeight.w600 : FontWeight.w400)),
      ));
      if (i < segs.length - 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('›', style: FsType.sans(size: 11, color: FsColors.text3)),
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: children),
    );
  }

  // ── Pane body: placeholder / loading / error / table ──
  Widget _paneBody(PaneController pane, bool showPerms, {required bool left}) {
    if (!pane.isReady) {
      return _placeholder(
        icon: Icons.cloud_off_outlined,
        title: 'Not connected',
        message: 'Add Access Key, Secret & Bucket for\n${pane.endpointLabel} to browse this S3 endpoint.',
        actionLabel: 'Open Connection Manager',
        onAction: () {
          if (pane.connection != null) {
            ref.read(connectionsProvider.notifier).select(pane.connection!);
          }
          _go(AppScreen.connections);
        },
      );
    }
    if (pane.loading) {
      return Center(
        child: SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: FsColors.accent)),
      );
    }
    if (pane.error != null) {
      return _placeholder(
        icon: Icons.error_outline,
        title: 'Couldn\'t list files',
        message: pane.error!,
        actionLabel: 'Retry',
        onAction: pane.refresh,
      );
    }
    return _fileTable(pane, showPerms, left: left);
  }

  Widget _placeholder({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      color: FsColors.bgSurface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 34, color: FsColors.text3),
        const SizedBox(height: 12),
        Text(title, style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: FsType.sans(size: 12, color: FsColors.text2, height: 1.5)),
        const SizedBox(height: 16),
        FsButton(actionLabel, kind: FsButtonKind.primary, onTap: onAction),
      ]),
    );
  }

  Widget _paneFooter(PaneController pane) {
    final count = pane.items.where((f) => !f.isParent).length;
    final isLocal = pane.kind == EndpointKind.local;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: Text(
        pane.isReady ? '$count items · Drop files here to transfer${isLocal ? '' : ' · S3 bucket'}' : '—',
        style: FsType.sans(size: 10, color: FsColors.text3),
      ),
    );
  }

  // ── File table ──
  Widget _fileTable(PaneController pane, bool showPerms, {required bool left}) {
    return Container(
      color: FsColors.bgSurface,
      child: Column(children: [
        _tableHead(showPerms),
        Expanded(
          child: ListView.builder(
            itemCount: pane.items.length,
            itemBuilder: (context, i) {
              final f = pane.items[i];
              final selected = pane.isSelected(i);
              final row = _fileRow(pane, f, i, showPerms, left: left, selected: selected);
              if (!f.isDir) {
                return Draggable<DragPayload>(
                  data: DragPayload(f, left),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: _dragGhost(f, pane.isSelected(i) ? pane.selectedItems().length : 1),
                  onDragStarted: () {
                    _sessions.focusPane(left);
                    // Keep an existing multi-selection if this row is part of it.
                    if (!pane.isSelected(i)) pane.select(i);
                  },
                  childWhenDragging: Opacity(opacity: 0.4, child: row),
                  child: row,
                );
              }
              return row;
            },
          ),
        ),
      ]),
    );
  }

  Widget _tableHead(bool showPerms) {
    Widget cell(String t, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(t,
                textAlign: align,
                style: FsType.sans(size: 10, weight: FontWeight.w600, color: FsColors.text3, letterSpacing: 0.6)),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        cell('NAME', 40),
        cell('SIZE', 15, align: TextAlign.right),
        cell('MODIFIED', 25),
        if (showPerms) cell('PERMS', 20, align: TextAlign.right),
      ]),
    );
  }

  Widget _fileRow(PaneController pane, FileItem f, int index, bool showPerms,
      {required bool left, required bool selected}) {
    return Hoverable(builder: (hover) {
      Color bg = Colors.transparent;
      if (selected) {
        bg = FsColors.bgActive;
      } else if (hover) {
        bg = FsColors.bgHover;
      }
      final nameColor = f.isDir ? FsColors.accentHi : FsColors.text1;
      return GestureDetector(
        onTap: () {
          _sessions.focusPane(left);
          final kb = HardwareKeyboard.instance;
          if (kb.isControlPressed || kb.isMetaPressed) {
            pane.toggleSelect(index);
          } else if (kb.isShiftPressed) {
            pane.selectRange(index);
          } else {
            pane.select(index);
          }
        },
        onDoubleTap: (f.isDir || f.isParent) ? () => pane.open(f) : null,
        onSecondaryTapDown: f.isParent
            ? null
            : (d) {
                _sessions.focusPane(left);
                // Preserve a multi-selection if right-clicking inside it.
                if (!pane.isSelected(index)) pane.select(index);
                _showRowMenu(pane, left, f, d.globalPosition);
              },
        child: MouseRegion(
          cursor: f.isDir ? SystemMouseCursors.click : SystemMouseCursors.grab,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              border: Border(bottom: BorderSide(color: FsColors.border)),
            ),
            child: Row(children: [
              Expanded(
                flex: 40,
                child: Row(children: [
                  _compareDot(pane, f),
                  Text(f.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: f.name,
                      waitDuration: const Duration(milliseconds: 500),
                      child: Text(f.name, overflow: TextOverflow.ellipsis, style: FsType.sans(size: 12, color: nameColor)),
                    ),
                  ),
                ]),
              ),
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(f.sizeLabel, textAlign: TextAlign.right, style: FsType.sans(size: 11, color: FsColors.text2, tabular: true)),
                ),
              ),
              Expanded(flex: 25, child: Text(f.modified, style: FsType.sans(size: 11, color: FsColors.text2, tabular: true))),
              if (showPerms)
                Expanded(
                  flex: 20,
                  child: Text(f.perms, textAlign: TextAlign.right, style: FsType.sans(size: 10, color: FsColors.text3)),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _dragGhost(FileItem f, int count) {
    final label = count > 1 ? '$count items' : '${f.name}  ·  ${f.sizeLabel}';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: FsColors.bgActive,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FsColors.accent, width: 2),
          boxShadow: [BoxShadow(color: FsColors.accent.withValues(alpha: 0.3), blurRadius: 24)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(count > 1 ? '📦' : f.icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(label, style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.accentHi)),
        ]),
      ),
    );
  }

  // ── Transfer queue strip ──
  Widget _queueStrip() {
    // Watch only the transfer queue here so status changes update the strip
    // without rebuilding the file tables above.
    return Consumer(builder: (context, ref, _) {
      final state = ref.watch(transfersProvider);
      final active = state.transfers.where((t) => t.status == TransferStatus.active).toList();
      final current = active.isNotEmpty ? active.first : null;
      return _queueStripBody(state, current);
    });
  }

  Widget _queueStripBody(TransfersState state, Transfer? current) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        StatusDot(current != null ? FsColors.green : FsColors.text3, glow: current != null),
        const SizedBox(width: 8),
        Flexible(
          child: Text(current != null ? 'Transferring — ${current.name}' : 'Idle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FsType.sans(size: 11, color: FsColors.text2)),
        ),
        const SizedBox(width: 10),
        if (current != null)
          // Live progress repaints here only — not the whole browser pane.
          ValueListenableBuilder<int>(
            valueListenable: current.liveTick,
            builder: (context, _, _) => Row(children: [
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: current.progress,
                    minHeight: 4,
                    backgroundColor: FsColors.bgPanel,
                    valueColor: AlwaysStoppedAnimation(FsColors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(current.progress * 100).round()}% · ${current.speed}',
                  style: FsType.sans(size: 10, color: FsColors.accentHi, tabular: true)),
            ]),
          ),
        const Spacer(),
        Text('${state.queuedCount} remaining', style: FsType.sans(size: 11, color: FsColors.text2)),
        const SizedBox(width: 10),
        FsButton('Pause all', fontSize: 10, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), onTap: () => ref.read(transfersProvider.notifier).pauseAll()),
        const SizedBox(width: 6),
        FsButton('View queue', fontSize: 10, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), onTap: () => _go(AppScreen.queue)),
      ]),
    );
  }

  // ── SFTP / activity log console ──
  Widget _logPanel() {
    Widget line(String marker, Color markerColor, String msg) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(marker, style: FsType.mono(size: 10, color: markerColor)),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: FsType.mono(size: 10, color: FsColors.text3))),
          ]),
        );
    return Container(
      height: 96,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          line('»', FsColors.accent, 'Drag files between panes to transfer (Local ⇄ S3, S3 ⇄ S3, SFTP).'),
          line('✓', FsColors.green, 'Local endpoint ready'),
          line('»', FsColors.accent, 'Select an S3 or SFTP endpoint in either pane to browse it'),
          line('ℹ', FsColors.accentHi, 'Add credentials in Connection Manager to connect'),
        ]),
      ),
    );
  }
}
