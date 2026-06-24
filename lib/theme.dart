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
    double? height,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
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
