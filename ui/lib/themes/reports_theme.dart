import 'package:flutter/material.dart';
import 'report_palette.dart';

/// Reports fallback theme in the asodya.com colors (domain repository, `my_theme.dart` and the
/// landing): neon lime with black in the dark theme, neon purple with white in the light
/// theme, and the other asodya.com neons (orange, cyan, pink, yellow, violet, teal) for
/// charts and states. No blue. Chart orders pass the dataviz checks (colorblind separation
/// and normal vision); the dark neons are brighter than the usual band on purpose (brand).
class ReportsTheme {
  static const neonPurple = Color(0xFF8C52FF);
  static const neonLime = Color(0xFF6EFF00);
  static const neonCyan = Color(0xFF00E5FF);

  static ReportPalette palette(Brightness b) => b == Brightness.dark
      ? const ReportPalette(
          canvas: Color(0xFF0B0C10),
          surface: Color(0xFF12151E),
          surfaceAlt: Color(0xFF1A1E2B),
          border: Color(0xFF272D3D),
          textPrimary: Color(0xFFF4F4F5),
          textMuted: Color(0xFF9CA3AF),
          accent: neonLime,
          onAccent: Color(0xFF0B0C10),
          highlight: Color(0xFFA47BFF),
          positive: Color(0xFF00E676),
          warning: Color(0xFFFFD60A),
          negative: Color(0xFFFF1744),
          info: neonCyan,
          caution: Color(0xFFFF9100),
          // Lime, purple, orange, cyan, pink, yellow, violet, teal.
          series: [neonLime, neonPurple, Color(0xFFFF9100), neonCyan, Color(0xFFFF4FA3), Color(0xFFFFD60A), Color(0xFFA201FF), Color(0xFF1DE9B6)],
          other: Color(0xFF6F6F6F),
        )
      : const ReportPalette(
          canvas: Color(0xFFFFFFFF),
          surface: Color(0xFFF4F4F5),
          surfaceAlt: Color(0xFFE9E9EC),
          border: Color(0xFFE4E4E7),
          textPrimary: Color(0xFF1E1E1E),
          textMuted: Color(0xFF52525B),
          accent: Color(0xFF7C3AED),
          onAccent: Color(0xFFFFFFFF),
          highlight: Color(0xFF16A34A),
          positive: Color(0xFF16A34A),
          warning: Color(0xFFCA8A04),
          negative: Color(0xFFDC2626),
          info: Color(0xFF0891B2),
          caution: Color(0xFFEA580C),
          // Purple, green, cyan, orange, teal, violet, pink, amber.
          series: [Color(0xFF7C3AED), Color(0xFF16A34A), Color(0xFF0891B2), Color(0xFFEA580C), Color(0xFF0D9488), Color(0xFFA201FF), Color(0xFFDB2777), Color(0xFFCA8A04)],
          other: Color(0xFFA8A8A8),
        );
}
