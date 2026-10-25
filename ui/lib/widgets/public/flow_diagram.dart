import 'package:flutter/material.dart';
import '../../themes/report_palette.dart';
import 'public_motion.dart';

/// One step of the data path.
class FlowStep {
  final String title;
  final String detail;
  final IconData icon;

  const FlowStep(this.title, this.detail, this.icon);
}

/// Animated data path: the steps appear one by one, then data dots travel along the
/// links twice. Wide panels draw a row, narrow panels a column. The marks use the chart
/// series colors; the texts use the text colors. Reduced motion shows the final state.
class FlowDiagram extends StatelessWidget {
  final List<FlowStep> steps;

  const FlowDiagram({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('flow_diagram'),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius)),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, c) {
        final row = c.maxWidth >= 560;
        return PlayWhenVisible(
          duration: const Duration(milliseconds: 5200),
          curve: Curves.linear,
          builder: (context, t) {
            final nodes = [
              for (var i = 0; i < steps.length; i++)
                _Node(step: steps[i], color: _brand(p, i), t: ((t * 2.2) - i * 0.18).clamp(0.0, 1.0)),
            ];
            // The link line goes under the steps, the data dots over them.
            Widget paint(Widget child) => CustomPaint(
                  painter: _LinkPainter(count: steps.length, row: row, t: t, palette: p, dots: false),
                  foregroundPainter: _LinkPainter(count: steps.length, row: row, t: t, palette: p, dots: true),
                  child: child,
                );
            if (row) {
              // Every step gets the height of the tallest one.
              return paint(IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < nodes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: nodes[i]),
                  ],
                ]),
              ));
            }
            return paint(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < nodes.length; i++) ...[
                if (i > 0) const SizedBox(height: 18),
                nodes[i],
              ],
            ]));
          },
        );
      }),
    );
  }
}

class _Node extends StatelessWidget {
  final FlowStep step;
  final Color color;
  final double t;

  const _Node({required this.step, required this.color, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - t)),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
            border: Border(top: BorderSide(color: color, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Icon(step.icon, size: 20, color: p.textPrimary),
            const SizedBox(height: 10),
            Text(step.title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.textPrimary, height: 1.25)),
            const SizedBox(height: 4),
            Text(step.detail, style: TextStyle(fontSize: 12, color: p.textMuted, height: 1.35)),
          ]),
        ),
      ),
    );
  }
}

/// Links between the steps and the data dots that travel on them.
class _LinkPainter extends CustomPainter {
  final int count;
  final bool row;
  final double t;
  final ReportPalette palette;

  /// True for the data dots (foreground), false for the link line (background).
  final bool dots;

  _LinkPainter({required this.count, required this.row, required this.t, required this.palette, required this.dots});

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) return;
    final line = Paint()
      ..color = palette.border
      ..strokeWidth = 2;
    // Centers of the steps along the main axis (the steps share the space evenly).
    final main = row ? size.width : size.height;
    final step = main / count;
    final cross = row ? 34.0 : 24.0;
    Offset at(double m) => row ? Offset(m, cross) : Offset(cross, m);
    final start = at(step / 2);
    final end = at(main - step / 2);
    if (!dots) {
      final drawn = ((t * 2.2) - 0.1).clamp(0.0, 1.0);
      canvas.drawLine(start, Offset.lerp(start, end, drawn)!, line);
      return;
    }
    // Two passes of data dots after the steps appear; none at the end of the run.
    final travel = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (travel <= 0 || travel >= 1) return;
    for (var pass = 0; pass < 2; pass++) {
      final local = ((travel * 2) - pass).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      for (var k = 0; k < 3; k++) {
        final pos = (local - k * 0.06).clamp(0.0, 1.0);
        if (pos <= 0) continue;
        final segment = (pos * (count - 1)).floor().clamp(0, count - 2);
        final dot = Paint()..color = palette.seriesAt(segment + 1).withValues(alpha: 1 - k * 0.3);
        canvas.drawCircle(Offset.lerp(start, end, pos)!, 5 - k.toDouble(), dot);
      }
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => old.t != t || old.row != row || old.palette != palette || old.dots != dots;
}

/// Brand color of a step: accent, highlight, info, caution, positive, in turn.
Color _brand(ReportPalette p, int i) => [p.accent, p.highlight, p.info, p.caution, p.positive][i % 5];
