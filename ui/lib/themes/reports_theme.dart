import 'package:flutter/material.dart';
import 'report_palette.dart';

/// Reports fallback theme in the asodya.com brand: charcoal and white surfaces, neon purple
/// for actions, lime (dark) or cyan (light) for highlights, neon state colors. Text colors
/// keep AA contrast: the dark accent is a lighter purple with dark text on it.
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
          accent: Color(0xFFA47BFF),
          onAccent: Color(0xFF0B0C10),
          highlight: neonLime,
          positive: Color(0xFF00E676),
          warning: Color(0xFFFFD60A),
          negative: Color(0xFFFF1744),
          info: neonCyan,
          caution: Color(0xFFFF9100),
          // Validated categorical order (dataviz checks pass on dark surfaces).
          series: [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500), Color(0xFFD55181), Color(0xFF008300), Color(0xFF9085E9), Color(0xFFE66767)],
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
          highlight: Color(0xFF0891B2),
          positive: Color(0xFF16A34A),
          warning: Color(0xFFEAB308),
          negative: Color(0xFFDC2626),
          info: Color(0xFF0284C7),
          caution: Color(0xFFEA580C),
          // Validated categorical order (dataviz checks pass on light surfaces).
          series: [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF008300), Color(0xFF6250D6), Color(0xFFE34948)],
          other: Color(0xFFA8A8A8),
        );
}
