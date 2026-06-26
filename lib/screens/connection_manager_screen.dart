import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection.dart';
import '../state/app.dart';
import '../state/connection_filter.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ConnectionManagerScreen extends ConsumerStatefulWidget {
  const ConnectionManagerScreen({super.key});

  @override
  ConsumerState<ConnectionManagerScreen> createState() => _ConnectionManagerScreenState();
}

class _ConnectionManagerScreenState extends ConsumerState<ConnectionManagerScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionsProvider);
    final selected = state.selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 220, child: _sidebar(ref, state)),
        VerticalDivider(width: 1, color: FsColors.border),
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
      color: FsColors.bgScaffold,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: FsColors.bgSurface,
          borderRadius: BorderRadius.circular(FsColors.rCard),
          border: Border.all(color: FsColors.border),
          boxShadow: FsColors.cardShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: FsColors.bgActive,
              borderRadius: BorderRadius.circular(FsColors.rCard),
            ),
            child: Icon(Icons.lan_outlined, size: 30, color: FsColors.accentHi),
          ),
          const SizedBox(height: 18),
          Text('No connections yet',
              style: FsType.sans(size: 20, weight: FontWeight.w700, color: FsColors.text1)),
          const SizedBox(height: 8),
          Text('Add a real SFTP or Amazon S3 endpoint to get started.',
              textAlign: TextAlign.center, style: FsType.sans(size: 13, color: FsColors.text2, height: 1.5)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.read(connectionsProvider.notifier).create(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Connection'),
          ),
        ]),
      ),
    );
  }

  Widget _sidebarNote(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text,
              textAlign: TextAlign.center, style: FsType.sans(size: 11, color: FsColors.text3)),
        ),
      );

  // ── Saved sessions sidebar ──
  Widget _sidebar(WidgetRef ref, ConnectionsState state) {
    Widget groupLabel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
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
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: active ? FsColors.bgActive : (hover ? FsColors.bgHover : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? FsColors.bgSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: StatusDot(c.online ? FsColors.green : FsColors.text3, glow: c.online),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      style: FsType.sans(
                          size: 12.5,
                          weight: active ? FontWeight.w600 : FontWeight.w400,
                          color: active ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2))),
                ),
                if (c.isS3) Text('S3', style: FsType.sans(size: 9, weight: FontWeight.w700, color: FsColors.amber)),
              ]),
            ),
          ),
        );
      });
    }

    // Live search filter, then group by user tag (untagged last).
    final groups = groupConnections(filterConnections(state.connections, _query));

    Widget body;
    if (state.connections.isEmpty) {
      body = _sidebarNote('No saved connections');
    } else if (groups.isEmpty) {
      body = _sidebarNote('No matches for “${_query.trim()}”');
    } else {
      body = ListView(padding: EdgeInsets.zero, children: [
        for (final g in groups) ...[
          groupLabel(g.label.toUpperCase()),
          ...g.items.map(connItem),
        ],
      ]);
    }

    return Container(
      color: FsColors.bgDeep,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
          child: FsTextField(
            controller: _search,
            hint: 'Search sessions…',
            mono: false,
            height: 34,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(child: body),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => ref.read(connectionsProvider.notifier).create(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Connection'),
            ),
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

  /// Obscured fields (password / secret / token / passphrase) whose contents
  /// the user has chosen to reveal via the eye toggle.
  final Set<TextEditingController> _revealed = {};

  late final _name = TextEditingController(text: c.name);
  late final _tag = TextEditingController(text: c.tag);
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
  late final _awsProfile = TextEditingController(text: c.awsProfile);
  late final _roleArn = TextEditingController(text: c.assumeRoleArn);
  late final _roleSession = TextEditingController(text: c.roleSessionName);

  // Clears the placeholder name when the field is focused, so the user can type
  // straight away instead of deleting "New connection" first.
  late final FocusNode _nameFocus = FocusNode()
    ..addListener(() {
      if (_nameFocus.hasFocus && _name.text.trim() == 'New connection') {
        _name.clear();
        c.name = '';
        ref.read(connectionsProvider.notifier).touch();
      }
    });

  void _toast(String t, String s, ToastKind k) => ref.read(toastsProvider.notifier).push(t, s, k);

  /// Open the OS file picker to choose an SSH private-key file, writing the
  /// chosen path into the Key file field.
  Future<void> _browseKeyFile() async {
    try {
      final file = await openFile(confirmButtonText: 'Select');
      final path = file?.path;
      if (path == null || path.isEmpty) return; // cancelled
      setState(() {
        _keyFile.text = path;
        c.keyFile = path;
      });
      ref.read(connectionsProvider.notifier).touch();
    } catch (e) {
      _toast('Couldn\'t open file picker', e.toString(), ToastKind.error);
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    for (final ctl in [_name, _tag, _host, _port, _user, _timeout, _keyFile, _passphrase, _password, _remotePath, _localPath, _region, _bucket, _endpoint, _akid, _secret, _token, _awsProfile, _roleArn, _roleSession]) {
      ctl.dispose();
    }
    super.dispose();
  }

  /// White rounded card wrapper for grouping form sections.
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
        boxShadow: FsColors.cardShadow,
      ),
      child: child,
    );
  }

  /// Large section header: an icon + bold title.
  Widget _sectionTitle(String t, [IconData? icon]) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: FsColors.accentHi),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(t,
              overflow: TextOverflow.ellipsis,
              style: FsType.sans(size: 16, weight: FontWeight.w700, color: FsColors.text1)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    // Detail layout: form + connection log. Side-by-side when there's room,
    // stacked (log under the form) when the area is too narrow for two columns.
    return LayoutBuilder(builder: (context, cons) {
      final log = Container(
        color: FsColors.bgScaffold,
        padding: const EdgeInsets.all(20),
        child: _connectionLog(),
      );

      if (cons.maxWidth < 640) {
        return Column(
          children: [
            Expanded(child: _formColumn()),
            Divider(height: 1, color: FsColors.border),
            SizedBox(height: 220, child: log),
          ],
        );
      }

      // Cap the form so fields don't sprawl; the log gets the rest.
      final formWidth = (cons.maxWidth * 0.5).clamp(320.0, 720.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: formWidth, child: _formColumn()),
          VerticalDivider(width: 1, color: FsColors.border),
          Expanded(child: log),
        ],
      );
    });
  }

  /// True when the form is too narrow for side-by-side fields (set per build
  /// from the form's actual width); multi-field rows then stack vertically.
  bool _narrow = false;

  /// Lays [fields] in a Row of Expandeds when there's room, or stacks them in a
  /// Column when [_narrow] — so field rows never overflow on small windows.
  Widget _fieldRow(List<Widget> fields, {List<int>? flex}) {
    if (_narrow) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          fields[i],
        ],
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(flex: flex == null ? 1 : flex[i], child: fields[i]),
      ],
    ]);
  }

  Widget _formColumn() {
    return LayoutBuilder(builder: (context, cons) {
      _narrow = cons.maxWidth < 380;
      return SingleChildScrollView(
        padding: EdgeInsets.all(_narrow ? 16 : 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name.trim().isEmpty ? 'Unnamed connection' : c.name,
            style: FsType.sans(size: 22, weight: FontWeight.w700, color: FsColors.text1)),
        if (c.lastConnected.isNotEmpty || c.details.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [if (c.lastConnected.isNotEmpty) c.lastConnected, if (c.details.isNotEmpty) c.details].join(' · '),
            style: FsType.sans(size: 13, color: FsColors.text2),
          ),
        ],
        const SizedBox(height: 20),

        // ── General card: name + protocol ──
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('General', Icons.tune),
            const SizedBox(height: 16),
            FormField2('Connection name',
                _field(_name, (v) {
                  c.name = v;
                  // Refresh the header here and the sidebar list (same name shown).
                  ref.read(connectionsProvider.notifier).touch();
                }, hint: 'e.g. Prod SFTP, Data bucket', icon: Icons.badge_outlined, focusNode: _nameFocus)),
            const SizedBox(height: 16),
            FormField2('Group / tag (optional)',
                _field(_tag, (v) {
                  c.tag = v;
                  // Regroup the sidebar live as the tag changes.
                  ref.read(connectionsProvider.notifier).touch();
                }, hint: 'e.g. Production, Staging', icon: Icons.sell_outlined)),
            const SizedBox(height: 16),
            FormField2('Protocol', _protocolSelect()),
          ]),
        ),
        const SizedBox(height: 18),

        // ── Connection detail card ──
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: c.isS3 ? _s3Fields() : _sshFields()),
        ),
        const SizedBox(height: 18),

        // M3 action buttons.
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () => ref.read(sessionsProvider.notifier).connect(c),
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Connect'),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.read(sessionsProvider.notifier).testConnection(c),
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Test'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(connectionsProvider.notifier).save(c);
              _toast('Saved', '${c.name} configuration stored', ToastKind.success);
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.read(connectionsProvider.notifier).duplicate(c),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Duplicate'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(connectionsProvider.notifier).delete(c);
              _toast('Deleted', '${c.name} removed', ToastKind.info);
            },
            style: OutlinedButton.styleFrom(foregroundColor: FsColors.red),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ]),
      ]),
      );
    });
  }

  // ── Connection log ──
  // A persistent, timestamped transcript of Connect / Test attempts. Unlike the
  // corner toasts (which fade after a few seconds) these stay put so the user
  // can read each diagnostic in order, right inside the new-connection window.
  Widget _connectionLog() {
    final lines = ref.watch(connectionLogProvider);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionTitle('Connection log', Icons.receipt_long_outlined)),
        if (lines.isNotEmpty) ...[
          Text('${lines.length}', style: FsType.sans(size: 11, color: FsColors.text3)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => ref.read(connectionLogProvider.notifier).clear(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Clear', style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.accentHi)),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 12),
      Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FsColors.bgScaffold,
          borderRadius: BorderRadius.circular(FsColors.rField),
          border: Border.all(color: FsColors.border),
        ),
        child: lines.isEmpty
            ? Center(
                child: Text('Test or connect to see diagnostics here.',
                    style: FsType.sans(size: 11, color: FsColors.text3)),
              )
            : ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final line = lines[lines.length - 1 - i]; // newest first
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_stamp(line.time),
                          style: FsType.mono(size: 11, color: FsColors.text3)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(line.message,
                            style: FsType.mono(size: 11, color: _logColor(line.kind), height: 1.4)),
                      ),
                    ]),
                  );
                },
              ),
      ),
      ),
    ]),
    );
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';
  static String _stamp(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  Color _logColor(ToastKind kind) => switch (kind) {
        ToastKind.success => FsColors.green,
        ToastKind.error => FsColors.red,
        ToastKind.info => FsColors.text2,
      };

  // ── S3 credential fields ──
  List<Widget> _s3Fields() {
    return [
      _sectionTitle('Connection', Icons.cloud_outlined),
      const SizedBox(height: 16),
      _fieldRow([
        FormField2('Region', _field(_region, (v) => c.region = v, hint: 'us-east-1', icon: Icons.public)),
        FormField2('Bucket', _field(_bucket, (v) => c.bucket = v, hint: 'blank = browse all buckets', icon: Icons.inventory_2_outlined)),
      ], flex: [1, 2]),
      const SizedBox(height: 12),
      FormField2('Endpoint (optional — for S3-compatible / MinIO)',
          _field(_endpoint, (v) => c.endpoint = v, hint: 's3.amazonaws.com', icon: Icons.dns_outlined)),
      const SizedBox(height: 20),

      _sectionTitle('Credentials', Icons.vpn_key_outlined),
      const SizedBox(height: 12),
      // Credentials source: typed, or the AWS chain (env vars → ~/.aws).
      _checkRow('Use AWS environment / ~/.aws credentials (auto-refreshed)', c.useAwsProfile,
          (v) => setState(() => c.useAwsProfile = v)),
      const SizedBox(height: 12),
      if (c.useAwsProfile) ...[
        FormField2('AWS profile',
            _field(_awsProfile, (v) => c.awsProfile = v, hint: 'default (or \$AWS_PROFILE)', icon: Icons.person_outline)),
        const SizedBox(height: 6),
        Text(
          'Credentials are resolved per request from the AWS environment '
          'variables (AWS_ACCESS_KEY_ID / …) if set, otherwise this profile in '
          '~/.aws/credentials — so refreshed temporary credentials are picked '
          'up automatically.',
          style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4),
        ),
      ] else ...[
        FormField2('Access Key ID', _field(_akid, (v) => c.accessKeyId = v, hint: 'AKIA…', icon: Icons.key_outlined)),
        const SizedBox(height: 12),
        FormField2('Secret Access Key', _field(_secret, (v) => c.secretAccessKey = v, obscure: true, hint: '••••••••', icon: Icons.lock_outline)),
        const SizedBox(height: 12),
        FormField2('Session Token (optional)', _field(_token, (v) => c.sessionToken = v, obscure: true, hint: 'For temporary STS credentials', icon: Icons.confirmation_number_outlined)),
      ],
      const SizedBox(height: 20),
      _sectionTitle('Assume role (optional)', Icons.badge_outlined),
      const SizedBox(height: 12),
      FormField2('Role ARN',
          _field(_roleArn, (v) => c.assumeRoleArn = v, hint: 'arn:aws:iam::123456789012:role/Name', icon: Icons.security)),
      const SizedBox(height: 12),
      FormField2('Role session name',
          _field(_roleSession, (v) => c.roleSessionName = v, hint: 'drag', icon: Icons.label_outline)),
      const SizedBox(height: 6),
      Text(
        'When set, the credentials above are exchanged for temporary credentials '
        'scoped to this role via STS AssumeRole (auto-refreshed before expiry).',
        style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4),
      ),
      const SizedBox(height: 20),
      _sectionTitle('Paths & Options', Icons.folder_outlined),
      const SizedBox(height: 14),
      _checkRow('Use SSL (HTTPS)', c.useSsl, (v) => setState(() => c.useSsl = v)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: FsColors.bgScaffold,
          borderRadius: BorderRadius.circular(FsColors.rField),
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
      _sectionTitle('Connection', Icons.cloud_outlined),
      const SizedBox(height: 16),
      FormField2('Hostname / IP', _field(_host, (v) => c.host = v, icon: Icons.dns_outlined)),
      const SizedBox(height: 16),
      _fieldRow([
        FormField2('Port', _field(_port, (v) => c.port = int.tryParse(v) ?? c.port, icon: Icons.numbers)),
        FormField2('Username', _field(_user, (v) => c.username = v, icon: Icons.person_outline)),
        FormField2('Timeout (s)', _field(_timeout, (v) => c.timeout = int.tryParse(v) ?? c.timeout, icon: Icons.timer_outlined)),
      ]),
      const SizedBox(height: 20),
      _sectionTitle('Authentication', Icons.shield_outlined),
      const SizedBox(height: 12),
      _authTabs(),
      const SizedBox(height: 16),
      if (c.auth == AuthMethod.password)
        FormField2('Password', _field(_password, (v) => c.password = v, obscure: true, hint: '••••••••', icon: Icons.lock_outline))
      else ...[
        FormField2(
          'Key file',
          Row(children: [
            Expanded(child: _field(_keyFile, (v) => c.keyFile = v, hint: 'Blank = default ~/.ssh keys', icon: Icons.vpn_key_outlined)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _browseKeyFile,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Browse'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        FormField2('Passphrase', _field(_passphrase, (v) => c.passphrase = v, obscure: true, hint: 'Leave blank if none', icon: Icons.password_outlined)),
      ],
      const SizedBox(height: 20),
      _sectionTitle('Paths & Options', Icons.folder_outlined),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: FormField2('Remote start path', _field(_remotePath, (v) => c.remotePath = v, icon: Icons.folder_outlined))),
        const SizedBox(width: 12),
        Expanded(child: FormField2('Local start path', _field(_localPath, (v) => c.localPath = v, hint: '~', icon: Icons.folder_outlined))),
      ]),
      const SizedBox(height: 14),
      _checkRow('Keep session alive (heartbeat every 30s)', c.keepAlive, (v) => setState(() => c.keepAlive = v)),
      const SizedBox(height: 6),
      _checkRow('Open in new tab', c.openInNewTab, (v) => setState(() => c.openInNewTab = v)),
    ];
  }

  /// Local field builder: a bigger Material [TextField] (~46px tall) styled to
  /// match the app, with a leading [prefixIcon]. ([FsTextField] has no prefix
  /// icon, so the field is built inline here.)
  Widget _field(TextEditingController ctl, ValueChanged<String> onChanged,
      {bool obscure = false, String? hint, IconData? icon, FocusNode? focusNode}) {
    final style = FsType.sans(size: 13, color: FsColors.text1);
    // For secret fields, an eye button toggles visibility per-field.
    final revealed = obscure && _revealed.contains(ctl);
    return SizedBox(
      height: 46,
      child: TextField(
        controller: ctl,
        focusNode: focusNode,
        obscureText: obscure && !revealed,
        onChanged: onChanged,
        style: style,
        cursorColor: FsColors.accent,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: style.copyWith(color: FsColors.text3),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: FsColors.text3),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          suffixIcon: !obscure
              ? null
              : IconButton(
                  splashRadius: 18,
                  tooltip: revealed ? 'Hide' : 'Show',
                  icon: Icon(
                    revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: FsColors.text3,
                  ),
                  onPressed: () => setState(
                      () => revealed ? _revealed.remove(ctl) : _revealed.add(ctl)),
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: true,
          fillColor: FsColors.bgSurface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsColors.rField),
            borderSide: BorderSide(color: FsColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsColors.rField),
            borderSide: BorderSide(color: FsColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _protocolSelect() {
    return SegmentedButton<Protocol>(
      segments: const [
        ButtonSegment(value: Protocol.sftp, label: Text('SFTP'), icon: Icon(Icons.dns_outlined, size: 16)),
        ButtonSegment(value: Protocol.s3, label: Text('S3'), icon: Icon(Icons.cloud_outlined, size: 16)),
      ],
      selected: {c.protocol},
      showSelectedIcon: false,
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(FsType.sans(size: 13, weight: FontWeight.w600)),
      ),
      onSelectionChanged: (s) {
        setState(() => c.protocol = s.first);
        ref.read(connectionsProvider.notifier).select(c);
      },
    );
  }

  Widget _authTabs() {
    return SegmentedButton<AuthMethod>(
      segments: [
        for (final m in AuthMethod.values)
          ButtonSegment(
            value: m,
            label: Text(m.label),
            icon: Icon(m == AuthMethod.password ? Icons.lock_outline : Icons.vpn_key_outlined, size: 16),
          ),
      ],
      selected: {c.auth},
      showSelectedIcon: false,
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(FsType.sans(size: 13, weight: FontWeight.w600)),
      ),
      onSelectionChanged: (s) => setState(() => c.auth = s.first),
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
          side: BorderSide(color: FsColors.border),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: FsType.sans(size: 12, color: FsColors.text2))),
    ]);
  }
}
