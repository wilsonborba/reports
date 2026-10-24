import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import '../themes/report_palette.dart';

/// Thai text for the PDF. The PDF library has no Thai shaping (tone marks after upper
/// vowels land inside the vowel), so Thai text becomes a small image that the browser
/// draws with the bundled Thai fallback font.
class ThaiText {
  static final RegExp _thai = RegExp(r'[฀-๿]');

  static bool has(String s) => _thai.hasMatch(s);
}

/// A drawn text: PNG bytes and the size in PDF points.
class TextImage {
  final Uint8List png;
  final double width;
  final double height;

  const TextImage(this.png, this.width, this.height);
}

/// Draws [text] at [fontSize] points, wrapped at [maxWidth] points.
typedef TextImageRenderer = Future<TextImage> Function(String text, {required double fontSize, required bool bold, required double maxWidth, required int color});

/// Pixels per PDF point of the text images (sharp in print).
const double textImageScale = 3;

/// Renderer with the app fonts (dart:ui), for the browser.
Future<TextImage> renderTextImage(String text, {required double fontSize, required bool bold, required double maxWidth, required int color}) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: ReportPalette.thaiFont,
        fontFamilyFallback: const [ReportPalette.font],
        fontSize: fontSize * textImageScale,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: Color(color),
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth * textImageScale);
  final w = painter.width.ceil().clamp(1, 1 << 14), h = painter.height.ceil().clamp(1, 1 << 14);
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), Offset.zero);
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  painter.dispose();
  return TextImage(data!.buffer.asUint8List(), w / textImageScale, h / textImageScale);
}
