import 'package:flutter/material.dart';
import '../../layouts/report_layout.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'bar_charts.dart';
import 'data_table_view.dart';
import 'donut_chart.dart';
import 'format.dart';
import 'kpi_tiles.dart';
import 'line_charts.dart';
import 'map_chart.dart';
import 'sankey_chart.dart';

/// Chooses the chart for a dataset from its field types and roles. The layout can
/// force a visual and the measures; the API never sends chart types.
class VisualChooser {
  static const _geo = {'latitude', 'longitude'};

  static List<FieldInfo> dimensions(DatasetDescriptor d) => d.fields.where((f) => f.isDimension).toList();

  static List<FieldInfo> measures(DatasetDescriptor d) =>
      d.fields.where((f) => !f.isDimension && f.isNumeric && !_geo.contains(f.type)).toList();

  static bool hasGeo(DatasetDescriptor d) =>
      d.fields.any((f) => f.type == 'latitude') && d.fields.any((f) => f.type == 'longitude');

  /// Automatic choice when the layout says [Visual.auto].
  /// Category stages of a Sankey: the slot list, or the category dimensions in field
  /// order (no dates, hours or coordinates), at most 4.
  static List<FieldInfo> sankeyStages(DatasetDescriptor d, Slot slot) {
    if (slot.dimensions.isNotEmpty) {
      return [for (final n in slot.dimensions) if (d.field(n) != null) d.field(n)!];
    }
    return dimensions(d).where((f) => f.type == 'string').take(4).toList();
  }

  static Visual auto(DatasetPage page) {
    final d = page.descriptor;
    final dims = dimensions(d);
    final ms = measures(d);
    if (page.rows.isEmpty) return Visual.table;
    if (dims.isEmpty && page.rows.length == 1) return Visual.kpi;
    if (ms.isEmpty) return Visual.table;
    if (hasGeo(d) && dims.isNotEmpty) return Visual.map;
    if (dims.length == 2 && ms.length == 1 && dims.first.isTime && !dims.last.isTime) return Visual.stackedBar;
    if (dims.length == 1 && dims.first.isTime) return page.rows.length > 1 ? Visual.line : Visual.kpi;
    if (dims.length == 1 && dims.first.type == 'float') return Visual.curve;
    if (dims.length == 1 && dims.first.type == 'string') {
      if (ms.length > 3) return Visual.table;
      // A donut shows parts of a whole; rates and shares do not add up to one.
      final main = ms.firstWhere((f) => f.type != 'percent', orElse: () => ms.first);
      if (main.type == 'percent') return Visual.hbar;
      return page.rows.length <= 6 ? Visual.donut : Visual.hbar;
    }
    return Visual.table;
  }

  /// Measures of a slot: the forced list, or the first measure plus the next ones
  /// with the same type and unit (so one axis can show them).
  static List<FieldInfo> slotMeasures(DatasetDescriptor d, Slot slot, {int max = 4}) {
    if (slot.measures.isNotEmpty) {
      return [for (final n in slot.measures) if (d.field(n) != null) d.field(n)!];
    }
    final ms = measures(d);
    if (ms.isEmpty) return const [];
    final first = ms.firstWhere((f) => f.type != 'percent', orElse: () => ms.first);
    return ms.where((f) => f.type == first.type && f.unit == first.unit).take(max).toList();
  }

  static FieldInfo? _share(DatasetDescriptor d, FieldInfo value) {
    for (final f in measures(d)) {
      if (f.type == 'percent' && f != value) return f;
    }
    return null;
  }

  /// Bar measure and second value of a ranking or donut: the first measure in field
  /// order (the dataset is ranked by it), then a share, or else the next measure.
  static (FieldInfo, FieldInfo?) ranked(DatasetDescriptor d, Slot slot) {
    final all = measures(d);
    final forced = slotMeasures(d, slot);
    final main = slot.measures.isNotEmpty ? forced.first : all.first;
    final second = slot.measures.length > 1
        ? forced[1]
        : (_share(d, main) ?? all.where((f) => f != main).firstOrNull);
    return (main, second);
  }

  /// The chart widget for a loaded dataset. [companions] holds the extra datasets of the slot.
  /// [height] is the body height of a board card; null means the natural height.
  /// [frame] is the largest height of a full view chart (80% of the screen); long content
  /// scrolls inside it.
  static Widget build(DatasetPage page, Slot slot,
      {Map<String, DatasetPage> companions = const {}, bool full = false, double? height, double? frame}) {
    final visual = resolve(page, slot);
    final limit = full ? null : previewLimit(visual);
    // The table sorts all rows first and then shows the preview rows itself. The map
    // draws every point and limits only its list.
    final shown = limit != null && page.rows.length > limit && visual != Visual.table && visual != Visual.map
        ? DatasetPage(descriptor: page.descriptor, rows: page.rows.take(limit).toList(), offset: page.offset, limit: limit, totalRows: page.totalRows)
        : page;
    final chart = _build(shown, visual, slot,
        companions: companions, full: full, height: height == null ? null : (height - 48).clamp(80.0, 4000.0), frame: frame ?? 640);
    if (height == null) return chart;
    // Inside a fixed card the content never overflows: what does not fit scrolls.
    return SizedBox(height: height, child: SingleChildScrollView(child: chart));
  }

