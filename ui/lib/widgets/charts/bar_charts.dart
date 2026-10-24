import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'chart_parts.dart';
import 'format.dart';
import 'line_charts.dart';
import 'motion.dart';
import 'series_colors.dart';

/// Vertical bars: one bar per x value (time or category), one measure. Bars grow from the
/// baseline; the hovered bar keeps its color and the others dim. [sharedHover] links the
/// hover of charts that share the x axis.
class VerticalBarChart extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo x;
  final FieldInfo measure;
  final double height;
  final Color? color;
  final ValueNotifier<int?>? sharedHover;
  final double leftReserved;

  /// Smallest width of one bar slot; with it the plot scrolls when the bars do not fit.
  final double? pointWidth;

  /// Shared y range (small multiples); null uses the range of this chart.
  final YRange? range;

  const VerticalBarChart({
    super.key,
    required this.page,
    required this.x,
    required this.measure,
    this.height = 260,
    this.color,
    this.sharedHover,
    this.leftReserved = 44,
    this.pointWidth,
    this.range,
  });

  @override
  State<VerticalBarChart> createState() => _VerticalBarChartState();
}

class _VerticalBarChartState extends State<VerticalBarChart> {
  late final ValueNotifier<int?> _hover = widget.sharedHover ?? ValueNotifier<int?>(null);

  @override
  void dispose() {
    if (widget.sharedHover == null) _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = widget.page.rows;
    final labels = [for (final r in rows) ChartParts.xLabel(r[widget.x.name], widget.x)];
    final color = widget.color ?? p.seriesAt(0);
    final range = widget.range ?? YRange.of([for (final r in rows) asDouble(r[widget.measure.name]) ?? 0], zero: true);
    Widget chart(bool showAxis, double? perPoint, int? hovered, double t) => BarChart(
          duration: Duration.zero,
          BarChartData(
            minY: range.min,
            maxY: range.max,
            gridData: ChartParts.grid(p),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: showAxis ? ChartParts.leftTitles(p, reserved: widget.leftReserved) : ChartParts.none,
              bottomTitles: ChartParts.bottomLabels(p, labels, maxLabels: perPoint == null ? 12 : (rows.length * perPoint / 64).floor().clamp(2, 1 << 20)),
              topTitles: ChartParts.none,
              rightTitles: ChartParts.none,
            ),
            barTouchData: BarTouchData(
              touchCallback: (event, response) {
                final i = event.isInterestedForInteractions ? response?.spot?.touchedBarGroupIndex : null;
                if (_hover.value != i) _hover.value = i;
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => p.textPrimary,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                  '${labels[group.x]}\n',
                  ChartTooltip.base(p),
                  children: ChartTooltip.row(p, valueWithUnit(rows[group.x][widget.measure.name], widget.measure), widget.measure.label),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < rows.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: (asDouble(rows[i][widget.measure.name]) ?? 0) * staggered(t, i, rows.length.clamp(0, 40)),
                    color: color.withValues(alpha: dimmed(hovered != null, hovered == i)),
                    width: perPoint == null ? (300 / rows.length).clamp(3.0, 24.0) : (perPoint * 0.6).clamp(3.0, 24.0),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]),
            ],
          ),
        );
    return ValueListenableBuilder<int?>(
      valueListenable: _hover,
      builder: (context, hovered, _) => EntryAnimation(
        duration: Duration(milliseconds: 500 + 25 * rows.length.clamp(0, 40)),
        builder: (context, t) => widget.pointWidth == null
            ? SizedBox(height: widget.height, child: chart(true, null, hovered, t))
            : ScrollableX(
                count: rows.length,
                pointWidth: widget.pointWidth!,
                height: widget.height,
                range: range,
                axisWidth: widget.leftReserved,
                chart: (showAxis, perPoint) => chart(showAxis, perPoint, hovered, t),
              ),
      ),
    );
  }
}

