import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'bar_charts.dart';
import 'chart_parts.dart';
import 'format.dart';
import 'motion.dart';

/// Lines over x positions (time or category labels) or a numeric x (curves). A vertical
/// guide snaps to the nearest x and one tooltip lists every series there. Legend hover
/// highlights a line, a legend click hides it. Lines draw from left to right.
class SeriesLineChart extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo x;
  final List<FieldInfo> measures;
  final bool numericX;
  final double height;

  /// Smallest width of one x position; with it the plot scrolls when the points do not fit.
  /// Not used with a numeric x.
  final double? pointWidth;

  /// Shared y range (small multiples); null uses the range of this chart.
  final YRange? range;

  const SeriesLineChart(
      {super.key, required this.page, required this.x, required this.measures, this.numericX = false, this.height = 260, this.pointWidth, this.range});

  @override
  State<SeriesLineChart> createState() => _SeriesLineChartState();
}

class _SeriesLineChartState extends State<SeriesLineChart> {
  String? _highlight;
  final Set<String> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = widget.page.rows;
    final measures = widget.measures;
    final numericX = widget.numericX;
    final x = widget.x;
    final labels = [for (final r in rows) ChartParts.xLabel(r[x.name], x)];
    double xv(int i) => numericX ? (asDouble(rows[i][x.name]) ?? i.toDouble()) : i.toDouble();
    Color colorOf(int m) => p.seriesAt(m);
    final bars = [
      for (var m = 0; m < measures.length; m++)
        LineChartBarData(
          show: !_hidden.contains(measures[m].name),
          spots: [
            for (var i = 0; i < rows.length; i++)
              if (asDouble(rows[i][measures[m].name]) != null) FlSpot(xv(i), asDouble(rows[i][measures[m].name])!),
          ],
          isCurved: numericX,
          curveSmoothness: 0.2,
          color: colorOf(m).withValues(alpha: dimmed(_highlight != null, _highlight == measures[m].name)),
          barWidth: _highlight == measures[m].name ? 3 : 2,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: measures.length == 1, color: colorOf(m).withValues(alpha: 0.10)),
        ),
    ];
    String xText(double v) => numericX ? '${labelWithUnit(x)} ${compactNumber(v)}' : labels[v.round().clamp(0, labels.length - 1)];
    final range = widget.range ??
        YRange.of([
          for (final m in measures)
            if (!_hidden.contains(m.name))
              for (final r in rows)
                if (asDouble(r[m.name]) != null) asDouble(r[m.name])!
        ]);
    final scroll = widget.pointWidth != null && !numericX;
    Widget chart(bool showAxis, double? perPoint) => LineChart(
          duration: Duration.zero,
          LineChartData(
            minY: range.min,
            maxY: range.max,
            gridData: ChartParts.grid(p),
            borderData: FlBorderData(show: false),
            lineBarsData: bars,
            titlesData: FlTitlesData(
              leftTitles: showAxis ? ChartParts.leftTitles(p) : ChartParts.none,
              bottomTitles: numericX
                  ? AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(compactNumber(v), style: TextStyle(fontSize: 10.5, color: p.textMuted)),
                        ),
                      ),
                    )
                  : ChartParts.bottomLabels(p, labels, maxLabels: perPoint == null ? 12 : (rows.length * perPoint / 64).floor().clamp(2, 1 << 20)),
              topTitles: ChartParts.none,
              rightTitles: ChartParts.none,
            ),
            lineTouchData: LineTouchData(
              getTouchedSpotIndicator: (bar, indexes) => [
                for (final _ in indexes)
                  TouchedSpotIndicatorData(
                    FlLine(color: p.textPrimary.withValues(alpha: 0.7), strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (spot, percent, b, i) =>
                          FlDotCirclePainter(radius: 5, color: b.color ?? p.accent, strokeWidth: 2, strokeColor: p.surface),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => p.textPrimary,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) {
                  final sorted = [...spots]..sort((a, b) => a.barIndex.compareTo(b.barIndex));
                  return [
                    for (final s in spots)
                      s == sorted.first
                          ? LineTooltipItem('${xText(s.x)}\n', ChartTooltip.base(p), children: [
                              for (final o in sorted) ...[
                                ...ChartTooltip.row(p, valueWithUnit(o.y, measures[o.barIndex]), measures[o.barIndex].label),
                                if (o != sorted.last) const TextSpan(text: '\n'),
                              ],
                            ])
                          : null,
                  ];
                },
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EntryAnimation(
        duration: const Duration(milliseconds: 600),
        builder: (context, t) {
          Widget reveal(Widget child) => ClipRect(
                clipper: t >= 1 ? null : _Reveal(t),
                clipBehavior: t >= 1 ? Clip.none : Clip.hardEdge,
                child: child,
              );
          if (!scroll) return reveal(SizedBox(height: widget.height, child: chart(true, null)));
          return ScrollableX(
            count: rows.length,
            pointWidth: widget.pointWidth!,
            height: widget.height,
            range: range,
            chart: (showAxis, perPoint) => reveal(chart(showAxis, perPoint)),
          );
        },
      ),
      if (measures.length > 1) ...[
        const SizedBox(height: 10),
        Legend(
          entries: [for (var m = 0; m < measures.length; m++) LegendItem(measures[m].name, labelWithUnit(measures[m]), colorOf(m), line: true)],
          highlighted: _highlight,
          hidden: _hidden,
          onHover: (k) => setState(() => _highlight = k),
          onToggle: (k) => setState(() => _hidden.contains(k) ? _hidden.remove(k) : _hidden.add(k)),
        ),
      ],
    ]);
  }
}

/// Reveals the chart from left to right.
class _Reveal extends CustomClipper<Rect> {
  final double t;
  _Reveal(this.t);

  @override
  // The clip reaches above and below the chart: axis labels draw a little outside it.
  Rect getClip(Size size) => Rect.fromLTWH(-40, -24, 40 + size.width * t, size.height + 48);

  @override
  bool shouldReclip(_Reveal old) => old.t != t;
}

/// Two measures of different scale as two aligned bar charts that share the x axis and the
/// hover (never one chart with two y-axes).
class AlignedCharts extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo x;
  final FieldInfo first;
  final FieldInfo second;
  final double height;

  const AlignedCharts({super.key, required this.page, required this.x, required this.first, required this.second, this.height = 300});

  @override
  State<AlignedCharts> createState() => _AlignedChartsState();
}

class _AlignedChartsState extends State<AlignedCharts> {
  final _hover = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final each = ((widget.height - 40) / 2).clamp(80.0, 4000.0);
    Widget title(FieldInfo f) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(labelWithUnit(f), style: TextStyle(fontSize: 11.5, color: p.textMuted)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title(widget.first),
      VerticalBarChart(
          key: const Key('aligned_first'), page: widget.page, x: widget.x, measure: widget.first, height: each, color: p.seriesAt(0), sharedHover: _hover, leftReserved: 48),
      const SizedBox(height: 8),
      title(widget.second),
      VerticalBarChart(
          key: const Key('aligned_second'), page: widget.page, x: widget.x, measure: widget.second, height: each, color: p.seriesAt(1), sharedHover: _hover, leftReserved: 48),
    ]);
  }
}
