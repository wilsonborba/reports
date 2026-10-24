import 'package:flutter/material.dart';
import 'report_palette.dart';

/// Reports fallback theme: black and white, monochrome surfaces, normal colors on buttons and states.
class ReportsTheme {
  static const _green = Color(0xFF16A34A);
  static const _blue = Color(0xFF2563EB);
  static const _yellow = Color(0xFFEAB308);
  static const _orange = Color(0xFFEA580C);
  static const _red = Color(0xFFDC2626);

  static ReportPalette palette(Brightness b) => b == Brightness.dark
      ? const ReportPalette(
          canvas: Color(0xFF0A0A0A),
          surface: Color(0xFF151515),
          surfaceAlt: Color(0xFF1F1F1F),
          border: Color(0xFF2E2E2E),
          textPrimary: Color(0xFFF5F5F5),
          textMuted: Color(0xFF9E9E9E),
          accent: Color(0xFFFFFFFF),
          onAccent: Color(0xFF0A0A0A),
          positive: _green,
          warning: _yellow,
          negative: _red,
          info: _blue,
          caution: _orange,
          // Validated categorical order (dataviz checks pass on dark surfaces).
          series: [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500), Color(0xFFD55181), Color(0xFF008300), Color(0xFF9085E9), Color(0xFFE66767)],
          other: Color(0xFF6F6F6F),
        )
      : const ReportPalette(
          canvas: Color(0xFFFFFFFF),
          surface: Color(0xFFF7F7F7),
          surfaceAlt: Color(0xFFEDEDED),
          border: Color(0xFFDCDCDC),
          textPrimary: Color(0xFF111111),
          textMuted: Color(0xFF616161),
          accent: Color(0xFF111111),
          onAccent: Color(0xFFFFFFFF),
          positive: _green,
          warning: _yellow,
          negative: _red,
          info: _blue,
          caution: _orange,
          // Validated categorical order (dataviz checks pass on light surfaces).
          series: [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF008300), Color(0xFF6250D6), Color(0xFFE34948)],
          other: Color(0xFFA8A8A8),
        );
}
