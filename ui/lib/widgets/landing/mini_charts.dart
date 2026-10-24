import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/catalog.dart';
import '../../themes/report_palette.dart';
import '../charts/motion.dart';

/// Small chart frame of a project tile: a label and the chart below it.
class MiniChartFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const MiniChartFrame({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.textMuted, letterSpacing: 0.2)),
      const SizedBox(height: 8),
      child,
    ]);
  }
}

/// Top values per report as thin horizontal bars (one color). The rest of the reports
/// fold into one "+ N more" line.
class MiniBars extends StatelessWidget {
  final List<ReportCount> items;
  final int top;
  final String Function(int value) format;
  final String moreLabel;

  const MiniBars({super.key, required this.items, required this.format, required this.moreLabel, this.top = 4});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sorted = [...items]..sort((a, b) => b.value.compareTo(a.value));
    final shown = sorted.take(top).toList();
    final maxV = shown.isEmpty ? 0 : shown.first.value;
    final color = p.seriesAt(0);
    return EntryAnimation(
      duration: const Duration(milliseconds: 600),
      builder: (context, t) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < shown.length; i++)
          Tooltip(
            message: '${shown[i].title}: ${format(shown[i].value)}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  flex: 5,
                  child: Text(shown[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.textPrimary)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 6,
                        width: maxV <= 0 ? 0 : math.max(2.0, c.maxWidth * shown[i].value / maxV * staggered(t, i, shown.length)),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  child: Text(format(shown[i].value),
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
          ),
        if (sorted.length > top)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(moreLabel, style: TextStyle(fontSize: 11, color: p.textMuted)),
          ),
      ]),
    );
  }
}

/// Rows per day as a small area line. The first and the last day show below it.
class Sparkline extends StatelessWidget {
  final List<DayCount> days;
  final double height;

  /// Tooltip text (the period and the total rows).
  final String tooltip;

  const Sparkline({super.key, required this.days, required this.tooltip, this.height = 56});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (days.isEmpty) return SizedBox(height: height);
    return Tooltip(
      message: tooltip,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EntryAnimation(
          duration: const Duration(milliseconds: 700),
          builder: (context, t) => SizedBox(
            height: height,
            child: CustomPaint(painter: _SparkPainter(days: days, color: p.seriesAt(0), t: t)),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(days.first.date, style: TextStyle(fontSize: 10.5, color: p.textMuted)),
          const Spacer(),
          Text(days.last.date, style: TextStyle(fontSize: 10.5, color: p.textMuted)),
        ]),
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<DayCount> days;
  final Color color;
  final double t;

  _SparkPainter({required this.days, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = days.map((d) => d.rows).fold<int>(0, math.max);
    if (maxV <= 0) return;
    final n = days.length;
    Offset at(int i) => Offset(n == 1 ? size.width / 2 : size.width * i / (n - 1), size.height - 2 - (size.height - 4) * days[i].rows / maxV);
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(n - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.days != days || old.color != color || old.t != t;
}
