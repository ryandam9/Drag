import 'package:flutter/material.dart';
import '../models/connection.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ConnectionManagerScreen extends StatelessWidget {
  const ConnectionManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 220, child: _sidebar(app)),
        const VerticalDivider(width: 1, color: FsColors.border),
        Expanded(child: _form(context, app)),
      ],
    );
  }

  // ── Saved sessions sidebar ──
  Widget _sidebar(AppState app) {
    Widget groupLabel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(t,
              style: FsType.sans(
                  size: 10, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1)),
        );

    Widget connItem(Connection c) {
      final active = identical(c, app.selectedConnection);
      return Hoverable(builder: (hover) {
        return GestureDetector(
          onTap: () => app.selectConnection(c),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: active ? FsColors.bgActive : (hover ? FsColors.bgHover : Colors.transparent),
              child: Row(children: [
                StatusDot(c.online ? FsColors.green : FsColors.text3, glow: c.online),
                const SizedBox(width: 8),
                Text(c.name,
                    style: FsType.sans(
                        size: 12, color: active ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2))),
              ]),
            ),
          ),
        );
      });
    }

    final recent = app.connections.where((c) => c.group == ConnGroup.recent).toList();
    final saved = app.connections.where((c) => c.group == ConnGroup.saved).toList();

    return Container(
      color: FsColors.bgDeep,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: FsTextField(hint: 'Search sessions…', mono: false, height: 28),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            groupLabel('RECENT'),
            ...recent.map(connItem),
            groupLabel('SAVED'),
            ...saved.map(connItem),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FsButton('＋ New Connection',
                fontSize: 11,
                padding: const EdgeInsets.symmetric(vertical: 7),
                onTap: () => app.pushToast('New connection', 'Fill in the form to create one', ToastKind.info)),
          ),
        ),
      ]),
    );
  }

  // ── Detail / quick-connect form ──
  Widget _form(BuildContext context, AppState app) {
    final c = app.selectedConnection;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: FsType.sans(size: 15, weight: FontWeight.w600, color: FsColors.text1)),
        const SizedBox(height: 4),
        Text(
          [if (c.lastConnected.isNotEmpty) c.lastConnected, if (c.details.isNotEmpty) c.details].join(' · '),
          style: FsType.sans(size: 12, color: FsColors.text2),
        ),
        const SizedBox(height: 20),

        // Protocol + hostname.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: FormField2('Protocol', _select(c.protocol.label, Protocol.values.map((p) => p.label).toList())),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: FormField2('Hostname / IP', FsTextField(value: c.host))),
        ]),
        const SizedBox(height: 16),

        // Port + username + timeout.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: FormField2('Port', FsTextField(value: '${c.port}'))),
          const SizedBox(width: 12),
          Expanded(child: FormField2('Username', FsTextField(value: c.username))),
          const SizedBox(width: 12),
          Expanded(child: FormField2('Timeout (s)', FsTextField(value: '${c.timeout}'))),
        ]),
        const SizedBox(height: 16),

        Text('Authentication',
            style: FsType.sans(size: 11, weight: FontWeight.w600, color: FsColors.text2)),
        const SizedBox(height: 8),
        _authTabs(c),
        const SizedBox(height: 16),

        FormField2(
          'Key file',
          Row(children: [
            Expanded(child: FsTextField(value: c.keyFile.isEmpty ? '~/.ssh/id_rsa' : c.keyFile)),
            const SizedBox(width: 6),
            FsButton('Browse…', fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ]),
        ),
        const SizedBox(height: 12),
        const FormField2('Passphrase', FsTextField(hint: 'Leave blank if none', obscure: true)),
        const SizedBox(height: 12),
        FormField2('Remote start path', FsTextField(value: c.remotePath)),
        const SizedBox(height: 12),
        FormField2('Local start path', FsTextField(value: c.localPath.isEmpty ? '~' : c.localPath)),
        const SizedBox(height: 14),

        _checkRow('Keep session alive (heartbeat every 30s)', c.keepAlive),
        const SizedBox(height: 6),
        _checkRow('Open in new tab', c.openInNewTab),
        const SizedBox(height: 18),

        Row(children: [
          FsButton('⚡ Connect',
              kind: FsButtonKind.primary,
              onTap: () {
                c.online = true;
                app.pushToast('Session connected', '${c.name} · ${c.protocol.label} · 22ms', ToastKind.info);
                app.go(AppScreen.browser);
              }),
          const SizedBox(width: 10),
          FsButton('💾 Save', onTap: () => app.pushToast('Saved', '${c.name} configuration stored', ToastKind.success)),
          const SizedBox(width: 10),
          const FsButton('⧉ Duplicate'),
          const Spacer(),
          const FsButton('⊗ Delete',
              kind: FsButtonKind.danger,
              fontSize: 11,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        ]),
      ]),
    );
  }

  Widget _authTabs(Connection c) {
    final methods = AuthMethod.values;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: FsColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in methods)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                color: m == c.auth ? FsColors.bgActive : Colors.transparent,
                child: Text(m.label,
                    style: FsType.sans(
                        size: 11,
                        weight: FontWeight.w600,
                        color: m == c.auth ? FsColors.accentHi : FsColors.text2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _select(String value, List<String> options) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FsColors.border),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: FsColors.bgPanel,
          icon: const Icon(Icons.expand_more, size: 16, color: FsColors.text2),
          style: FsType.sans(size: 12, color: FsColors.text1),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (_) {},
        ),
      ),
    );
  }

  Widget _checkRow(String label, bool value) {
    return Row(children: [
      SizedBox(
        width: 18,
        height: 18,
        child: Checkbox(
          value: value,
          onChanged: (_) {},
          activeColor: FsColors.accent,
          side: const BorderSide(color: FsColors.border),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 10),
      Text(label, style: FsType.sans(size: 12, color: FsColors.text2)),
    ]);
  }
}
