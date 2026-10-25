import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';
import 'public_layout.dart';
import 'public_motion.dart';

/// Decorative charts of the Science pages, drawn with CustomPainter. They illustrate a
/// method; they are not real data (the frame says so). Marks use the chart series colors,
/// texts use the text colors. Each animation plays once when the chart comes into view.

/// Frame of a decorative chart: title, legend, the chart, and the "illustration" note.
class IllustrationFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final List<(Color, String)> legend;

  const IllustrationFrame({super.key, required this.title, required this.child, this.legend = const []});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: publicCardColor(context), borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textPrimary)),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            for (final (color, label) in legend)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 3, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: p.textMuted)),
              ]),
          ]),
        ],
        const SizedBox(height: 16),
        child,
        const SizedBox(height: 10),
        Text(context.tr('pub_sci_illustration'), style: TextStyle(fontSize: 11.5, color: p.textMuted)),
      ]),
    );
  }
}

/// Animated chart of a fixed height: the painter gets the progress (0 to 1).
class _Animated extends StatelessWidget {
  final double height;
  final Duration duration;
  final bool staticOnPhone;
  final CustomPainter Function(double t, ReportPalette p) painter;

  const _Animated({required this.height, required this.painter, this.duration = const Duration(milliseconds: 1600), this.staticOnPhone = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      child: PlayWhenVisible(
        duration: duration,
        staticOnPhone: staticOnPhone,
        builder: (context, t) => CustomPaint(size: Size.infinite, painter: painter(t, p)),
      ),
    );
  }
}