/// Stacked bars: x on the axis, one segment per category. Legend hover highlights a
/// category; a legend click hides it. At most 8 categories, the rest fold into "Other".
class StackedBarChart extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo x;
  final FieldInfo category;
  final FieldInfo measure;
  final double height;

  const StackedBarChart({super.key, required this.page, required this.x, required this.category, required this.measure, this.height = 300});

  @override
  State<StackedBarChart> createState() => _StackedBarChartState();
}

class _StackedBarChartState extends State<StackedBarChart> {
  String? _highlight;
  int? _hoverX;
  final Set<String> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final page = widget.page, x = widget.x, category = widget.category, measure = widget.measure;
    final xs = <String, dynamic>{};
    final totals = <String, double>{};
    final values = <String, Map<String, double>>{};
    for (final r in page.rows) {
      final xk = '${r[x.name]}';
      final ck = '${r[category.name]}';
      xs.putIfAbsent(xk, () => r[x.name]);
      final v = asDouble(r[measure.name]) ?? 0;
      totals[ck] = (totals[ck] ?? 0) + v;
      (values[xk] ??= {})[ck] = v;
    }
    final colors = SeriesColorScope.of(context);
    // At most 8 categories; past that the smallest fold into "Other".
    final cats = foldCategories(totals.keys.toList(), totals, ReportPalette.slots - 1, domain: colors.domain(category.name));
    if (cats.contains(otherKey)) {
      final kept = cats.toSet();
      for (final row in values.values) {
        final folded = row.entries.where((e) => !kept.contains(e.key)).fold<double>(0, (s, e) => s + e.value);
        row.removeWhere((k, _) => !kept.contains(k));
        row[otherKey] = folded;
      }
    }
    final xKeys = xs.keys.toList();
    final labels = [for (final k in xKeys) ChartParts.xLabel(xs[k], x)];
    Color color(String c) => c == otherKey ? p.other : colors.color(p, category.name, c, cats.indexOf(c));
    String name(String c) => c == otherKey ? context.tr('other') : c;
    final shown = cats.where((c) => !_hidden.contains(c)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EntryAnimation(
        duration: Duration(milliseconds: 500 + 25 * xKeys.length.clamp(0, 40)),
        builder: (context, t) => SizedBox(
          height: widget.height,
          child: BarChart(
            duration: Duration.zero,
            BarChartData(
              gridData: ChartParts.grid(p),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: ChartParts.leftTitles(p),
                bottomTitles: ChartParts.bottomLabels(p, labels),
                topTitles: ChartParts.none,
                rightTitles: ChartParts.none,
              ),
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  final i = event.isInterestedForInteractions ? response?.spot?.touchedBarGroupIndex : null;
                  if (_hoverX != i) setState(() => _hoverX = i);
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => p.textPrimary,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, rod, ri) {
                    final xk = xKeys[group.x];
                    final rowsOfX = [for (final c in shown.reversed) if ((values[xk]?[c] ?? 0) > 0) c];
                    return BarTooltipItem('${labels[group.x]}\n', ChartTooltip.base(p), children: [
                      for (final c in rowsOfX) ...[
                        ...ChartTooltip.row(p, valueWithUnit(values[xk]![c], measure), name(c)),
                        if (c != rowsOfX.last) const TextSpan(text: '\n'),
                      ],
                    ]);
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < xKeys.length; i++)
                  () {
                    final grow = staggered(t, i, xKeys.length.clamp(0, 40));
                    var y = 0.0;
                    final items = <BarChartRodStackItem>[];
                    for (final c in shown) {
                      final v = (values[xKeys[i]]?[c] ?? 0) * grow;
                      final a = dimmed(_highlight != null || _hoverX != null, (_highlight == null || _highlight == c) && (_hoverX == null || _hoverX == i));
                      // A 1 px surface border on each segment gives the 2 px gap between neighbors.
                      items.add(BarChartRodStackItem(y, y + v, color(c).withValues(alpha: a), borderSide: BorderSide(color: p.surface, width: 1)));
                      y += v;
                    }
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: y,
                        rodStackItems: items,
                        width: (360 / xKeys.length).clamp(3.0, 24.0),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        color: Colors.transparent,
                      ),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Legend(
        entries: [for (final c in cats) LegendItem(c, name(c), color(c))],
        highlighted: _highlight,
        hidden: _hidden,
        onHover: (k) => setState(() => _highlight = k),
        onToggle: (k) => setState(() => _hidden.contains(k) ? _hidden.remove(k) : _hidden.add(k)),
      ),
    ]);
  }
}

