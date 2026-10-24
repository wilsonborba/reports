import 'package:flutter/material.dart';

/// Colors of one theme in one brightness. Every widget reads its colors from here
/// (`context.palette`). Project palettes come from the API theme tokens; the only
/// built-in palette is the neutral Reports theme (the fallback).
@immutable
class ReportPalette extends ThemeExtension<ReportPalette> {
  final Color canvas;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color positive;
  final Color warning;
  final Color negative;
  final Color info;
  final Color caution;

  /// Series colors for charts (8 slots), assigned in this fixed order.
  final List<Color> series;

  /// Gray for the folded "Other" category.
  final Color other;

  const ReportPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.positive,
    required this.warning,
    required this.negative,
    required this.info,
    required this.caution,
    required this.series,
    this.other = const Color(0xFFA8A8A8),
  });

  /// Number of categorical slots; a 9th category folds into [other].
  static const int slots = 8;

  /// Color of a series slot. Slots past the palette use [other], never a cycled color.
  Color seriesAt(int index) => index >= 0 && index < series.length && index < slots ? series[index] : other;

  /// Palette from API theme tokens (`#RRGGBB` strings). Null when a token is missing or invalid.
  static ReportPalette? fromTokens(Map<String, dynamic>? t) {
    if (t == null) return null;
    Color? c(dynamic v) {
      final s = '$v';
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return null;
      return Color(int.parse('FF${s.substring(1)}', radix: 16));
    }
    final names = ['canvas', 'surface', 'surface_alt', 'border', 'text_primary', 'text_muted', 'accent', 'on_accent',
        'positive', 'warning', 'negative', 'info', 'caution', 'other'];
    final v = {for (final n in names) n: c(t[n])};
    final series = (t['series'] is List) ? (t['series'] as List).map(c).toList() : <Color?>[];
    if (v.values.any((x) => x == null) || series.isEmpty || series.any((x) => x == null)) return null;
    return ReportPalette(
      canvas: v['canvas']!,
      surface: v['surface']!,
      surfaceAlt: v['surface_alt']!,
      border: v['border']!,
      textPrimary: v['text_primary']!,
      textMuted: v['text_muted']!,
      accent: v['accent']!,
      onAccent: v['on_accent']!,
      positive: v['positive']!,
      warning: v['warning']!,
      negative: v['negative']!,
      info: v['info']!,
      caution: v['caution']!,
      series: series.cast<Color>(),
      other: v['other']!,
    );
  }

  @override
  ReportPalette copyWith({Color? accent, Color? onAccent, List<Color>? series}) => ReportPalette(
        canvas: canvas,
        surface: surface,
        surfaceAlt: surfaceAlt,
        border: border,
        textPrimary: textPrimary,
        textMuted: textMuted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        positive: positive,
        warning: warning,
        negative: negative,
        info: info,
        caution: caution,
        series: series ?? this.series,
        other: other,
      );

  @override
  ReportPalette lerp(ReportPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ReportPalette(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      positive: l(positive, other.positive),
      warning: l(warning, other.warning),
      negative: l(negative, other.negative),
      info: l(info, other.info),
      caution: l(caution, other.caution),
      series: t < 0.5 ? series : other.series,
      other: l(this.other, other.other),
    );
  }

  /// Main font family (bundled). Thai text falls back to [thaiFont]; equations use [monoFont].
  static const String font = 'Ubuntu Sans';
  static const String thaiFont = 'IBM Plex Sans Thai';
  static const String monoFont = 'Ubuntu Sans Mono';
  static const List<String> fontFallback = [thaiFont];

  /// Corners of the flat Carbon style: surfaces (cards, tiles, panels) and controls
  /// (buttons, inputs, menus, chips). Chart marks keep their own rounded bar ends.
  static const double surfaceRadius = 4;
  static const double controlRadius = 2;

  /// Builds the Material theme from a palette. Ubuntu Sans with Thai fallback.
  ThemeData toTheme(Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: font, fontFamilyFallback: fontFallback);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: info,
      onSecondary: canvas,
      error: negative,
      onError: canvas,
      surface: surface,
      onSurface: textPrimary,
      outline: border,
      outlineVariant: border,
      surfaceContainerHighest: surfaceAlt,
    );
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius));
    final surfaceShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(surfaceRadius));
    return base.copyWith(
      colorScheme: scheme,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: control)),
      // Text and outline buttons use the text color: a light project color (yellow) has no
      // contrast as text on a light surface.
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: control, foregroundColor: textPrimary, side: BorderSide(color: textMuted))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: control, foregroundColor: textPrimary)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: control)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: control)),
      menuTheme: MenuThemeData(style: MenuStyle(shape: WidgetStatePropertyAll(surfaceShape))),
      popupMenuTheme: PopupMenuThemeData(shape: surfaceShape, color: surface),
      dialogTheme: DialogThemeData(shape: surfaceShape, backgroundColor: surface),
      chipTheme: ChipThemeData(shape: control),
      cardTheme: CardThemeData(shape: surfaceShape, elevation: 0, color: surface),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(controlRadius)),
      ),
      snackBarTheme: SnackBarThemeData(shape: surfaceShape, behavior: SnackBarBehavior.floating),
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      dividerColor: border,
      textTheme: base.textTheme.apply(fontFamily: font, fontFamilyFallback: fontFallback, bodyColor: textPrimary, displayColor: textPrimary),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: font, fontFamilyFallback: fontFallback),
      iconTheme: IconThemeData(color: textPrimary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: textPrimary, borderRadius: BorderRadius.circular(controlRadius)),
        textStyle: TextStyle(fontFamily: font, fontFamilyFallback: fontFallback, color: canvas, fontSize: 12),
      ),
      extensions: [this],
    );
  }
}

extension PaletteContext on BuildContext {
  /// Palette of the active theme.
  ReportPalette get palette => Theme.of(this).extension<ReportPalette>()!;
}
