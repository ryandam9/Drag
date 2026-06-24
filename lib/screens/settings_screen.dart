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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
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
      Text('Theme', style: FsType.sans(size: 12, weight: FontWeight.w600, color: FsColors.text2)),
      const SizedBox(height: 4),
      Text('Bird-inspired palettes — the accent recolors the whole UI.',
          style: FsType.sans(size: 11, color: FsColors.text3, height: 1.4)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in kBirdThemes)
            _themeSwatch(t, selected: settings.themeName == t.name, onTap: () {
              notifier.setTheme(t);
              toast('Theme applied', t.name, ToastKind.info);
            }),
        ],
      ),
      const SizedBox(height: 18),
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

  /// A clickable theme card: the three signature colours as a swatch plus the
  /// bird name, ringed in the theme accent when selected.
  Widget _themeSwatch(BirdTheme t, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 184,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FsColors.bgPanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? t.accentHi : FsColors.border, width: selected ? 2 : 1),
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
