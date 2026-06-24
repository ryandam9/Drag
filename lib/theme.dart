import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Drag's palette, retuned to the Feathers **Rainbow Bee-eater** identity used
/// in the attendance-register app: deep-navy surfaces with a bright-blue /
/// cyan accent (primary #00346E, secondary #007CBF, tertiary #06ABDF).
class FsColors {
  // ── Navy surface ramp (#061522 / #0B2236 anchor the dark surfaces) ──
  static const bgScaffold = Color(0xFF04101C);
  static const bgDeep = Color(0xFF061522);
  static const bgSurface = Color(0xFF0B2236);
  static const bgPanel = Color(0xFF0F2A41);
  static const bgHover = Color(0xFF163651);
  static const bgActive = Color(0xFF16487B);

  static const border = Color(0xFF1C3A57);
  static const borderHi = Color(0xFF2E5A8A);

  /// The accent's factory default — the Bee-eater "secondary" bright blue.
  static const accentDefault = Color(0xFF007CBF);

  /// Accent + its lighter highlight variant. These are mutable so the
  /// Appearance settings can recolor the whole UI at runtime (see
  /// `SettingsNotifier.setAccent`). The default highlight is the Bee-eater
  /// "tertiary" cyan.
  static Color accent = accentDefault;
  static Color accentHi = const Color(0xFF06ABDF);

  /// Derives the lighter "accentHi" highlight from a base accent color.
  static Color highlightFor(Color base) => Color.lerp(base, Colors.white, 0.28)!;

  // Status colours — the Feathers "day-type" dark shades, lifted for legibility
  // on navy surfaces.
  static const green = Color(0xFFAFD135); // lifted olive
  static const amber = Color(0xFFFFC04D); // lifted orange
  static const red = Color(0xFFFF6B6B);
  static const purple = Color(0xFFE673BD); // lifted magenta

  static const text1 = Color(0xFFE3E9F2);
  static const text2 = Color(0xFF9FB2C9);
  static const text3 = Color(0xFF5A7088);

  // Badge fills, aligned to the status palette.
  static const badgeLocalBg = Color(0xFF0E3A57);
  static const badgeRemoteBg = Color(0xFF0C3B3A);
  static const badgeRemoteFg = Color(0xFF5FD6CF);
  static const badgeDoneBg = Color(0xFF294D11);
  static const badgeDoneFg = Color(0xFFAFD135);
  static const badgeQueuedBg = Color(0xFF25303F);
  static const badgeQueuedFg = Color(0xFF9AA3BC);
  static const badgeErrorBg = Color(0xFF4A1618);
  static const badgeErrorFg = Color(0xFFFF8A8A);
  static const badgePausedBg = Color(0xFF4A3410);
  static const badgePausedFg = Color(0xFFFFC04D);
}

class FsType {
  static TextStyle sans({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = FsColors.text1,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color color = FsColors.text2,
    double? letterSpacing,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
}

ThemeData buildDragTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final interText = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: FsColors.text1,
    displayColor: FsColors.text1,
  );
  return base.copyWith(
    scaffoldBackgroundColor: FsColors.bgScaffold,
    canvasColor: FsColors.bgSurface,
    colorScheme: base.colorScheme.copyWith(
      primary: FsColors.accent,
      secondary: FsColors.accentHi,
      surface: FsColors.bgSurface,
      error: FsColors.red,
    ),
    // The Feathers type direction: big display/headline numbers are heavier,
    // tighter-tracked and use tabular figures so animated counts don't jiggle.
    textTheme: interText.copyWith(
      displaySmall: interText.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineLarge: interText.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    dividerColor: FsColors.border,
    splashFactory: NoSplash.splashFactory,
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(FsColors.border),
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(4),
    ),
  );
}
