import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Haul's whole palette. Deliberately tiny: paper, ink in three strengths,
/// one accent, one warning colour. Everything else is opacity.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.onAccent,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  /// Inputs, hovered rows, placeholders.
  final Color sunken;
  final Color line;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color accent;
  final Color onAccent;
  final Color danger;

  Color get accentSoft => accent.withValues(alpha: 0.12);
  Color get dangerSoft => danger.withValues(alpha: 0.10);

  static const light = Palette(
    bg: Color(0xFFF6F6F4),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFEFEC),
    line: Color(0xFFE4E4E0),
    ink: Color(0xFF151515),
    ink2: Color(0xFF66665F),
    ink3: Color(0xFF9D9D96),
    accent: Color(0xFF4B45E0),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD13F3F),
  );

  static const dark = Palette(
    bg: Color(0xFF0D0D0E),
    surface: Color(0xFF171718),
    sunken: Color(0xFF1F1F21),
    line: Color(0xFF29292C),
    ink: Color(0xFFF2F2EF),
    ink2: Color(0xFFA3A39C),
    ink3: Color(0xFF6E6E69),
    accent: Color(0xFF8E89FF),
    onAccent: Color(0xFF0D0D0E),
    danger: Color(0xFFFF7468),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      sunken: l(sunken, other.sunken),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      danger: l(danger, other.danger),
    );
  }
}

/// Motion tokens. Short and soft: things should feel quick, never busy.
abstract final class Motion {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const ease = Cubic(0.2, 0.0, 0.0, 1.0);
  static const easeOut = Curves.easeOutCubic;
  static const easeIn = Curves.easeInCubic;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const xl = 24.0;
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

const _tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;

  TextStyle s(double size, FontWeight w, Color c, {double ls = 0, double h = 1.35}) => TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: ls,
        height: h,
        fontFeatures: _tabular,
      );

  final text = TextTheme(
    displaySmall: s(30, FontWeight.w700, p.ink, ls: -0.9, h: 1.1),
    headlineSmall: s(22, FontWeight.w700, p.ink, ls: -0.5, h: 1.2),
    titleLarge: s(18, FontWeight.w600, p.ink, ls: -0.3),
    titleMedium: s(15, FontWeight.w600, p.ink, ls: -0.15),
    titleSmall: s(14, FontWeight.w600, p.ink, ls: -0.1),
    bodyLarge: s(15, FontWeight.w400, p.ink, ls: -0.1, h: 1.45),
    bodyMedium: s(14, FontWeight.w400, p.ink, ls: -0.05, h: 1.45),
    bodySmall: s(12.5, FontWeight.w400, p.ink2, h: 1.4),
    labelLarge: s(14, FontWeight.w600, p.ink, ls: -0.1),
    labelMedium: s(13, FontWeight.w500, p.ink2),
    labelSmall: s(11.5, FontWeight.w500, p.ink3, ls: 0.2),
  );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.ink,
    onSecondary: p.bg,
    error: p.danger,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerHighest: p.sunken,
    outline: p.line,
    outlineVariant: p.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    fontFamily: 'Inter',
    textTheme: text,
    extensions: [p],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: p.ink.withValues(alpha: 0.04),
    focusColor: p.accent.withValues(alpha: 0.14),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.ink2, size: 20),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(Radii.sm)),
      textStyle: s(12, FontWeight.w500, p.bg),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.25),
      selectionHandleColor: p.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.ink.withValues(alpha: 0.18)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p.onAccent : p.ink3),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p.accent : p.sunken),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Colors.transparent : p.line),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.sunken,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
      trackHeight: 4,
      valueIndicatorColor: p.ink,
      valueIndicatorTextStyle: s(12, FontWeight.w600, p.bg),
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.6 : 0.32),
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.6 : 0.32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: p.line),
      ),
      textStyle: text.bodyMedium,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
