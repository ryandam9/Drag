import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _accents = [
    FsColors.accentDefault,
    FsColors.green,
    FsColors.purple,
    FsColors.amber,
    FsColors.red,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final toast = ref.read(toastsProvider.notifier);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 170, child: _sidebar()),
      const VerticalDivider(width: 1, color: FsColors.border),
      Expanded(child: _content(settings, notifier, toast)),
    ]);
  }

  // ── Settings categories ──
  Widget _sidebar() {
    Widget group(String label, List<String> items, {String? active}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(label,
                  style: FsType.sans(
                      size: 10, weight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1)),
            ),
            for (final it in items)
              Hoverable(builder: (hover) {
                final isActive = it == active;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  color: isActive ? FsColors.bgActive : (hover ? FsColors.bgHover : Colors.transparent),
                  child: Text(it,
                      style: FsType.sans(
                          size: 12,
                          color: isActive ? FsColors.accentHi : (hover ? FsColors.text1 : FsColors.text2))),
                );
              }),
          ],
        );

    return Container(
      color: FsColors.bgDeep,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        group('GENERAL', ['Appearance', 'Transfers', 'Network', 'Editor'], active: 'Appearance'),
        group('SECURITY', ['SSH / Keys', 'Fingerprints', 'Proxy']),
        group('ADVANCED', ['Keybindings', 'Plugins']),
      ]),
    );
  }

  // ── Appearance pane ──
  Widget _content(AppSettings settings, SettingsNotifier notifier, ToastsNotifier toasts) {
    void toast(String t, String s, ToastKind k) => toasts.push(t, s, k);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appearance', style: FsType.sans(size: 15, weight: FontWeight.w600, color: FsColors.text1)),
        const SizedBox(height: 16),

        FormField2('Theme', _select(settings.themeName, const ['Dark (default)', 'Light', 'System'],
            (v) => notifier.setThemeName(v))),
        const SizedBox(height: 14),

        FormField2(
          'Accent color',
          Row(children: [
            for (final c in _accents)
              GestureDetector(
                onTap: () {
                  notifier.setAccent(c);
                  toast('Accent updated', 'Theme accent changed', ToastKind.info);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: settings.accent == c ? Border.all(color: c, width: 3) : null,
                  ),
                  foregroundDecoration: settings.accent == c
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: FsColors.bgScaffold, width: 2),
                        )
                      : null,
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        FormField2(
            'UI font size',
            _select('${settings.uiFontSize.toInt()}px', const ['12px', '13px', '14px'],
                (v) => notifier.setUiFontSize(double.parse(v.replaceAll('px', ''))))),
        const SizedBox(height: 14),
        FormField2(
            'Monospace font',
            _select(settings.monospaceFont, const ['JetBrains Mono', 'Fira Code', 'Menlo'],
                (v) => notifier.setMonospaceFont(v))),
        const SizedBox(height: 18),

        _check('Show hidden files', settings.showHiddenFiles, notifier.setShowHiddenFiles),
        _check('Show file permissions column', settings.showPermsColumn, notifier.setShowPermsColumn),
        _check('Show transfer log on startup', settings.showLogOnStartup, notifier.setShowLogOnStartup),
        _check('Confirm before overwriting files', settings.confirmOverwrite, notifier.setConfirmOverwrite),
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

  Widget _select(String value, List<String> options, ValueChanged<String> onChanged) {
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
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: FsColors.bgPanel,
          icon: const Icon(Icons.expand_more, size: 16, color: FsColors.text2),
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
      child: Row(children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            onChanged: (v) => set(v ?? false),
            activeColor: FsColors.accent,
            side: const BorderSide(color: FsColors.border),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: FsType.sans(size: 12, color: FsColors.text2)),
      ]),
    );
  }
}
