import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  double _split = 0.5; // local/remote split fraction
  bool _dropHover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(
      children: [
        _sessionTabs(),
        _toolbar(app),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final leftW = (c.maxWidth - 5) * _split;
            return Row(
              children: [
                SizedBox(width: leftW, child: _localPane(app)),
                _divider(c.maxWidth),
                Expanded(child: _remotePane(app)),
              ],
            );
          }),
        ),
        _queueStrip(app),
        _logPanel(),
      ],
    );
  }

  // ── Session tabs ──
  Widget _sessionTabs() {
    Widget tab(String name, Color dot, {bool active = false, bool muted = false}) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: active ? FsColors.accent : Colors.transparent, width: 2),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusDot(dot, glow: dot == FsColors.green),
          const SizedBox(width: 7),
          Text(name,
              style: FsType.sans(
                  size: 12, color: active ? FsColors.accentHi : (muted ? FsColors.text3 : FsColors.text2))),
          const SizedBox(width: 8),
          Icon(Icons.close, size: 11, color: FsColors.text3),
        ]),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        tab('prod-server-01', FsColors.green, active: true),
        tab('staging-db', FsColors.amber),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('＋', style: FsType.sans(size: 13, color: FsColors.text3)),
        ),
      ]),
    );
  }

  // ── Toolbar ──
  Widget _toolbar(AppState app) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        const ToolButton('← Back'),
        const ToolButton('→ Fwd'),
        const ToolButton('↑ Up'),
        const ToolSep(),
        const ToolButton('⇄ Sync', active: true),
        ToolButton('↯ Queue', onTap: () => app.go(AppScreen.queue)),
        const ToolButton('📋 Log'),
        const ToolSep(),
        const ToolButton('⊕ New Folder'),
        const ToolButton('✎ Rename'),
        const ToolButton('⊗ Delete', color: FsColors.red),
        const Spacer(),
        Text('Filter:', style: FsType.sans(size: 10, color: FsColors.text3)),
        const SizedBox(width: 6),
        const FsTextField(hint: '*.log, *.conf…', width: 130, height: 26),
      ]),
    );
  }

  // ── Resizable divider ──
  Widget _divider(double totalW) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) {
          setState(() => _split = (_split + d.delta.dx / totalW).clamp(0.25, 0.75));
        },
        child: Container(width: 5, color: FsColors.border),
      ),
    );
  }

  // ── Pane header ──
  Widget _paneHeader({required bool local, required String path}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: FsColors.bgPanel,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: local ? FsColors.badgeLocalBg : FsColors.badgeRemoteBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(local ? 'LOCAL' : 'REMOTE',
              style: FsType.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: local ? FsColors.accentHi : FsColors.badgeRemoteFg)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 24,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FsColors.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FsColors.border),
            ),
            child: Text(path,
                overflow: TextOverflow.ellipsis, style: FsType.mono(size: 11, color: FsColors.text2)),
          ),
        ),
        const SizedBox(width: 6),
        _paneIconBtn('⊞'),
        const SizedBox(width: 4),
        _paneIconBtn('↺'),
      ]),
    );
  }

  Widget _paneIconBtn(String glyph) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FsColors.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FsColors.border),
        ),
        child: Text(glyph, style: FsType.sans(size: 11, color: FsColors.text2)),
      );

  Widget _breadcrumb(List<String> segs) {
    final children = <Widget>[];
    for (var i = 0; i < segs.length; i++) {
      final active = i == segs.length - 1;
      children.add(Text(segs[i],
          style: FsType.mono(
              size: 11,
              color: active ? FsColors.text1 : FsColors.text2,
              weight: active ? FontWeight.w600 : FontWeight.w400)));
      if (i < segs.length - 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('›', style: FsType.mono(size: 11, color: FsColors.text3)),
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: children),
    );
  }

  // ── Local pane (draggable rows) ──
  Widget _localPane(AppState app) {
    return Column(
      children: [
        _paneHeader(local: true, path: app.localPath),
        _breadcrumb(const ['~', 'projects', 'backend']),
        Expanded(child: _fileTable(app, app.local, local: true)),
        _paneFooter('${app.local.length - 1} items · ${app.selectedLocalIndex != null ? "1 selected" : "0 selected"} · Free: 128.4 GB'),
      ],
    );
  }

  // ── Remote pane (drop target) ──
  Widget _remotePane(AppState app) {
    return DragTarget<FileItem>(
      onWillAcceptWithDetails: (_) {
        setState(() => _dropHover = true);
        return true;
      },
      onLeave: (_) => setState(() => _dropHover = false),
      onAcceptWithDetails: (d) {
        setState(() => _dropHover = false);
        app.uploadFile(d.data);
      },
      builder: (context, candidate, rejected) {
        return Container(
          decoration: BoxDecoration(
            color: _dropHover ? FsColors.accent.withValues(alpha: 0.06) : null,
            border: _dropHover
                ? Border.all(color: FsColors.accent, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              _paneHeader(local: false, path: app.remotePath),
              _breadcrumb(const ['/', 'var', 'www', 'app']),
              Expanded(child: _fileTable(app, app.remote, local: false)),
              _paneFooter('${app.remote.length - 1} items · Drop files here to upload · Free: 44.2 GB'),
            ],
          ),
        );
      },
    );
  }

  Widget _paneFooter(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: const BoxDecoration(
          color: FsColors.bgDeep,
          border: Border(top: BorderSide(color: FsColors.border)),
        ),
        child: Text(text, style: FsType.sans(size: 10, color: FsColors.text3)),
      );

  // ── File table ──
  Widget _fileTable(AppState app, List<FileItem> files, {required bool local}) {
    return Container(
      color: FsColors.bgSurface,
      child: Column(
        children: [
          _tableHead(),
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, i) {
                final f = files[i];
                final selected = local && app.selectedLocalIndex == i;
                final row = _fileRow(app, f, i, local: local, selected: selected);
                // Local non-directory files are draggable to the remote pane.
                if (local && !f.isDir) {
                  return Draggable<FileItem>(
                    data: f,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: _dragGhost(f),
                    onDragStarted: () => app.selectLocal(i),
                    childWhenDragging: Opacity(opacity: 0.4, child: row),
                    child: row,
                  );
                }
                return row;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHead() {
    Widget cell(String t, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(t,
                textAlign: align,
                style: FsType.sans(
                    size: 10, weight: FontWeight.w600, color: FsColors.text3, letterSpacing: 0.6)),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(bottom: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        cell('NAME', 40),
        cell('SIZE', 15, align: TextAlign.right),
        cell('MODIFIED', 25),
        cell('PERMS', 20, align: TextAlign.right),
      ]),
    );
  }

  Widget _fileRow(AppState app, FileItem f, int index, {required bool local, required bool selected}) {
    return Hoverable(builder: (hover) {
      Color bg = Colors.transparent;
      if (selected) {
        bg = FsColors.bgActive;
      } else if (hover) {
        bg = FsColors.bgHover;
      }
      final nameColor = f.isDir ? FsColors.accentHi : (selected ? FsColors.text1 : FsColors.text1);
      return GestureDetector(
        onTap: local ? () => app.selectLocal(index) : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              border: const Border(bottom: BorderSide(color: Color(0x802A3550))),
            ),
            child: Row(children: [
              Expanded(
                flex: 40,
                child: Row(children: [
                  Text(f.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(f.name,
                        overflow: TextOverflow.ellipsis,
                        style: FsType.sans(size: 12, color: nameColor)),
                  ),
                ]),
              ),
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(f.sizeLabel,
                      textAlign: TextAlign.right, style: FsType.mono(size: 11, color: FsColors.text2)),
                ),
              ),
              Expanded(
                flex: 25,
                child: Text(f.modified, style: FsType.mono(size: 11, color: FsColors.text2)),
              ),
              Expanded(
                flex: 20,
                child: Text(f.perms,
                    textAlign: TextAlign.right, style: FsType.mono(size: 10, color: FsColors.text3)),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _dragGhost(FileItem f) {
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
          Text(f.icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text('${f.name}  ·  ${f.sizeLabel}',
              style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.accentHi)),
        ]),
      ),
    );
  }

  // ── Transfer queue strip ──
  Widget _queueStrip(AppState app) {
    final active = app.transfers.where((t) => t.status.name == 'active').toList();
    final current = active.isNotEmpty ? active.first : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: Row(children: [
        const StatusDot(FsColors.green, glow: true),
        const SizedBox(width: 8),
        Text(current != null ? 'Transferring — ${current.name}' : 'Idle',
            style: FsType.sans(size: 11, color: FsColors.text2)),
        const SizedBox(width: 10),
        if (current != null) ...[
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: current.progress,
                minHeight: 4,
                backgroundColor: FsColors.bgPanel,
                valueColor: const AlwaysStoppedAnimation(FsColors.accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${(current.progress * 100).round()}% · ${current.speed}',
              style: FsType.mono(size: 10, color: FsColors.accentHi)),
        ],
        const Spacer(),
        Text('${app.queuedCount} remaining', style: FsType.sans(size: 11, color: FsColors.text2)),
        const SizedBox(width: 10),
        FsButton('Pause all',
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            onTap: app.pauseAll),
        const SizedBox(width: 6),
        FsButton('View queue',
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            onTap: () => app.go(AppScreen.queue)),
      ]),
    );
  }

  // ── SFTP log console ──
  Widget _logPanel() {
    Widget line(String time, String marker, Color markerColor, String msg) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(time, style: FsType.mono(size: 10, color: FsColors.text3)),
            const SizedBox(width: 10),
            Text(marker, style: FsType.mono(size: 10, color: markerColor)),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: FsType.mono(size: 10, color: FsColors.text3))),
          ]),
        );
    return Container(
      height: 96,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FsColors.bgDeep,
        border: Border(top: BorderSide(color: FsColors.border)),
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          line('08:14:02', '»', FsColors.accent, 'Connected to prod-server-01 (OpenSSH 9.3, protocol 2.0)'),
          line('08:14:03', '✓', FsColors.green, 'Authentication successful (publickey)'),
          line('08:14:05', '»', FsColors.accent, 'PUT config.yaml → /var/www/app/config.yaml (4,096 bytes)'),
          line('08:14:06', '✕', FsColors.red, 'Permission denied: /var/www/app/.env (read-only)'),
          line('08:14:07', '»', FsColors.accent, 'PUT deploy.sh → /var/www/app/deploy.sh …'),
        ]),
      ),
    );
  }
}
