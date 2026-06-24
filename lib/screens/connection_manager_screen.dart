import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ConnectionManagerScreen extends ConsumerWidget {
  const ConnectionManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionsProvider);
    final selected = state.selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 220, child: _sidebar(ref, state)),
        const VerticalDivider(width: 1, color: FsColors.border),
        Expanded(
          child: selected == null
              ? _emptyState(ref)
              : ConnectionForm(key: ObjectKey(selected), connection: selected),
        ),
      ],
    );
  }

  Widget _emptyState(WidgetRef ref) {
    return Container(
      color: FsColors.bgSurface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lan_outlined, size: 36, color: FsColors.text3),
        const SizedBox(height: 12),
        Text('No connections yet',
            style: FsType.sans(size: 14, weight: FontWeight.w600, color: FsColors.text1)),
        const SizedBox(height: 6),
        Text('Add a real SFTP or Amazon S3 endpoint to get started.',
            textAlign: TextAlign.center, style: FsType.sans(size: 12, color: FsColors.text2, height: 1.5)),
        const SizedBox(height: 16),
        FsButton('＋ New Connection',
            kind: FsButtonKind.primary,
            onTap: () => ref.read(connectionsProvider.notifier).create()),
      ]),
    );
  }

  // ── Saved sessions sidebar ──
  Widget _sidebar(WidgetRef ref, ConnectionsState state) {
    Widget groupLabel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(t,
              style: FsType.sans(size: 10, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1)),
        );

    Widget connItem(Connection c) {
      final active = identical(c, state.selected);
      return Hoverable(builder: (hover) {
        return GestureDetector(
          onTap: () => ref.read(connectionsProvider.notifier).select(c),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: active ? FsColors.bgActive : (hover ? FsColors.bgHover : Colors.transparent),
              child: Row(children: [
                StatusDot(c.online ? FsColors.green : FsColors.text3, glow: c.online),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis,
                      style: FsType.sans(
                          size: 12, color: active ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2))),
                ),
                if (c.isS3) Text('S3', style: FsType.sans(size: 9, weight: FontWeight.w700, color: FsColors.amber)),
              ]),
            ),
          ),
        );
      });
    }

    final recent = state.connections.where((c) => c.group == ConnGroup.recent).toList();
    final saved = state.connections.where((c) => c.group == ConnGroup.saved).toList();

    return Container(
      color: FsColors.bgDeep,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: FsTextField(hint: 'Search sessions…', mono: false, height: 28),
        ),
        Expanded(
          child: state.connections.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No saved connections',
                        textAlign: TextAlign.center,
                        style: FsType.sans(size: 11, color: FsColors.text3)),
                  ),
                )
              : ListView(padding: EdgeInsets.zero, children: [
                  if (recent.isNotEmpty) groupLabel('RECENT'),
                  ...recent.map(connItem),
                  if (saved.isNotEmpty) groupLabel('SAVED'),
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
                onTap: () => ref.read(connectionsProvider.notifier).create()),
          ),
        ),
      ]),
    );
  }
}

/// Editable detail form. Stateful so credential text survives rebuilds (toasts,
/// transfers) — a fresh State is created per connection via the [ObjectKey].
class ConnectionForm extends ConsumerStatefulWidget {
  final Connection connection;
  const ConnectionForm({super.key, required this.connection});

