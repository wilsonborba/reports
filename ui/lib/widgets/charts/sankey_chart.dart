import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'chart_parts.dart';
import 'format.dart';
import 'motion.dart';
import 'sankey_layout.dart';
import 'series_colors.dart';

/// Sankey diagram: flows of one measure through 2 to 4 category stages. Nodes of the
/// first stage take the color of their category and the links carry it; nodes of later
/// stages are neutral, so one color never names two categories. Hover (or tap) on a
/// node highlights its links; hover on a link shows its value and its share of the
/// source. The flows draw from left to right once.
class SankeyChart extends StatefulWidget {
  final DatasetPage page;
  final List<FieldInfo> stages;
  final FieldInfo measure;

  /// Height of the chart on a board card; null takes a height from the node count.
  final double? height;

  /// Largest height when [height] is null (full view frame).
  final double? maxHeight;

  const SankeyChart({super.key, required this.page, required this.stages, required this.measure, this.height, this.maxHeight});

  @override
  State<SankeyChart> createState() => _SankeyChartState();
}

class _SankeyChartState extends State<SankeyChart> {
  SankeyNode? _node;
  SankeyLink? _link;
  Offset? _pointer;

  void _setHover(SankeyNode? node, SankeyLink? link, Offset? at) {
    if (node == _node && link == _link && at == _pointer) return;
    setState(() {
      _node = node;
      _link = link;
      _pointer = at;
    });
  }

