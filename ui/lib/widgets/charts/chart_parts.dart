import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'format.dart';

/// Shared pieces of the axis charts.
class ChartParts {
  static FlGridData grid(ReportPalette p) => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: p.border.withValues(alpha: 0.5), strokeWidth: 1),
      );

  static AxisTitles leftTitles(ReportPalette p, {double reserved = 44}) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: reserved,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(compactNumber(v), style: TextStyle(fontSize: 10.5, color: p.textMuted)),
          ),
        ),
      );

  /// Bottom labels for category or time positions 0..n-1, thinned to about [maxLabels].
  static AxisTitles bottomLabels(ReportPalette p, List<String> labels, {int maxLabels = 12}) {
    final step = (labels.length / maxLabels).ceil().clamp(1, 1 << 20);
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= labels.length || i % step != 0 || (v - i).abs() > 0.01) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, child: Text(labels[i], style: TextStyle(fontSize: 10.5, color: p.textMuted)));
        },
      ),
    );
  }

  static const AxisTitles none = AxisTitles(sideTitles: SideTitles(showTitles: false));

  /// Short label for an x value (dates show month-day).
  static String xLabel(dynamic v, FieldInfo f) {
    if (f.type == 'date' && v is String && v.length >= 10) return shortDateText(v);
    return valueText(v, f);
  }
}

/// One legend entry: identity key, label and color.
class LegendItem {
  final String key;
  final String label;
  final Color color;
  final bool line;

  const LegendItem(this.key, this.label, this.color, {this.line = false});
}

/// Legend that is part of the chart: hover highlights a series, a click hides or shows it.
/// The text uses text colors; only the swatch carries the series color.
class Legend extends StatelessWidget {
  final List<(String, Color)> items;
  final List<LegendItem>? entries;
  final String? highlighted;
  final Set<String> hidden;
  final ValueChanged<String?>? onHover;
  final ValueChanged<String>? onToggle;

  const Legend({super.key, this.items = const [], this.entries, this.highlighted, this.hidden = const {}, this.onHover, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = entries ?? [for (final (label, color) in items) LegendItem(label, label, color)];
    return Wrap(spacing: 14, runSpacing: 6, children: [
      for (final e in list)
        MouseRegion(
          key: Key('legend_${e.key}'),
          cursor: onToggle == null ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: onHover == null ? null : (_) => onHover!(e.key),
          onExit: onHover == null ? null : (_) => onHover!(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle == null ? null : () => onToggle!(e.key),
            child: Opacity(
              opacity: hidden.contains(e.key) ? 0.45 : (highlighted == null || highlighted == e.key ? 1 : 0.6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: e.line ? 14 : 10,
                  height: e.line ? 3 : 10,
                  decoration: BoxDecoration(
                    color: hidden.contains(e.key) ? Colors.transparent : e.color,
                    border: hidden.contains(e.key) ? Border.all(color: e.color) : null,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  e.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: p.textMuted,
                    decoration: hidden.contains(e.key) ? TextDecoration.lineThrough : null,
                  ),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Tooltip text for fl_chart: the value first in bold, the series name after it.
class ChartTooltip {
  static TextStyle base(ReportPalette p) => TextStyle(color: p.canvas, fontSize: 11.5, height: 1.35);

  static List<TextSpan> row(ReportPalette p, String value, String name) => [
        TextSpan(text: value, style: TextStyle(color: p.canvas, fontWeight: FontWeight.w700, fontSize: 12.5)),
        TextSpan(text: '  $name', style: TextStyle(color: p.canvas.withValues(alpha: 0.75), fontSize: 11)),
      ];
}

/// Value range of an axis chart. Charts that share a scale (a scroll axis, small
/// multiples) pass the same range.
class YRange {
  final double min;
  final double max;
  const YRange(this.min, this.max);

  /// Range of [values]; [zero] keeps the baseline at 0 (bars).
  static YRange of(Iterable<double> values, {bool zero = false}) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (lo == double.infinity) return const YRange(0, 1);
    if (zero) {
      lo = lo < 0 ? lo : 0;
      hi = hi > 0 ? hi : 0;
    }
    if (hi <= lo) hi = lo + 1;
    return YRange(lo, hi);
  }
}

/// X axis with many points: each point gets at least [pointWidth] px. When the points do
/// not fit, the plot scrolls horizontally and a fixed y axis stays on the left. [chart]
/// gets `showAxis` (false inside the scroll) and the width of one point.
class ScrollableX extends StatefulWidget {
  final int count;
  final double pointWidth;
  final double height;
  final YRange range;
  final double axisWidth;
  final Widget Function(bool showAxis, double perPoint) chart;

  const ScrollableX({super.key, required this.count, required this.pointWidth, required this.height, required this.range, required this.chart, this.axisWidth = 44});

  @override
  State<ScrollableX> createState() => _ScrollableXState();
}

class _ScrollableXState extends State<ScrollableX> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (context, c) {
      final plot = c.maxWidth - widget.axisWidth;
      final needed = widget.count * widget.pointWidth;
      if (needed <= plot) {
        return SizedBox(height: widget.height, child: widget.chart(true, plot / widget.count.clamp(1, 1 << 20)));
      }
      final axis = LineChart(
        duration: Duration.zero,
        LineChartData(
          minX: 0,
          maxX: 1,
          minY: widget.range.min,
          maxY: widget.range.max,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [LineChartBarData(show: false, spots: [FlSpot(0, widget.range.min)])],
          titlesData: FlTitlesData(
            leftTitles: ChartParts.leftTitles(p, reserved: widget.axisWidth),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (_, _) => const SizedBox.shrink())),
            topTitles: ChartParts.none,
            rightTitles: ChartParts.none,
          ),
        ),
      );
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(key: const Key('fixed_y_axis'), width: widget.axisWidth + 2, height: widget.height, child: axis),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const Key('chart_x_scroll'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(width: needed, height: widget.height, child: widget.chart(false, widget.pointWidth)),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}
