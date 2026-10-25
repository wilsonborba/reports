import 'package:flutter/material.dart';
import 'report_palette.dart';

/// Reports fallback theme in the asodya.com colors (domain repository): neon lime with black
/// in the dark theme, purple with white in the light theme, on the controls only (buttons,
/// selected tab, links). Charts use soft, varied colors with no blue, so a dashboard does
/// not repeat the brand colors everywhere; both chart orders pass every dataviz check
/// (lightness band, colorblind and normal-vision separation).
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
          positive: Color(0xFF3FB950),
          warning: Color(0xFFD4A72C),
          negative: Color(0xFFF85149),
          info: Color(0xFF2AA9C2),
          caution: Color(0xFFDB8B2E),
          // Soft and varied chart colors (no blue; the brand lime and purple stay on the
          // controls): orange, cyan, coral, lavender, green, pink, amber, teal.
          series: [Color(0xFFD95926), Color(0xFF0AA5B8), Color(0xFFE66767), Color(0xFF9085E9), Color(0xFF3F9E1E), Color(0xFFD55181), Color(0xFFC98500), Color(0xFF199E70)],
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
          // Soft and varied chart colors (no blue; the brand purple stays on the controls):
          // orange, teal, green, pink, amber, red, violet, sea green.
          series: [Color(0xFFEB6834), Color(0xFF0F9FA8), Color(0xFF008300), Color(0xFFE87BA4), Color(0xFFEDA100), Color(0xFFE34948), Color(0xFF6250D6), Color(0xFF1BAF7A)],
          other: Color(0xFFA8A8A8),
        );
}