  @override
  ConsumerState<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends ConsumerState<ConnectionForm> {
  Connection get c => widget.connection;

  late final _host = TextEditingController(text: c.host);
  late final _port = TextEditingController(text: '${c.port}');
  late final _user = TextEditingController(text: c.username);
  late final _timeout = TextEditingController(text: '${c.timeout}');
  late final _keyFile = TextEditingController(text: c.keyFile);
  late final _passphrase = TextEditingController(text: c.passphrase);
  late final _password = TextEditingController(text: c.password);
  late final _remotePath = TextEditingController(text: c.remotePath);
  late final _localPath = TextEditingController(text: c.localPath);

  late final _region = TextEditingController(text: c.region);
  late final _bucket = TextEditingController(text: c.bucket);
  late final _endpoint = TextEditingController(text: c.endpoint);
  late final _akid = TextEditingController(text: c.accessKeyId);
  late final _secret = TextEditingController(text: c.secretAccessKey);
  late final _token = TextEditingController(text: c.sessionToken);

  void _toast(String t, String s, ToastKind k) => ref.read(toastsProvider.notifier).push(t, s, k);

  @override
  void dispose() {
    for (final ctl in [_host, _port, _user, _timeout, _keyFile, _passphrase, _password, _remotePath, _localPath, _region, _bucket, _endpoint, _akid, _secret, _token]) {
      ctl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

        FormField2('Protocol', _protocolSelect()),
        const SizedBox(height: 16),

        if (c.isS3) ..._s3Fields() else ..._sshFields(),

        const SizedBox(height: 18),
        Row(children: [
          FsButton('⚡ Connect',
              kind: FsButtonKind.primary,
              onTap: () => ref.read(sessionsProvider.notifier).connect(c)),
          const SizedBox(width: 10),
          FsButton('💾 Save', onTap: () {
            ref.read(connectionsProvider.notifier).save(c);
            _toast('Saved', '${c.name} configuration stored', ToastKind.success);
          }),
          const SizedBox(width: 10),
          FsButton('⧉ Duplicate', onTap: () => ref.read(connectionsProvider.notifier).duplicate(c)),
          const Spacer(),
          FsButton('⊗ Delete',
              kind: FsButtonKind.danger,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () {
                ref.read(connectionsProvider.notifier).delete(c);
                _toast('Deleted', '${c.name} removed', ToastKind.info);
              }),
        ]),
      ]),
    );
  }

  // ── S3 credential fields ──
  List<Widget> _s3Fields() {
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: FormField2('Region', _field(_region, (v) => c.region = v, hint: 'us-east-1'))),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: FormField2('Bucket', _field(_bucket, (v) => c.bucket = v, hint: 'my-bucket'))),
      ]),
      const SizedBox(height: 12),
      FormField2('Endpoint (optional — for S3-compatible / MinIO)',
          _field(_endpoint, (v) => c.endpoint = v, hint: 's3.amazonaws.com')),
      const SizedBox(height: 12),
      FormField2('Access Key ID', _field(_akid, (v) => c.accessKeyId = v, hint: 'AKIA…')),
      const SizedBox(height: 12),
      FormField2('Secret Access Key', _field(_secret, (v) => c.secretAccessKey = v, obscure: true, hint: '••••••••')),
      const SizedBox(height: 12),
      FormField2('Session Token (optional)', _field(_token, (v) => c.sessionToken = v, obscure: true, hint: 'For temporary STS credentials')),
      const SizedBox(height: 14),
      _checkRow('Use SSL (HTTPS)', c.useSsl, (v) => setState(() => c.useSsl = v)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: FsColors.bgPanel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FsColors.border),
        ),
        child: Row(children: [
          const Text('🪣', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cross-account copies are streamed: pick this bucket in one pane and another account\'s bucket in the other, then drag between them.',
              style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4),
            ),
          ),
        ]),
      ),
    ];
  }

  // ── SSH / SFTP fields ──
  List<Widget> _sshFields() {
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: FormField2('Hostname / IP', _field(_host, (v) => c.host = v))),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: FormField2('Port', _field(_port, (v) => c.port = int.tryParse(v) ?? c.port))),
        const SizedBox(width: 12),
        Expanded(child: FormField2('Username', _field(_user, (v) => c.username = v))),
        const SizedBox(width: 12),
        Expanded(child: FormField2('Timeout (s)', _field(_timeout, (v) => c.timeout = int.tryParse(v) ?? c.timeout))),
      ]),
      const SizedBox(height: 16),
      Text('Authentication', style: FsType.sans(size: 11, weight: FontWeight.w600, color: FsColors.text2)),
      const SizedBox(height: 8),
      _authTabs(),
      const SizedBox(height: 16),
      if (c.auth == AuthMethod.password)
        FormField2('Password', _field(_password, (v) => c.password = v, obscure: true, hint: '••••••••'))
      else ...[
        FormField2(
          'Key file',
          Row(children: [
            Expanded(child: _field(_keyFile, (v) => c.keyFile = v, hint: '~/.ssh/id_rsa')),
            const SizedBox(width: 6),
            FsButton('Browse…', fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ]),
        ),
        const SizedBox(height: 12),
        FormField2('Passphrase', _field(_passphrase, (v) => c.passphrase = v, obscure: true, hint: 'Leave blank if none')),
      ],
      const SizedBox(height: 12),
      FormField2('Remote start path', _field(_remotePath, (v) => c.remotePath = v)),
      const SizedBox(height: 12),
      FormField2('Local start path', _field(_localPath, (v) => c.localPath = v, hint: '~')),
      const SizedBox(height: 14),
      _checkRow('Keep session alive (heartbeat every 30s)', c.keepAlive, (v) => setState(() => c.keepAlive = v)),
      const SizedBox(height: 6),
      _checkRow('Open in new tab', c.openInNewTab, (v) => setState(() => c.openInNewTab = v)),
    ];
  }

  Widget _field(TextEditingController ctl, ValueChanged<String> onChanged, {bool obscure = false, String? hint}) {
    return FsTextField(controller: ctl, obscure: obscure, hint: hint, onChanged: onChanged);
  }

  Widget _protocolSelect() {
    return Container(
      height: 32,
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FsColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FsColors.border),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Protocol>(
          value: c.protocol,
          isDense: true,
          isExpanded: true,
          dropdownColor: FsColors.bgPanel,
          icon: const Icon(Icons.expand_more, size: 16, color: FsColors.text2),
          style: FsType.sans(size: 12, color: FsColors.text1),
          items: Protocol.values
              .map((p) => DropdownMenuItem(
                  value: p, child: Text(p == Protocol.s3 ? 'S3 (Amazon S3)' : p.label)))
              .toList(),
          onChanged: (p) {
            if (p != null) {
              setState(() => c.protocol = p);
              ref.read(connectionsProvider.notifier).select(c);
            }
          },
        ),
      ),
    );
  }

  Widget _authTabs() {
    final methods = AuthMethod.values;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: FsColors.border), borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final m in methods)
            GestureDetector(
              onTap: () => setState(() => c.auth = m),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: m == c.auth ? FsColors.bgActive : Colors.transparent,
                  child: Text(m.label,
                      style: FsType.sans(
                          size: 11, weight: FontWeight.w600, color: m == c.auth ? FsColors.accentHi : FsColors.text2)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _checkRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(children: [
      SizedBox(
        width: 18,
        height: 18,
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
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