  static Path _band(SankeyLink l) {
    final x0 = l.source.x + l.source.width, x1 = l.target.x, xm = (x0 + x1) / 2;
    final y0 = l.sourceY, y1 = l.targetY, t = math.max(1.0, l.thickness);
    return Path()
      ..moveTo(x0, y0)
      ..cubicTo(xm, y0, xm, y1, x1, y1)
      ..lineTo(x1, y1 + t)
      ..cubicTo(xm, y1 + t, xm, y0 + t, x0, y0 + t)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = SeriesColorScope.of(context);
    final layout = SankeyLayout.build(widget.page.rows, widget.stages, widget.measure, domain: colors.domain);
    if (layout.isEmpty) return Text(context.tr('no_data'), style: TextStyle(color: p.textMuted));
    String name(SankeyNode n) => n.isOther ? context.tr('other') : valueText(n.raw, widget.stages[n.stage]);
    Color colorOf(SankeyNode n) {
      if (n.stage > 0) return p.textMuted;
      if (n.isOther) return p.other;
      return colors.color(p, widget.stages[0].name, n.key, layout.columns[0].indexOf(n));
    }

    final tallest = layout.columns.fold<int>(0, (m, c) => math.max(m, c.length));
    return LayoutBuilder(builder: (context, c) {
      final phone = c.maxWidth < 600;
      final natural = (tallest * (phone ? 30.0 : 36.0) + 40).clamp(220.0, 2000.0);
      final height = widget.height ?? math.min(natural, widget.maxHeight ?? natural);
      // Labels of the first and the last stage sit outside the nodes.
      final labelWidth = (c.maxWidth * (phone ? 0.26 : 0.2)).clamp(70.0, 200.0);
      layout.place(c.maxWidth, height, left: labelWidth, right: labelWidth, nodeWidth: phone ? 10 : 12, gap: phone ? 6 : 10);
      final bands = {for (final l in layout.links) l: _band(l)};
      final fontSize = phone ? 11.0 : 12.0;

      (SankeyNode?, SankeyLink?) hit(Offset at) {
        for (final col in layout.columns) {
          for (final n in col) {
            if (Rect.fromLTWH(n.x - 4, n.y, n.width + 8, math.max(n.height, 6)).contains(at)) return (n, null);
          }
        }
        // The top band wins where bands cross: the last one drawn.
        for (final l in layout.links.reversed) {
          if (bands[l]!.contains(at)) return (null, l);
        }
        return (null, null);
      }

      bool lit(SankeyLink l) => (_link == null && _node == null) || _link == l || _node == l.source || _node == l.target;
      final anyHover = _link != null || _node != null;

      // Labels fade in with the flows ([t] is the entry progress).
      List<Widget> labelsAt(double t) {
        final fade = t >= 1 ? 1.0 : (t * 1.4).clamp(0.0, 1.0);
        final labels = <Widget>[];
        for (final col in layout.columns) {
          for (final n in col) {
            final first = n.stage == 0, last = n.stage == layout.columns.length - 1;
            final text = Text.rich(
              TextSpan(children: [
                TextSpan(text: name(n), style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary)),
                TextSpan(text: '  ${compactNumber(n.value)}', style: TextStyle(color: p.textMuted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: first ? TextAlign.right : TextAlign.left,
              style: TextStyle(fontSize: fontSize, fontFeatures: const [FontFeature.tabularFigures()]),
            );
            final dim = anyHover && _node != n && !(_link != null && (_link!.source == n || _link!.target == n));
            final top = n.y + n.height / 2 - fontSize * 0.75;
            final label = AnimatedOpacity(
              opacity: (dim ? 0.45 : 1) * fade,
              duration: const Duration(milliseconds: 150),
              child: first || last
                  ? text
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: p.surface.withValues(alpha: 0.85),
                      child: text,
                    ),
            );
            labels.add(first
                ? Positioned(left: 0, width: labelWidth - 8, top: top, child: label)
                : last
                    ? Positioned(left: n.x + n.width + 8, width: labelWidth - 8, top: top, child: label)
                    : Positioned(left: n.x + n.width + 4, top: top, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: labelWidth), child: label)));
          }
      }
        return labels;
      }

      Widget? tooltip;
      final l = _link;
      if (l != null && _pointer != null) {
        const w = 220.0;
        final share = SankeyLayout.shareOfSource(l) * 100;
        tooltip = Positioned(
          left: (_pointer!.dx + 14).clamp(4.0, math.max(4.0, c.maxWidth - w - 4)).toDouble(),
          top: (_pointer!.dy + 14).clamp(0.0, math.max(0.0, height - 70)).toDouble(),
          child: IgnorePointer(
            child: Container(
              key: const Key('sankey_tooltip'),
              constraints: const BoxConstraints(maxWidth: w),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: p.textPrimary, borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
              child: Text.rich(TextSpan(style: ChartTooltip.base(p), children: [
                TextSpan(text: '${name(l.source)} → ${name(l.target)}\n', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...ChartTooltip.row(p, valueWithUnit(l.value, widget.measure), widget.measure.label),
                TextSpan(text: '\n${context.tr('share_of', {'share': '${numberText(share, 1)}%', 'name': name(l.source)})}'),
              ])),
            ),
          ),
        );
      }

      return EntryAnimation(
        duration: const Duration(milliseconds: 800),
        builder: (context, t) => SizedBox(
          key: const Key('sankey'),
          width: c.maxWidth,
          height: height,
          child: MouseRegion(
            onHover: (e) {
              final (n, link) = hit(e.localPosition);
              _setHover(n, link, e.localPosition);
            },
            onExit: (_) => _setHover(null, null, null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) {
                final (n, link) = hit(e.localPosition);
                final same = (n != null && n == _node) || (link != null && link == _link);
                same ? _setHover(null, null, null) : _setHover(n, link, e.localPosition);
              },
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SankeyPainter(
                      layout: layout,
                      bands: bands,
                      color: colorOf,
                      lit: lit,
                      anyHover: anyHover,
                      reveal: t,
                      border: p.surface,
                    ),
                  ),
                ),
                ...labelsAt(t),
                ?tooltip,
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class _SankeyPainter extends CustomPainter {
  final SankeyLayout layout;
  final Map<SankeyLink, Path> bands;
  final Color Function(SankeyNode) color;
  final bool Function(SankeyLink) lit;
  final bool anyHover;
  final double reveal;
  final Color border;

  _SankeyPainter({
    required this.layout,
    required this.bands,
    required this.color,
    required this.lit,
    required this.anyHover,
    required this.reveal,
    required this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    for (final l in layout.links) {
      final on = lit(l);
      final a = !anyHover ? 0.38 : (on ? 0.62 : 0.10);
      canvas.drawPath(bands[l]!, Paint()..color = color(l.source).withValues(alpha: a));
    }
    for (final col in layout.columns) {
      for (final n in col) {
        final r = Rect.fromLTWH(n.x, n.y, n.width, math.max(1.0, n.height));
        canvas.drawRect(r, Paint()..color = color(n));
        // A 1 px surface line keeps neighbor nodes apart.
        canvas.drawRect(r, Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SankeyPainter old) => true;
}
