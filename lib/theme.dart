import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color palette ported 1:1 from the FileSync mockup CSS variables.
class FsColors {
  static const bgScaffold = Color(0xFF08090D);
  static const bgDeep = Color(0xFF0F1117);
  static const bgSurface = Color(0xFF161B27);
  static const bgPanel = Color(0xFF1C2333);
  static const bgHover = Color(0xFF222C42);
  static const bgActive = Color(0xFF1E3A5F);

  static const border = Color(0xFF2A3550);
  static const borderHi = Color(0xFF3D5080);

  static const accent = Color(0xFF3B82F6);
  static const accentHi = Color(0xFF60A5FA);

  static const green = Color(0xFF22C55E);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const purple = Color(0xFFA855F7);

  static const text1 = Color(0xFFE2E8F0);
  static const text2 = Color(0xFF94A3B8);
  static const text3 = Color(0xFF4A5568);

  // Badge fills.
  static const badgeLocalBg = Color(0xFF1E3A5F);
  static const badgeRemoteBg = Color(0xFF2A1F4E);
  static const badgeRemoteFg = Color(0xFFC084FC);
  static const badgeDoneBg = Color(0xFF14532D);
  static const badgeDoneFg = Color(0xFF86EFAC);
  static const badgeQueuedBg = Color(0xFF292524);
  static const badgeQueuedFg = Color(0xFFD6D3D1);
  static const badgeErrorBg = Color(0xFF450A0A);
  static const badgeErrorFg = Color(0xFFFCA5A5);
  static const badgePausedBg = Color(0xFF431407);
  static const badgePausedFg = Color(0xFFFED7AA);
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

ThemeData buildFileSyncTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: FsColors.bgScaffold,
    canvasColor: FsColors.bgSurface,
    colorScheme: base.colorScheme.copyWith(
      primary: FsColors.accent,
      secondary: FsColors.accentHi,
      surface: FsColors.bgSurface,
      error: FsColors.red,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: FsColors.text1,
      displayColor: FsColors.text1,
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