  /// Smallest width of one x position in a full view line or bar chart.
  static const double fullPointWidth = 8;

  /// Rows of one table page in a full view.
  static const int fullPageSize = 50;

  /// Rows a card shows for a visual; null shows every row. More rows give a See all button.
  static int? previewLimit(Visual v) => switch (v) {
        Visual.hbar => 10,
        Visual.table => 8,
        Visual.map => 8,
        _ => null,
      };

  /// True when the card shows only a part of the rows of the dataset.
  static bool needsFullView(DatasetPage page, Slot slot) {
    final limit = previewLimit(resolve(page, slot));
    final total = page.totalRows > page.rows.length ? page.totalRows : page.rows.length;
    return limit != null && total > limit;
  }

  /// The visual for a slot: the forced one when the dataset fits it, else the table.
  static Visual resolve(DatasetPage page, Slot slot) {
    final d = page.descriptor;
    final visual = slot.visual == Visual.auto ? auto(page) : slot.visual;
    final dims = dimensions(d);
    final ms = slotMeasures(d, slot);
    final fits = switch (visual) {
      Visual.kpi || Visual.table || Visual.auto => true,
      Visual.map => hasGeo(d) && dims.isNotEmpty && ms.isNotEmpty,
      Visual.stackedBar => dims.length >= 2 && ms.isNotEmpty,
      Visual.curve => d.fields.isNotEmpty && ms.isNotEmpty,
      Visual.combo => dims.isNotEmpty && ms.length >= 2,
      Visual.sankey => sankeyStages(d, slot).length >= 2 && ms.isNotEmpty,
      _ => dims.isNotEmpty && ms.isNotEmpty,
    };
    return fits ? visual : Visual.table;
  }

  static Widget _build(DatasetPage page, Visual visual, Slot slot,
      {required Map<String, DatasetPage> companions, required bool full, double? height, double frame = 640}) {
    final d = page.descriptor;
    final dims = dimensions(d);
    final ms = slotMeasures(d, slot);
    switch (visual) {
      case Visual.kpi:
        return KpiTiles(page: page);
      case Visual.line:
        if (full && ms.length > ReportPalette.slots) {
          return SmallMultiples(
              titles: [for (final m in ms) labelWithUnit(m)], pages: [for (final _ in ms) page], x: dims.first, measures: ms, line: true, measurePerCell: true);
        }
        return SeriesLineChart(page: page, x: dims.first, measures: ms, height: height ?? (full ? 420 : 260), pointWidth: full ? fullPointWidth : null);
      case Visual.curve:
        return SeriesLineChart(page: page, x: dims.isNotEmpty ? dims.first : d.fields.first, measures: ms, numericX: true, height: height ?? (full ? 420 : 260));
      case Visual.bar:
        return VerticalBarChart(page: page, x: dims.first, measure: ms.first, height: height ?? (full ? 420 : 260), pointWidth: full ? fullPointWidth : null);
      case Visual.stackedBar:
        if (full) {
          final totals = <String, double>{};
          for (final r in page.rows) {
            final k = '${r[dims[1].name]}';
            totals[k] = (totals[k] ?? 0) + (asDouble(r[ms.first.name]) ?? 0);
          }
          if (totals.length > ReportPalette.slots) {
            final cats = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
            final labels = {for (final r in page.rows) '${r[dims[1].name]}': valueText(r[dims[1].name], dims[1])};
            return SmallMultiples(titles: [for (final c in cats) labels[c]!], pages: SmallMultiples.split(page, dims[1], cats), x: dims[0], measures: [ms.first]);
          }
        }
        return StackedBarChart(page: page, x: dims[0], category: dims[1], measure: ms.first, height: height ?? (full ? 460 : 300));
      case Visual.hbar:
        final (main, second) = ranked(d, slot);
        if (full) return RankingColumns(page: page, label: dims.first, measure: main, share: second, frame: frame);
        return RankingBars(page: page, label: dims.first, measure: main, share: second, maxItems: null);
      case Visual.donut:
        final (main, second) = ranked(d, slot);
        return DonutChart(page: page, label: dims.first, value: main, share: second?.type == 'percent' ? second : null, listMaxHeight: full ? frame : null);
      case Visual.combo:
        return AlignedCharts(page: page, x: dims.first, first: ms[0], second: ms[1], height: height ?? (full ? 460 : 320));
      case Visual.map:
        final links = slot.companions.map((c) => companions[c]).whereType<DatasetPage>().firstOrNull;
        final label = dims.firstWhere((f) => f.type == 'string', orElse: () => dims.first);
        return SpatialMap(points: page, links: links, label: label, value: ms.first, share: _share(d, ms.first), listSize: full ? page.rows.length : 8, height: height, maxHeight: full ? frame : null);
      case Visual.sankey:
        // A Sankey uses every loaded row; it suits aggregated datasets.
        return SankeyChart(page: page, stages: sankeyStages(d, slot), measure: ms.first, height: height, maxHeight: full ? frame : null);
      case Visual.table:
      case Visual.auto:
        // Full view: pages of 50 rows; header and pager stay inside the frame.
        return DataTableView(
            page: page,
            maxRows: full ? null : previewLimit(Visual.table),
            maxHeight: height ?? (full ? (frame - 100).clamp(200.0, 4000.0) : 380),
            pageSize: full ? fullPageSize : null);
    }
  }
}
