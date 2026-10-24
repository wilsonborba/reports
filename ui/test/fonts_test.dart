import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:reports_ui/themes/theme_registry.dart';

void main() {
  test('every font file in pubspec.yaml exists, with the license', () {
    final assets = RegExp(r'asset: (assets/fonts/\S+\.ttf)').allMatches(File('pubspec.yaml').readAsStringSync()).map((m) => m.group(1)!).toList();
    expect(assets.length, 7);
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
  });

  test('the theme uses Ubuntu Sans with IBM Plex Sans Thai as fallback, no runtime download', () {
    final theme = ThemeRegistry.theme(null, Brightness.light);
    expect(theme.textTheme.bodyMedium!.fontFamily, ReportPalette.font);
    expect(theme.textTheme.bodyMedium!.fontFamilyFallback, [ReportPalette.thaiFont]);
    expect(File('pubspec.yaml').readAsStringSync().contains('google_fonts'), isFalse);
  });

  testWidgets('the bundled Thai font loads and shapes Thai text', (tester) async {
    final loader = FontLoader(ReportPalette.thaiFont)..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    await loader.load();
    final painter = TextPainter(
      text: const TextSpan(text: 'ที่นี่ ปริมาณรถ', style: TextStyle(fontFamily: ReportPalette.thaiFont, fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.width, greaterThan(50));
  });
}