/// Horizontal ranking bars with labels and values (one series, one color). The hovered
/// row keeps its color and the others dim; bars grow one after the other.
class RankingBars extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo label;
  final FieldInfo measure;
  final FieldInfo? share;
  final int? maxItems;

  /// Rank of the first row minus 1 (a column of a long ranking starts after the others).
  final int rankOffset;

  /// Value of a full bar; columns of one ranking share it. Null uses the largest row.
  final double? maxValue;

  const RankingBars(
      {super.key, required this.page, required this.label, required this.measure, this.share, this.maxItems, this.rankOffset = 0, this.maxValue});

  @override
  State<RankingBars> createState() => _RankingBarsState();
}

class _RankingBarsState extends State<RankingBars> {
  int? _hover;

  String _valueText(Map<String, dynamic> row) => widget.share == null
      ? valueWithUnit(row[widget.measure.name], widget.measure)
      : '${valueWithUnit(row[widget.measure.name], widget.measure)}  ${valueWithUnit(row[widget.share!.name], widget.share)}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = widget.maxItems == null ? widget.page.rows : widget.page.rows.take(widget.maxItems!).toList();
    final measure = widget.measure;
    final maxValue = widget.maxValue ?? rows.fold<double>(0, (m, r) => (asDouble(r[measure.name]) ?? 0) > m ? (asDouble(r[measure.name]) ?? 0) : m);
    // The value column is as wide as its longest text, so values are never cut.
    final longest = rows.fold<int>(0, (m, r) => _valueText(r).length > m ? _valueText(r).length : m);
    final valueWidth = (longest * 7.2 + 8).clamp(48.0, 220.0);
    final color = p.seriesAt(0);
    return EntryAnimation(
      duration: Duration(milliseconds: 500 + 25 * rows.length.clamp(0, 40)),
      builder: (context, t) => Column(children: [
        for (var i = 0; i < rows.length; i++)
          MouseRegion(
            key: Key('rank_row_${widget.rankOffset + i}'),
            onEnter: (_) => setState(() => _hover = i),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _hover = _hover == i ? null : i),
              child: Opacity(
                opacity: dimmed(_hover != null, _hover == i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                      width: widget.rankOffset + rows.length >= 100 ? 30 : 22,
                      child: Text('${widget.rankOffset + i + 1}', style: TextStyle(fontSize: 11, color: p.textMuted, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 4,
                      child: Tooltip(
                        message: valueText(rows[i][widget.label.name], widget.label),
                        waitDuration: const Duration(milliseconds: 400),
                        child: Text(valueText(rows[i][widget.label.name], widget.label),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textPrimary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(builder: (context, c) {
                        final v = asDouble(rows[i][measure.name]) ?? 0;
                        final w = maxValue <= 0 ? 0.0 : c.maxWidth * (v / maxValue) * staggered(t, i, rows.length.clamp(0, 40));
                        return Stack(children: [
                          Container(height: 10, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(5))),
                          Container(height: 10, width: w, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                        ]);
                      }),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: valueWidth,
                      child: Text(
                        _valueText(rows[i]),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: TextStyle(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()], color: p.textPrimary,
                            fontWeight: _hover == i ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Full ranking: up to [perColumn] rows in one column, then 2 or 3 columns side by side
/// (as many as the width allows). Past that the columns grow and the frame scrolls.
/// All columns share one bar scale.
class RankingColumns extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo label;
  final FieldInfo measure;
  final FieldInfo? share;
  final double frame;
  final int perColumn;
  final int maxColumns;
  final double minColumnWidth;

  const RankingColumns({
    super.key,
    required this.page,
    required this.label,
    required this.measure,
    this.share,
    required this.frame,
    this.perColumn = 25,
    this.maxColumns = 3,
    this.minColumnWidth = 340,
  });

  /// Columns for [rows] rows at [width] px.
  static int columnsFor(int rows, double width, {int perColumn = 25, int maxColumns = 3, double minColumnWidth = 340}) {
    final byRows = (rows / perColumn).ceil().clamp(1, maxColumns);
    final byWidth = (width / minColumnWidth).floor().clamp(1, maxColumns);
    return byRows < byWidth ? byRows : byWidth;
  }

  @override
  State<RankingColumns> createState() => _RankingColumnsState();
}

class _RankingColumnsState extends State<RankingColumns> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.page.rows;
    final maxValue = rows.fold<double>(0, (m, r) => (asDouble(r[widget.measure.name]) ?? 0) > m ? (asDouble(r[widget.measure.name]) ?? 0) : m);
    return LayoutBuilder(builder: (context, c) {
      final cols = RankingColumns.columnsFor(rows.length, c.maxWidth,
          perColumn: widget.perColumn, maxColumns: widget.maxColumns, minColumnWidth: widget.minColumnWidth);
      final per = (rows.length / cols).ceil();
      DatasetPage part(int from) {
        final slice = rows.sublist(from, (from + per).clamp(0, rows.length));
        return DatasetPage(descriptor: widget.page.descriptor, rows: slice, offset: from, limit: slice.length, totalRows: rows.length);
      }

      final columns = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var k = 0; k < cols; k++) ...[
          if (k > 0) const SizedBox(width: 24),
          Expanded(
            key: Key('rank_column_$k'),
            child: k * per < rows.length
                ? RankingBars(
                    page: part(k * per),
                    label: widget.label,
                    measure: widget.measure,
                    share: widget.share,
                    rankOffset: k * per,
                    maxValue: maxValue,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ]);
      return ConstrainedBox(
        key: const Key('rank_frame'),
        constraints: BoxConstraints(maxHeight: widget.frame),
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(controller: _scroll, child: columns),
        ),
      );
    });
  }
}

/// Small multiples: one small bar chart per category, all on one y scale, in a grid.
/// Used when a stacked chart has more categories, or a line chart more lines, than the
/// palette has colors. One color: the title of each cell names the category or the line.
class SmallMultiples extends StatelessWidget {
  final List<String> titles;
  final List<DatasetPage> pages;
  final FieldInfo x;
  final List<FieldInfo> measures;
  final bool line;
  final double cellHeight;
  final double minCellWidth;

  /// True when cell i shows measure i (many lines); false when every cell shows all measures.
  final bool measurePerCell;

  const SmallMultiples({
    super.key,
    required this.titles,
    required this.pages,
    required this.x,
    required this.measures,
    this.line = false,
    this.cellHeight = 170,
    this.minCellWidth = 300,
    this.measurePerCell = false,
  });

  /// One page per category value of [category], in the order of [categories].
  static List<DatasetPage> split(DatasetPage page, FieldInfo category, List<String> categories) => [
        for (final c in categories)
          () {
            final rows = page.rows.where((r) => '${r[category.name]}' == c).toList();
            return DatasetPage(descriptor: page.descriptor, rows: rows, offset: 0, limit: rows.length, totalRows: rows.length);
          }(),
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final range = YRange.of([
      for (final pg in pages)
        for (final r in pg.rows)
          for (final m in measures)
            if (asDouble(r[m.name]) != null) asDouble(r[m.name])!
    ], zero: !line);
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minCellWidth).floor().clamp(1, 4);
      final width = (c.maxWidth - (cols - 1) * 16) / cols;
      return Wrap(
        key: const Key('small_multiples'),
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < pages.length; i++)
            SizedBox(
              width: width,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(titles[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.textPrimary)),
                const SizedBox(height: 4),
                line
                    ? SeriesLineChart(page: pages[i], x: x, measures: measurePerCell ? [measures[i]] : measures, height: cellHeight, range: range)
                    : VerticalBarChart(page: pages[i], x: x, measure: measures.first, height: cellHeight, range: range),
              ]),
            ),
        ],
      );
    });
  }
}
