import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Haul's whole palette: warm paper, ink in three strengths, one accent and
/// one warning colour. Everything else is opacity.
///
/// The accent is hi-vis orange (the colour of things that haul cargo), not
/// the indigo every generated UI defaults to. Every text pair here meets
/// WCAG AA (4.5:1); see docs/DESIGN.md for the numbers.
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
    bg: Color(0xFFF5F4F0),
    surface: Color(0xFFFBFAF7),
    sunken: Color(0xFFECEBE6),
    line: Color(0xFFE0DED8),
    ink: Color(0xFF1A1917),
    ink2: Color(0xFF5C5A55),
    ink3: Color(0xFF65635D),
    accent: Color(0xFFB53F0B),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFB3123E),
  );

  static const dark = Palette(
    bg: Color(0xFF111110),
    surface: Color(0xFF1A1918),
    sunken: Color(0xFF242321),
    line: Color(0xFF302F2C),
    ink: Color(0xFFEFEDE8),
    ink2: Color(0xFFADABA4),
    ink3: Color(0xFF93918A),
    accent: Color(0xFFFF8A4C),
    onAccent: Color(0xFF111110),
    danger: Color(0xFFFF6B8B),
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

/// Motion tokens. Motion here only ever reports a change of state (added,
/// finished, moved); nothing loops for decoration and nothing bounces.
///
/// When the OS asks for reduced motion ([reduced], set from
/// `MediaQuery.disableAnimations` at the root), every duration collapses
/// to zero and changes simply happen.
abstract final class Motion {
  static bool reduced = false;
  static Duration _d(int ms) => reduced ? Duration.zero : Duration(milliseconds: ms);
  static Duration get fast => _d(140);
  static Duration get normal => _d(220);
  static Duration get slow => _d(360);
  static const ease = Cubic(0.2, 0.0, 0.0, 1.0);
  static const easeOut = Curves.easeOutCubic;
  static const easeIn = Curves.easeInCubic;
}

/// Radius is semantic, not decorative: small for controls, a little more
/// for containers, only sheets get a soft top edge.
abstract final class Radii {
  static const sm = 6.0; // chips, tags, inline controls
  static const md = 8.0; // buttons, inputs, rows, thumbnails
  static const lg = 12.0; // cards, dialogs, toasts
  static const xl = 16.0; // bottom sheets
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
  TextTheme get text => Theme.of(this).textTheme;

  /// For text that really is code: pairing codes, addresses, file paths.
  TextStyle get mono => TextStyle(fontFamily: 'PlexMono', fontSize: 13, color: palette.ink2, height: 1.4);
}

const _tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;

  TextStyle s(double size, FontWeight w, Color c, {double ls = 0, double h = 1.35}) => TextStyle(
        fontFamily: 'Plex',
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: ls,
        height: h,
        fontFeatures: _tabular,
      );

  // A 1.2 modular scale from a 14px body. Headings at 600, never 700:
  // weight does the work a gradient or a giant size would do elsewhere.
  final text = TextTheme(
    displaySmall: s(28, FontWeight.w600, p.ink, ls: -0.5, h: 1.15),
    headlineSmall: s(22, FontWeight.w600, p.ink, ls: -0.3, h: 1.2),
    titleLarge: s(18, FontWeight.w600, p.ink, ls: -0.2, h: 1.3),
    titleMedium: s(15.5, FontWeight.w600, p.ink, ls: -0.1),
    titleSmall: s(14, FontWeight.w600, p.ink),
    bodyLarge: s(15.5, FontWeight.w400, p.ink, h: 1.45),
    bodyMedium: s(14, FontWeight.w400, p.ink, h: 1.45),
    bodySmall: s(13, FontWeight.w400, p.ink2, h: 1.4),
    labelLarge: s(14, FontWeight.w600, p.ink),
    labelMedium: s(13, FontWeight.w500, p.ink2),
    labelSmall: s(12, FontWeight.w500, p.ink3, h: 1.3),
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
    fontFamily: 'Plex',
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
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : p.ink3),
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