void _grid(Canvas canvas, Size size, ReportPalette p, {int lines = 4}) {
  final paint = Paint()
    ..color = p.border
    ..strokeWidth = 1;
  for (var i = 0; i <= lines; i++) {
    final y = size.height * i / lines;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
}

/// Bars that grow one after the other (records per day).
class GrowingBars extends StatelessWidget {
  const GrowingBars({super.key});

  static final List<double> values = [for (var i = 0; i < 14; i++) 0.45 + 0.35 * math.sin(i * 0.7).abs() + 0.15 * ((i * 37) % 7) / 7];

  @override
  Widget build(BuildContext context) => IllustrationFrame(
        key: const Key('chart_bars'),
        title: context.tr('pub_chart_records'),
        child: _Animated(height: 180, painter: (t, p) => _BarsPainter(values, t, p)),
      );
}

class _BarsPainter extends CustomPainter {
  final List<double> values;
  final double t;
  final ReportPalette p;

  _BarsPainter(this.values, this.t, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size, p);
    final gap = 6.0;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    final paint = Paint()..color = p.seriesAt(0);
    for (var i = 0; i < values.length; i++) {
      final local = ((t * 1.6) - i * 0.04).clamp(0.0, 1.0);
      final h = size.height * values[i] * Curves.easeOutCubic.transform(local);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.p != p;
}

/// Two loss curves that draw from left to right (training and validation).
class LossCurves extends StatelessWidget {
  const LossCurves({super.key});

  static double train(double x) => 0.08 + 0.9 * math.exp(-4.2 * x) + 0.015 * math.sin(x * 40);
  static double validation(double x) => 0.16 + 0.82 * math.exp(-3.4 * x) + 0.05 * x * x + 0.02 * math.sin(x * 23);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IllustrationFrame(
      key: const Key('chart_loss'),
      title: context.tr('pub_chart_loss'),
      legend: [(p.seriesAt(0), context.tr('pub_chart_train')), (p.seriesAt(1), context.tr('pub_chart_val'))],
      child: _Animated(height: 200, duration: const Duration(milliseconds: 2200), painter: (t, p) => _LossPainter(t, p)),
    );
  }
}

class _LossPainter extends CustomPainter {
  final double t;
  final ReportPalette p;

  _LossPainter(this.t, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size, p);
    for (final (f, color) in [(LossCurves.train, p.seriesAt(0)), (LossCurves.validation, p.seriesAt(1))]) {
      final path = Path();
      const steps = 120;
      final last = (steps * t).round();
      for (var i = 0; i <= last; i++) {
        final x = i / steps;
        final pt = Offset(x * size.width, size.height * (1 - f(x).clamp(0.0, 1.0)));
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_LossPainter old) => old.t != t || old.p != p;
}

/// Scatter points that appear, then a fitted line that draws over them.
class ScatterFit extends StatelessWidget {
  const ScatterFit({super.key});

  static final List<Offset> points = () {
    final r = math.Random(7);
    return [
      for (var i = 0; i < 60; i++)
        () {
          final x = r.nextDouble();
          final noise = (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) * 0.18;
          return Offset(x, (0.15 + 0.7 * x + noise).clamp(0.02, 0.98));
        }(),
    ];
  }();

  @override
  Widget build(BuildContext context) => IllustrationFrame(
        key: const Key('chart_scatter'),
        title: context.tr('pub_chart_scatter'),
        child: _Animated(height: 220, duration: const Duration(milliseconds: 2000), painter: (t, p) => _ScatterPainter(t, p)),
      );
}

class _ScatterPainter extends CustomPainter {
  final double t;
  final ReportPalette p;

  _ScatterPainter(this.t, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size, p);
    final pts = ScatterFit.points;
    final dot = Paint()..color = p.seriesAt(2).withValues(alpha: 0.75);
    for (var i = 0; i < pts.length; i++) {
      final local = ((t / 0.6) - i / pts.length * 0.6).clamp(0.0, 1.0);
      if (local <= 0) continue;
      canvas.drawCircle(Offset(pts[i].dx * size.width, (1 - pts[i].dy) * size.height), 4 * Curves.easeOutBack.transform(local), dot);
    }
    // Least squares line through the points.
    final n = pts.length;
    final mx = pts.fold<double>(0, (a, o) => a + o.dx) / n;
    final my = pts.fold<double>(0, (a, o) => a + o.dy) / n;
    var sxy = 0.0, sxx = 0.0;
    for (final o in pts) {
      sxy += (o.dx - mx) * (o.dy - my);
      sxx += (o.dx - mx) * (o.dx - mx);
    }
    final b = sxy / sxx;
    final a = my - b * mx;
    final line = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    if (line > 0) {
      final start = Offset(0, (1 - a) * size.height);
      final end = Offset(size.width, (1 - (a + b)) * size.height);
      canvas.drawLine(
        start,
        Offset.lerp(start, end, line)!,
        Paint()
          ..color = p.seriesAt(1)
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) => old.t != t || old.p != p;
}

/// Bell curve that draws, with the area within one standard deviation filled.
class BellCurve extends StatelessWidget {
  const BellCurve({super.key});

  @override
  Widget build(BuildContext context) => IllustrationFrame(
        key: const Key('chart_bell'),
        title: context.tr('pub_chart_bell'),
        child: _Animated(height: 200, duration: const Duration(milliseconds: 1800), painter: (t, p) => _BellPainter(t, p)),
      );
}

class _BellPainter extends CustomPainter {
  final double t;
  final ReportPalette p;

  _BellPainter(this.t, this.p);

  static double pdf(double z) => math.exp(-z * z / 2);

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size, p);
    Offset at(double z) => Offset((z + 3.5) / 7 * size.width, size.height * (1 - 0.92 * pdf(z)));
    final reveal = Curves.easeInOut.transform(t);
    final fill = Path()..moveTo(at(-1).dx, size.height);
    for (var z = -1.0; z <= 1.0001; z += 0.05) {
      fill.lineTo(at(z).dx, at(z).dy);
    }
    fill
      ..lineTo(at(1).dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = p.seriesAt(3).withValues(alpha: 0.25 * reveal));
    final curve = Path();
    final end = -3.5 + 7 * reveal;
    for (var z = -3.5; z <= end; z += 0.05) {
      final o = at(z);
      z == -3.5 ? curve.moveTo(o.dx, o.dy) : curve.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = p.seriesAt(3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final mean = Paint()
      ..color = p.textMuted
      ..strokeWidth = 1;
    if (reveal > 0.5) canvas.drawLine(Offset(at(0).dx, size.height), Offset(at(0).dx, at(0).dy), mean);
  }

  @override
  bool shouldRepaint(_BellPainter old) => old.t != t || old.p != p;
}

/// Small neural network: the links draw layer by layer, then one signal passes through.
/// Phones show the final state without motion.
class NeuralNetDiagram extends StatelessWidget {
  const NeuralNetDiagram({super.key});

  static const List<int> layers = [4, 6, 6, 3];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IllustrationFrame(
      key: const Key('chart_network'),
      title: context.tr('pub_chart_net'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Animated(height: 220, duration: const Duration(milliseconds: 3200), staticOnPhone: true, painter: (t, p) => _NetPainter(t, p)),
        const SizedBox(height: 8),
        Row(children: [
          for (final (i, key) in [(0, 'pub_layer_in'), (1, 'pub_layer_hidden'), (2, 'pub_layer_hidden'), (3, 'pub_layer_out')])
            Expanded(
              child: Text(context.tr(key),
                  textAlign: i == 0 ? TextAlign.left : (i == 3 ? TextAlign.right : TextAlign.center),
                  style: TextStyle(fontSize: 12, color: p.textMuted)),
            ),
        ]),
      ]),
    );
  }
}

class _NetPainter extends CustomPainter {
  final double t;
  final ReportPalette p;

  _NetPainter(this.t, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final layers = NeuralNetDiagram.layers;
    const pad = 14.0;
    List<Offset> nodes(int l) {
      final x = pad + (size.width - 2 * pad) * l / (layers.length - 1);
      final n = layers[l];
      return [for (var i = 0; i < n; i++) Offset(x, size.height * (i + 0.5) / n)];
    }

    final all = [for (var l = 0; l < layers.length; l++) nodes(l)];
    // Links appear layer by layer in the first half of the run.
    for (var l = 0; l < layers.length - 1; l++) {
      final local = ((t * 2) - l * 0.3).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final link = Paint()
        ..color = p.textMuted.withValues(alpha: 0.35 * local)
        ..strokeWidth = 1;
      for (final a in all[l]) {
        for (final b in all[l + 1]) {
          canvas.drawLine(a, Offset.lerp(a, b, local)!, link);
        }
      }
    }
    // One signal passes through the network in the second half; it stays lit at the end.
    final signal = ((t - 0.5) / 0.5).clamp(0.0, 1.0) * (layers.length - 1);
    for (var l = 0; l < layers.length; l++) {
      final lit = (signal - l + 1).clamp(0.0, 1.0);
      for (var i = 0; i < all[l].length; i++) {
        final o = all[l][i];
        canvas.drawCircle(o, 9, Paint()..color = p.canvas);
        canvas.drawCircle(
          o,
          9,
          Paint()
            ..color = p.seriesAt(l)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        // A fixed pattern of active nodes, the same on every run.
        final active = (i * 7 + l * 3) % 3 != 0 || l == 0;
        if (lit > 0 && active) {
          canvas.drawCircle(o, 6 * lit, Paint()..color = p.seriesAt(l));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NetPainter old) => old.t != t || old.p != p;
}
