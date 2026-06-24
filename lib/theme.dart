import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Drag's palette. Following the **attendance-register** style approach: a
/// light Material 3 look generated with [ColorScheme.fromSeed] from the active
/// bird theme's primary colour — warm off-white surfaces, white cards, soft
/// tinted containers, dark legible text. [applyTheme] regenerates the whole
/// ramp when the theme changes, so every bird palette gives a distinct light
/// look (not just a different accent).
class FsColors {
  // ── Surface ramp (light) ──
  // NOT const: [applyTheme] recomputes these from the active ColorScheme.
  // Defaults are a neutral light scheme for the first frame before settings load.
  static Color bgScaffold = const Color(0xFFF4F6F1); // page background (warm off-white)
  static Color bgDeep = const Color(0xFFEFF2EC); // sidebar / title bar
  static Color bgSurface = const Color(0xFFFFFFFF); // cards
  static Color bgPanel = const Color(0xFFFFFFFF); // panels / dialogs
  static Color bgHover = const Color(0xFFE9ECE4); // subtle hover
  static Color bgActive = const Color(0xFFD7E8D2); // soft selected pill (secondaryContainer)

  static Color border = const Color(0xFFDDE2D6); // hairline (outlineVariant)
  static Color borderHi = const Color(0xFFB9BFB0); // stronger (outline)

  /// The accent's factory default.
  static const accentDefault = Color(0xFF1E6B2F);

  /// The UI accent ([ColorScheme.primary]) and a darker "highlight" used for
  /// selected text/icons sitting on [bgActive] ([ColorScheme.onSecondaryContainer]).
  static Color accent = accentDefault;
  static Color accentHi = const Color(0xFF0B5323);

  /// The full active scheme — buildDragTheme builds Material widgets from this.
  static ColorScheme scheme = const ColorScheme.light(primary: accentDefault);

  /// Derives a lighter tint of [base] (kept for callers that want a soft fill).
  static Color highlightFor(Color base) => Color.lerp(base, Colors.white, 0.28)!;

  /// Darkens [c] toward black by [amt] — used for pressed/hover button states.
  static Color darken(Color c, [double amt = 0.10]) => Color.lerp(c, Colors.black, amt)!;

  // Status colours — semantic, fixed, tuned for legibility on light surfaces.
  static const green = Color(0xFF2E7D32);
  static const amber = Color(0xFFB26A00);
  static const red = Color(0xFFC62828);
  static const purple = Color(0xFFA13B7E);

  static Color text1 = const Color(0xFF1A1C19); // headings / primary text
  static Color text2 = const Color(0xFF44483F); // secondary text
  static Color text3 = const Color(0xFF767D70); // muted / hints

  /// Soft drop shadow used by cards and the window frame.
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
      ];

  /// Regenerates the whole light palette from [t]'s primary colour via M3.
  static void applyTheme(BirdTheme t) {
    final cs = ColorScheme.fromSeed(seedColor: t.primary, brightness: Brightness.light);
    scheme = cs;
    accent = cs.primary;
    accentHi = cs.onSecondaryContainer;
    bgScaffold = cs.surfaceContainerLow;
    bgDeep = cs.surfaceContainer;
    bgSurface = cs.surfaceContainerLowest;
    bgPanel = cs.surfaceContainerLowest;
    bgHover = cs.surfaceContainerHigh;
    bgActive = cs.secondaryContainer;
    border = cs.outlineVariant;
    borderHi = cs.outline;
    // Pull the secondary/muted text darker than M3's defaults — onSurfaceVariant
    // and (especially) a surface-lerped tertiary read too light on these pale
    // surfaces. Bias both toward onSurface for legible contrast.
    text1 = cs.onSurface;
    text2 = Color.lerp(cs.onSurfaceVariant, cs.onSurface, 0.35)!;
    text3 = cs.onSurfaceVariant;
  }

  // Soft semantic pills (light tint bg + dark fg), matching the reference style.
  static const badgeLocalBg = Color(0xFFE1ECF7);
  static const badgeRemoteBg = Color(0xFFF4DBEA);
  static const badgeRemoteFg = Color(0xFFA13B7E);
  static const badgeDoneBg = Color(0xFFDCE7DA);
  static const badgeDoneFg = Color(0xFF2E6B33);
  static const badgeQueuedBg = Color(0xFFE8EAE3);
  static const badgeQueuedFg = Color(0xFF5C6157);
  static const badgeErrorBg = Color(0xFFF7DAD7);
  static const badgeErrorFg = Color(0xFFC62828);
  static const badgePausedBg = Color(0xFFFBEBD2);
  static const badgePausedFg = Color(0xFFB26A00);

  /// Card / button / field corner radii.
  static const rCard = 16.0;
  static const rField = 12.0;
  static const rPill = 24.0;
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
    bool tabular = false,
  }) =>
      _resolve(uiFontFamily,
          size: size,
          weight: weight,
          color: color ?? FsColors.text1,
          letterSpacing: letterSpacing,
          height: height,
          tabular: tabular);

  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      _resolve(monoFontFamily,
          size: size,
          weight: weight,
          color: color ?? FsColors.text2,
          letterSpacing: letterSpacing,
          height: height);

  /// A style in a specific font [family] — used to preview each font in its own
  /// typeface inside the font pickers.
  static TextStyle family(
    String family, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      _resolve(family, size: size, weight: weight, color: color ?? FsColors.text1);

  /// Resolves [family] via Google Fonts when it's in the catalogue, otherwise
  /// falls back to a bundled/system font of that name. This keeps families that
  /// aren't in the `google_fonts` package (e.g. Roboto Condensed, shipped as an
  /// asset) working without throwing.
  static TextStyle _resolve(
    String family, {
    required double size,
    required FontWeight weight,
    required Color color,
    double? letterSpacing,
    double? height,
    bool tabular = false,
  }) {
    final features = tabular ? const [FontFeature.tabularFigures()] : null;
    try {
      return GoogleFonts.getFont(family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          height: height).copyWith(fontFeatures: features);
    } catch (_) {
      return TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: features,
      );
    }
  }
}

ThemeData buildDragTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: FsColors.scheme);
  // Build the text theme from the user's selected UI font. Fonts not in the
  // google_fonts catalogue (e.g. the bundled Roboto Condensed) aren't supported
  // by getTextTheme, so fall back to applying the family to the base theme.
  TextTheme rawText;
  try {
    rawText = GoogleFonts.getTextTheme(FsType.uiFontFamily, base.textTheme);
  } catch (_) {
    rawText = base.textTheme.apply(fontFamily: FsType.uiFontFamily);
  }
  final uiText = rawText.apply(
    bodyColor: FsColors.text1,
    displayColor: FsColors.text1,
  );
  return base.copyWith(
    scaffoldBackgroundColor: FsColors.bgScaffold,
    canvasColor: FsColors.bgSurface,
    // Big display/headline numbers are heavier, tighter-tracked and use tabular
    // figures so animated counts don't jiggle.
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
      thumbColor: WidgetStateProperty.all(FsColors.borderHi),
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(4),
    ),
  );
}
