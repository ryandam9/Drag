/// The selectable fonts, mirroring the mechanism used in the Wombat app: a flat
/// enum of Google Fonts families split into proportional (UI) and monospace
/// sets. Each [family] string is resolved at render time via
/// `GoogleFonts.getFont(family)`, so adding a font is a one-line change here.
enum AppFont {
  // ── Proportional / UI fonts ──
  inter('Inter'),
  googleSans('Google Sans'),
  roboto('Roboto'),
  openSans('Open Sans'),
  lato('Lato'),
  notoSans('Noto Sans'),
  sourceSans3('Source Sans 3'),
  nunito('Nunito'),
  montserrat('Montserrat'),
  poppins('Poppins'),
  workSans('Work Sans'),
  dmSans('DM Sans'),
  ibmPlexSans('IBM Plex Sans'),
  ptSans('PT Sans'),

  // ── Monospace fonts (for paths, logs, the file list) ──
  jetBrainsMono('JetBrains Mono', mono: true),
  googleSansCode('Google Sans Code', mono: true),
  robotoMono('Roboto Mono', mono: true),
  firaCode('Fira Code', mono: true),
  sourceCodePro('Source Code Pro', mono: true),
  ibmPlexMono('IBM Plex Mono', mono: true),
  spaceMono('Space Mono', mono: true),
  overpassMono('Overpass Mono', mono: true);

  const AppFont(this.family, {this.mono = false});

  /// The Google Fonts family name — also the display label.
  final String family;

  /// Whether this is a fixed-width font, eligible for the monospace slot.
  final bool mono;

  String get label => family;

  /// Proportional fonts, alphabetical by label.
  static List<AppFont> get sansFonts =>
      values.where((f) => !f.mono).toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  /// Monospace fonts, alphabetical by label.
  static List<AppFont> get monoFonts =>
      values.where((f) => f.mono).toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  /// Resolves a persisted family string back to a known font, falling back to
  /// the slot default (Inter for UI, JetBrains Mono for code) so a stale or
  /// unknown name never reaches `GoogleFonts.getFont` (which would throw).
  static AppFont byFamily(String family, {required bool mono}) =>
      values.firstWhere((f) => f.family == family && f.mono == mono,
          orElse: () => mono ? jetBrainsMono : inter);

  /// The validated family string for [family], honouring the [mono] slot.
  static String resolve(String family, {required bool mono}) =>
      byFamily(family, mono: mono).family;
}
