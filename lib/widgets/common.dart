import 'package:flutter/material.dart';
import '../theme.dart';

/// Small pill button used in screen headers (e.g. the Transfer Queue's
/// "⏸ Pause all" / "⊗ Clear done" bulk actions).
class TbButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const TbButton(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: _Hoverable(
        builder: (hover) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hover ? FsColors.bgHover : FsColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FsColors.border),
            ),
            child: Text(label, style: FsType.sans(size: 10, weight: FontWeight.w600, color: FsColors.text2)),
          ),
        ),
      ),
    );
  }
}

enum FsButtonKind { primary, ghost, danger }

class FsButton extends StatelessWidget {
  final String label;
  final FsButtonKind kind;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;

  const FsButton(
    this.label, {
    super.key,
    this.kind = FsButtonKind.ghost,
    this.onTap,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return _Hoverable(builder: (hover) {
      late Color bg, fg;
      Border? border;
      List<BoxShadow>? shadow;
      switch (kind) {
        case FsButtonKind.primary:
          bg = hover ? FsColors.darken(FsColors.accent) : FsColors.accent;
          fg = FsColors.scheme.onPrimary;
          shadow = FsColors.cardShadow;
        case FsButtonKind.ghost:
          bg = hover ? FsColors.bgHover : FsColors.bgSurface;
          fg = hover ? FsColors.text1 : FsColors.text2;
          border = Border.all(color: FsColors.border);
        case FsButtonKind.danger:
          bg = hover ? const Color(0xFFF7DAD7) : FsColors.bgSurface;
          fg = FsColors.red;
          border = Border.all(color: const Color(0xFFE6B4B0));
      }
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(FsColors.rPill),
              border: border,
              boxShadow: shadow,
            ),
            child: Text(label,
                style: FsType.sans(size: fontSize, weight: FontWeight.w600, color: fg)),
          ),
        ),
      );
    });
  }
}

/// A status pill (Active / Queued / Done / Error / Paused …).
class StatusBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  const StatusBadge(this.text, {super.key, required this.bg, required this.fg, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: FsType.sans(size: 10, weight: FontWeight.w600, color: fg)),
    );
    if (onTap == null) return pill;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: pill),
    );
  }
}

class StatusDot extends StatelessWidget {
  final Color color;
  final bool glow;
  final double size;
  const StatusDot(this.color, {super.key, this.glow = false, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow ? [BoxShadow(color: color, blurRadius: 6, spreadRadius: 0.5)] : null,
      ),
    );
  }
}

/// Generic toolbar text/icon button with hover + active states.
class ToolButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback? onTap;

  /// Optional hover description (e.g. what the action does + its shortcut).
  final String? tooltip;

  /// When false the button is dimmed and doesn't respond — used for actions
  /// that don't apply in the current context (e.g. mutating an S3 bucket list).
  final bool enabled;
  const ToolButton(this.label,
      {super.key,
      this.active = false,
      this.color,
      this.onTap,
      this.tooltip,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return _Hoverable(builder: (hover) {
      if (!enabled) {
        return Opacity(
          opacity: 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(label, style: FsType.sans(size: 12, color: color ?? FsColors.text2)),
          ),
        );
      }
      Color bg = Colors.transparent;
      Color fg = color ?? FsColors.text2;
      if (active) {
        bg = FsColors.bgActive;
        fg = FsColors.accentHi;
      } else if (hover) {
        bg = FsColors.bgHover;
        fg = color ?? FsColors.text1;
      }
      Widget btn = GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: FsType.sans(size: 12, color: fg)),
          ),
        ),
      );
      if (tooltip != null) {
        btn = Tooltip(
          message: tooltip!,
          waitDuration: const Duration(milliseconds: 400),
          child: btn,
        );
      }
      return btn;
    });
  }
}

class ToolSep extends StatelessWidget {
  const ToolSep({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: FsColors.border,
      );
}

/// Outlined / focusable text field matching `.form-input`.
class FsTextField extends StatelessWidget {
  final String? value;
  final String? hint;
  final bool mono;
  final bool readOnly;
  final bool obscure;
  final double? width;
  final double height;
  final TextAlign align;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  const FsTextField({
    super.key,
    this.value,
    this.hint,
    this.mono = false,
    this.readOnly = false,
    this.obscure = false,
    this.width,
    this.height = 36,
    this.align = TextAlign.left,
    this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? FsType.mono(size: 12, color: FsColors.text1)
        : FsType.sans(size: 12, color: FsColors.text1);
    return SizedBox(
      width: width,
      height: height,
      child: TextField(
        controller: controller ?? (value != null ? TextEditingController(text: value) : null),
        readOnly: readOnly,
        obscureText: obscure,
        textAlign: align,
        onChanged: onChanged,
        style: style,
        cursorColor: FsColors.accent,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: style.copyWith(color: FsColors.text3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}

/// Form field label + child column.
class FormField2 extends StatelessWidget {
  final String label;
  final Widget child;
  const FormField2(this.label, this.child, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: FsType.sans(size: 11, weight: FontWeight.w600, color: FsColors.text2, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Reusable hover wrapper that rebuilds its child with the hover flag.
class _Hoverable extends StatefulWidget {
  final Widget Function(bool hovering) builder;
  const _Hoverable({required this.builder});

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(_hover),
    );
  }
}

/// Public hover helper (re-exported for screens that need their own hover rows).
class Hoverable extends StatelessWidget {
  final Widget Function(bool hovering) builder;
  const Hoverable({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => _Hoverable(builder: builder);
}

/// A window container with the surface background, border and drop shadow.
class WindowFrame extends StatelessWidget {
  final Widget child;
  const WindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FsColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FsColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 48, offset: Offset(0, 18))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }
}
