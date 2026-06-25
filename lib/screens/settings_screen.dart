import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/known_hosts_store.dart';
import '../data/secret_store.dart';
import '../models/app_font.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The categories shown in the Settings sidebar. Each maps to a pane of real,
/// working controls — there are no decorative placeholders.
enum SettingsSection { appearance, browser, transfers, fingerprints }

extension on SettingsSection {
  String get label => switch (this) {
        SettingsSection.appearance => 'Appearance',
        SettingsSection.browser => 'Browser',
        SettingsSection.transfers => 'Transfers',
        SettingsSection.fingerprints => 'Fingerprints',
      };
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsSection _section = SettingsSection.appearance;

  /// Bumped to reload the known-hosts list after a remove / forget-all.
  int _khRefresh = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final toast = ref.read(toastsProvider.notifier);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 170, child: _sidebar()),
      VerticalDivider(width: 1, color: FsColors.border),
      Expanded(child: _content(settings, notifier, toast)),
    ]);
  }

  // ── Settings categories (clickable — switch the content pane) ──
  Widget _sidebar() {
    Widget item(SettingsSection s) {
      final isActive = s == _section;
      return Hoverable(builder: (hover) {
        return GestureDetector(
          onTap: () => setState(() => _section = s),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive
                    ? FsColors.bgActive
                    : (hover ? FsColors.bgHover : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(s.label,
                  style: FsType.sans(
                      size: 12,
                      weight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2))),
            ),
          ),
        );
      });
    }

    return Container(
      color: FsColors.bgDeep,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('PREFERENCES',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1)),
        ),
        for (final s in SettingsSection.values) item(s),
      ]),
    );
  }

  /// A white rounded card wrapping one settings section, matching the
  /// attendance-register card style (soft shadow, hairline border, rounded).
  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(FsColors.rCard),
        border: Border.all(color: FsColors.border),
        boxShadow: FsColors.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // ── Active pane ──
  Widget _content(AppSettings settings, SettingsNotifier notifier, ToastsNotifier toasts) {
    void toast(String t, String s, ToastKind k) => toasts.push(t, s, k);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_section.label, style: FsType.sans(size: 22, weight: FontWeight.w700, color: FsColors.text1)),
        const SizedBox(height: 20),
        ...switch (_section) {
          SettingsSection.appearance => _appearance(settings, notifier, toast),
          SettingsSection.browser => _browser(settings, notifier),
          SettingsSection.transfers => _transfers(settings, notifier),
          SettingsSection.fingerprints => _fingerprints(),
        },
        const SizedBox(height: 20),
        Row(children: [
          FsButton('Save',
              kind: FsButtonKind.primary,
              onTap: () => toast('Preferences saved', 'Your settings were applied', ToastKind.success)),
          const SizedBox(width: 10),
          FsButton('Reset defaults', onTap: () {
            notifier.resetSettings();
            toast('Defaults restored', 'Settings reset to defaults', ToastKind.info);
          }),
        ]),
      ]),
    );
  }

  static const _brightnessModes = [
    ('light', 'Light', Icons.light_mode_outlined),
    ('dark', 'Dark', Icons.dark_mode_outlined),
    ('system', 'System', Icons.brightness_auto_outlined),
  ];

  List<Widget> _appearance(AppSettings settings, SettingsNotifier notifier, void Function(String, String, ToastKind) toast) {
    return [
      _card(children: [
        Text('Mode', style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
        const SizedBox(height: 4),
        Text('Light or dark surfaces, or follow your operating system.',
            style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4)),
        const SizedBox(height: 16),
        Row(children: [
          for (final (value, label, icon) in _brightnessModes) ...[
            _brightnessChip(label, icon,
                selected: settings.brightnessMode == value,
                onTap: () {
                  notifier.setBrightnessMode(value);
                  toast('Display mode', label, ToastKind.info);
                }),
            const SizedBox(width: 8),
          ],
        ]),
      ]),
      const SizedBox(height: 16),
      _card(children: [
        Text('Theme', style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
        const SizedBox(height: 4),
        Text('Bird-inspired palettes — the accent recolors the whole UI.',
            style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in kBirdThemes)
              _themeSwatch(t, selected: settings.themeName == t.name, onTap: () {
                notifier.setTheme(t);
                toast('Theme applied', t.name, ToastKind.info);
              }),
          ],
        ),
      ]),
      const SizedBox(height: 16),
      _card(children: [
        FormField2(
            'UI font',
            _fontSelect(settings.uiFont, AppFont.sansFonts, (v) => notifier.setUiFont(v))),
        const SizedBox(height: 16),
        FormField2(
            'UI font size',
            _select('${settings.uiFontSize.toInt()}px',
                const ['11px', '12px', '13px', '14px', '15px', '16px', '17px', '18px'],
                (v) => notifier.setUiFontSize(double.parse(v.replaceAll('px', ''))))),
        const SizedBox(height: 16),
        FormField2(
            'Monospace font',
            _fontSelect(settings.monospaceFont, AppFont.monoFonts, (v) => notifier.setMonospaceFont(v))),
        const SizedBox(height: 10),
        Text('The quick brown fox jumps over the lazy dog · 0123456789',
            style: FsType.mono(size: 12, color: FsColors.text3)),
      ]),
    ];
  }

  /// A dropdown of [fonts] where each option is rendered in its own typeface, so
  /// the user previews the font before picking it. The current [family] is
  /// resolved to a known font (falling back to the slot default).
  Widget _fontSelect(String family, List<AppFont> fonts, ValueChanged<String> onChanged) {
    final mono = fonts.isNotEmpty && fonts.first.mono;
    final current = AppFont.byFamily(family, mono: mono).family;
    return Container(
      height: 36,
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FsColors.bgScaffold,
        borderRadius: BorderRadius.circular(FsColors.rField),
        border: Border.all(color: FsColors.border),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          isDense: true,
          isExpanded: true,
          dropdownColor: FsColors.bgPanel,
          icon: Icon(Icons.expand_more, size: 16, color: FsColors.text2),
          style: FsType.sans(size: 12, color: FsColors.text1),
          items: [
            for (final f in fonts)
              DropdownMenuItem(
                value: f.family,
                child: Text(f.label, style: FsType.family(f.family, size: 12, color: FsColors.text1)),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  /// A clickable theme card: the three signature colours as a swatch plus the
  /// bird name, ringed in the theme accent when selected.
  Widget _brightnessChip(String label, IconData icon,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? FsColors.bgActive : FsColors.bgSurface,
            borderRadius: BorderRadius.circular(FsColors.rField),
            border: Border.all(
                color: selected ? FsColors.accent : FsColors.border, width: selected ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? FsColors.accentHi : FsColors.text2),
            const SizedBox(width: 8),
            Text(label,
                style: FsType.sans(
                    size: 12,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? FsColors.accentHi : FsColors.text2)),
          ]),
        ),
      ),
    );
  }

  Widget _themeSwatch(BirdTheme t, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 184,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FsColors.bgSurface,
            borderRadius: BorderRadius.circular(FsColors.rField),
            border: Border.all(
                color: selected ? t.accentHi : FsColors.border, width: selected ? 2 : 1),
            boxShadow: selected ? FsColors.cardShadow : null,
          ),
          child: Row(children: [
            // Three stacked color chips representing the palette.
            SizedBox(
              width: 44,
              height: 26,
              child: Stack(children: [
                for (final entry in [t.primary, t.secondary, t.tertiary].asMap().entries)
                  Positioned(
                    left: entry.key * 14.0,
                    child: Container(
                      width: 18,
                      height: 26,
                      decoration: BoxDecoration(
                        color: entry.value,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FsColors.bgPanel, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FsType.sans(
                      size: 11.5,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? FsColors.text1 : FsColors.text2)),
            ),
            if (selected) Icon(Icons.check_circle, size: 16, color: t.accentHi),
          ]),
        ),
      ),
    );
  }

  List<Widget> _browser(AppSettings settings, SettingsNotifier notifier) {
    return [
      _card(children: [
        _check('Show hidden files', settings.showHiddenFiles, notifier.setShowHiddenFiles),
        _check('Show file permissions column', settings.showPermsColumn, notifier.setShowPermsColumn),
      ]),
    ];
  }

  static const _verifyLabels = {
    'off': 'Off',
    'size': 'Size (byte count)',
    'checksum': 'Checksum (MD5)',
  };

  // Aggregate transfer speed caps, in KiB/second (0 = unlimited).
  static const _speedLimits = <String, int>{
    'Unlimited': 0,
    '512 KB/s': 512,
    '1 MB/s': 1024,
    '5 MB/s': 5120,
    '10 MB/s': 10240,
    '25 MB/s': 25600,
    '50 MB/s': 51200,
  };

  String _speedLabel(int kbps) => _speedLimits.entries
      .firstWhere((e) => e.value == kbps, orElse: () => const MapEntry('Unlimited', 0))
      .key;

  List<Widget> _transfers(AppSettings settings, SettingsNotifier notifier) {
    return [
      _card(children: [
        _check('Show transfer log on startup', settings.showLogOnStartup, notifier.setShowLogOnStartup),
        _check('Confirm before overwriting files', settings.confirmOverwrite, notifier.setConfirmOverwrite),
        _check('Notify when a transfer finishes (window unfocused)', settings.notifyOnComplete,
            notifier.setNotifyOnComplete),
      ]),
      const SizedBox(height: 16),
      _card(children: [
        FormField2(
          'Verify transfers',
          _select(
            _verifyLabels[settings.verifyLevel] ?? _verifyLabels['size']!,
            _verifyLabels.values.toList(),
            (v) {
              final level = _verifyLabels.entries.firstWhere((e) => e.value == v).key;
              notifier.setVerifyLevel(level);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'After each file copies, confirm the destination matches the source. '
          'A mismatch fails the transfer so it can retry.',
          style: FsType.sans(size: 11, color: FsColors.text3),
        ),
      ]),
      const SizedBox(height: 16),
      _card(children: [
        FormField2(
          'Transfer speed limit',
          _select(
            _speedLabel(settings.transferLimitKbps),
            _speedLimits.keys.toList(),
            (v) => notifier.setTransferLimitKbps(_speedLimits[v] ?? 0),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Caps the combined throughput of all active transfers. Unlimited by default.',
          style: FsType.sans(size: 11, color: FsColors.text3),
        ),
      ]),
    ];
  }

  List<Widget> _fingerprints() {
    final store = ref.watch(knownHostsStoreProvider);
    return [
      _secretStorageCard(),
      const SizedBox(height: 16),
      _card(children: [
        Row(children: [
          Expanded(
            child: Text('Trusted SSH host keys',
                style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
          ),
          if (store != null)
            FsButton('Forget all', kind: FsButtonKind.danger, fontSize: 11, onTap: () async {
              await store.clear();
              if (mounted) setState(() => _khRefresh++);
            }),
        ]),
        const SizedBox(height: 4),
        Text(
          'Drag remembers each SFTP server\'s key the first time you connect and '
          'refuses to connect if it later changes (a possible man-in-the-middle). '
          'Forget an entry to be re-prompted, e.g. after a legitimate key rotation.',
          style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (store == null)
          Text('Host-key storage is unavailable.', style: FsType.sans(size: 12, color: FsColors.text3))
        else
          FutureBuilder<List<KnownHost>>(
            key: ValueKey(_khRefresh),
            future: store.load(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: FsColors.accent)),
                );
              }
              final hosts = snap.data!;
              if (hosts.isEmpty) {
                return Text('No trusted hosts yet — connect to an SFTP server to add one.',
                    style: FsType.sans(size: 12, color: FsColors.text3));
              }
              return Column(children: [for (final h in hosts) _hostRow(store, h)]);
            },
          ),
      ]),
    ];
  }

  Widget _secretStorageCard() {
    final store = ref.watch(secretStoreProvider);
    // No store wired (or an explicit memory store) ⇒ secrets are memory-only.
    final healthy = store?.status == SecretStoreStatus.keychain;
    final color = healthy ? FsColors.green : FsColors.amber;
    return _card(children: [
      Row(children: [
        Icon(healthy ? Icons.lock_outline : Icons.warning_amber_rounded, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Secret storage',
              style: FsType.sans(size: 15, weight: FontWeight.w700, color: FsColors.text1)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(FsColors.rPill),
          ),
          child: Text(healthy ? 'Keychain' : 'Memory only',
              style: FsType.sans(size: 11, weight: FontWeight.w600, color: color)),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        healthy
            ? 'Connection passwords, key passphrases and S3 secrets are stored in '
                'your OS keychain and persist across restarts.'
            : 'The OS keychain is unavailable, so connection passwords and secrets '
                'are kept in memory only — they will be lost when Drag closes. '
                'Re-enter them each session, or fix the system keychain to persist them.',
        style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4),
      ),
    ]);
  }

  Widget _hostRow(KnownHostsStore store, KnownHost h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FsColors.bgScaffold,
        borderRadius: BorderRadius.circular(FsColors.rField),
        border: Border.all(color: FsColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${h.endpoint}  ·  ${h.type}',
                style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.text1)),
            const SizedBox(height: 2),
            SelectableText(h.fingerprint, style: FsType.mono(size: 11, color: FsColors.text2)),
          ]),
        ),
        const SizedBox(width: 8),
        FsButton('Forget', fontSize: 11, onTap: () async {
          if (h.id != null) await store.remove(h.id!);
          if (mounted) setState(() => _khRefresh++);
        }),
      ]),
    );
  }

  Widget _select(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      height: 36,
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FsColors.bgScaffold,
        borderRadius: BorderRadius.circular(FsColors.rField),
        border: Border.all(color: FsColors.border),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: FsColors.bgPanel,
          icon: Icon(Icons.expand_more, size: 16, color: FsColors.text2),
          style: FsType.sans(size: 12, color: FsColors.text1),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => set(!value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: (v) => set(v ?? false),
                activeColor: FsColors.accent,
                side: BorderSide(color: FsColors.border),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: FsType.sans(size: 12, color: FsColors.text2)),
          ]),
        ),
      ),
    );
  }
}
