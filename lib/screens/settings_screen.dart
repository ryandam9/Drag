import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The categories shown in the Settings sidebar. Each maps to a pane of real,
/// working controls — there are no decorative placeholders.
enum SettingsSection { appearance, browser, transfers }

extension on SettingsSection {
  String get label => switch (this) {
        SettingsSection.appearance => 'Appearance',
        SettingsSection.browser => 'Browser',
        SettingsSection.transfers => 'Transfers',
      };
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsSection _section = SettingsSection.appearance;

  static const _accents = [
    FsColors.accentDefault,
    FsColors.green,
    FsColors.purple,
    FsColors.amber,
    FsColors.red,
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final toast = ref.read(toastsProvider.notifier);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 170, child: _sidebar()),
      const VerticalDivider(width: 1, color: FsColors.border),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: isActive ? FsColors.bgActive : (hover ? FsColors.bgHover : Colors.transparent),
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
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text('PREFERENCES',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: FsColors.text3, letterSpacing: 1)),
        ),
        for (final s in SettingsSection.values) item(s),
      ]),
    );
  }

  // ── Active pane ──
  Widget _content(AppSettings settings, SettingsNotifier notifier, ToastsNotifier toasts) {
    void toast(String t, String s, ToastKind k) => toasts.push(t, s, k);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_section.label, style: FsType.sans(size: 15, weight: FontWeight.w600, color: FsColors.text1)),
        const SizedBox(height: 16),
        ...switch (_section) {
          SettingsSection.appearance => _appearance(settings, notifier, toast),
          SettingsSection.browser => _browser(settings, notifier),
          SettingsSection.transfers => _transfers(settings, notifier),
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

  List<Widget> _appearance(AppSettings settings, SettingsNotifier notifier, void Function(String, String, ToastKind) toast) {
    return [
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
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
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
    ];
  }

  List<Widget> _browser(AppSettings settings, SettingsNotifier notifier) {
    return [
      _check('Show hidden files', settings.showHiddenFiles, notifier.setShowHiddenFiles),
      _check('Show file permissions column', settings.showPermsColumn, notifier.setShowPermsColumn),
    ];
  }

  List<Widget> _transfers(AppSettings settings, SettingsNotifier notifier) {
    return [
      _check('Show transfer log on startup', settings.showLogOnStartup, notifier.setShowLogOnStartup),
      _check('Confirm before overwriting files', settings.confirmOverwrite, notifier.setConfirmOverwrite),
    ];
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
                side: const BorderSide(color: FsColors.border),
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
