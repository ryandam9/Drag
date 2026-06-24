import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Drag's palette, retuned to the Feathers **Rainbow Bee-eater** identity used
/// in the attendance-register app: deep-navy surfaces with a bright-blue /
/// cyan accent (primary #00346E, secondary #007CBF, tertiary #06ABDF).
class FsColors {
  // ── Surface ramp ──
  // These are NOT const: [applyTheme] recomputes the whole ramp from the active
  // theme's hue, so switching themes retints every surface, border and text
  // colour across the app — not just the accent. Defaults below mirror the
  // Rainbow Bee-eater navy so the first frame (before settings load) looks right.
  static Color bgScaffold = const Color(0xFF04101C);
  static Color bgDeep = const Color(0xFF061522);
  static Color bgSurface = const Color(0xFF0B2236);
  static Color bgPanel = const Color(0xFF0F2A41);
  static Color bgHover = const Color(0xFF163651);
  static Color bgActive = const Color(0xFF16487B);

  static Color border = const Color(0xFF1C3A57);
  static Color borderHi = const Color(0xFF2E5A8A);

  /// The accent's factory default — the Bee-eater "secondary" bright blue.
  static const accentDefault = Color(0xFF007CBF);

  /// Accent + its lighter highlight variant. Recolored by [applyTheme] /
  /// `SettingsNotifier.setTheme`. The default highlight is the Bee-eater
  /// "tertiary" cyan.
  static Color accent = accentDefault;
  static Color accentHi = const Color(0xFF06ABDF);

  /// Derives the lighter "accentHi" highlight from a base accent color.
  static Color highlightFor(Color base) => Color.lerp(base, Colors.white, 0.28)!;

  // Status colours stay fixed — they carry semantic meaning (success / warn /
  // error) that shouldn't shift with the decorative theme.
  static const green = Color(0xFFAFD135); // lifted olive
  static const amber = Color(0xFFFFC04D); // lifted orange
  static const red = Color(0xFFFF6B6B);
  static const purple = Color(0xFFE673BD); // lifted magenta

  static Color text1 = const Color(0xFFE3E9F2);
  static Color text2 = const Color(0xFF9FB2C9);
  static Color text3 = const Color(0xFF5A7088);

  /// Retints the entire surface/border/text ramp from [t]'s primary hue and
  /// sets the accent from its secondary/tertiary. Keeps the dark aesthetic but
  /// gives every theme a distinct tinted-dark look.
  static void applyTheme(BirdTheme t) {
    accent = t.accent;
    accentHi = t.accentHi;
    final hue = HSLColor.fromColor(t.primary).hue;
    Color s(double sat, double light) => HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
    bgScaffold = s(0.45, 0.05);
    bgDeep = s(0.45, 0.07);
    bgSurface = s(0.42, 0.10);
    bgPanel = s(0.40, 0.13);
    bgHover = s(0.36, 0.17);
    bgActive = Color.lerp(s(0.40, 0.15), t.secondary, 0.45)!;
    border = s(0.30, 0.22);
    borderHi = s(0.32, 0.30);
    text1 = s(0.18, 0.93);
    text2 = s(0.20, 0.72);
    text3 = s(0.22, 0.50);
  }

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

/// One of the Feathers bird-inspired palettes used in the attendance-register
/// app. Each maps three signature colours to roles; in Drag the [secondary]
/// drives the UI accent and [tertiary] its lighter highlight, layered over the
/// shared deep-navy surface ramp.
class BirdTheme {
  final String name;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  const BirdTheme(this.name, this.primary, this.secondary, this.tertiary);

  /// The colour used as the live UI accent for this theme.
  Color get accent => secondary;

  /// The lighter highlight variant (hover/active accent text).
  Color get accentHi => tertiary;
}

/// The 12 selectable themes, ported 1:1 from attendance-register's
/// `bird_themes.dart`. [kDefaultThemeName] is the factory default.
const String kDefaultThemeName = 'Rainbow Bee-eater';

const List<BirdTheme> kBirdThemes = [
  BirdTheme('Rainbow Bee-eater', Color(0xFF00346E), Color(0xFF007CBF), Color(0xFF06ABDF)),
  BirdTheme('Spotted Pardalote', Color(0xFFCB0300), Color(0xFFFECA00), Color(0xFFD36328)),
  BirdTheme('Plains-wanderer', Color(0xFFEDD8C5), Color(0xFFE7AA01), Color(0xFFD09A5E)),
  BirdTheme('Rose-crowned Fruit Dove', Color(0xFFBD338F), Color(0xFFEB8252), Color(0xFF8FA33F)),
  BirdTheme('Eastern Rosella', Color(0xFF2F533C), Color(0xFFF4C623), Color(0xFF2F7AB9)),
  BirdTheme('Olivaceous Oriole', Color(0xFFB8A53F), Color(0xFFA29EB8), Color(0xFFBB5645)),
  BirdTheme('Princess Parrot', Color(0xFF7090C9), Color(0xFF6EB245), Color(0xFFCF2236)),
  BirdTheme('Superb Fairy-wren', Color(0xFFB03F05), Color(0xFFAA7853), Color(0xFF4F3321)),
  BirdTheme('Cassowary', Color(0xFF0169C4), Color(0xFFBDA14D), Color(0xFFD5114E)),
  BirdTheme('Eastern Yellow Robin', Color(0xFF979EB9), Color(0xFFE19E00), Color(0xFF85773A)),
  BirdTheme('Galah', Color(0xFFD05478), Color(0xFFE9A7BB), Color(0xFF4C5766)),
  BirdTheme('Blue-winged Kookaburra', Color(0xFFAD8D9F), Color(0xFF0B7595), Color(0xFFB5EFFB)),
];

/// Looks up a theme by [name], falling back to the default Bee-eater palette.
BirdTheme birdThemeByName(String name) =>
    kBirdThemes.firstWhere((t) => t.name == name,
        orElse: () => kBirdThemes.first);

class FsType {
  /// The active UI (proportional) and monospace font families. Mutable so the
  /// Appearance settings can swap the whole app's typography at runtime; set by
  /// `SettingsNotifier` from the persisted [AppSettings]. Always a valid Google
  /// Fonts family (sanitised via `AppFont.resolve`).
  static String uiFontFamily = 'Inter';
  static String monoFontFamily = 'JetBrains Mono';

  static TextStyle sans({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.getFont(
        uiFontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? FsColors.text1,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.getFont(
        monoFontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? FsColors.text2,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// A style in a specific Google Fonts [family] — used to preview each font in
  /// its own typeface inside the font pickers.
  static TextStyle family(
    String family, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      GoogleFonts.getFont(family,
          fontSize: size, fontWeight: weight, color: color ?? FsColors.text1);
}

ThemeData buildDragTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  // Build the text theme from the user's selected UI font.
  final uiText = GoogleFonts.getTextTheme(FsType.uiFontFamily, base.textTheme).apply(
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
    textTheme: uiText.copyWith(
      displaySmall: uiText.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineLarge: uiText.headlineLarge?.copyWith(
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
