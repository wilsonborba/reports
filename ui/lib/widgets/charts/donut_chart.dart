import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'format.dart';
import 'motion.dart';
import 'series_colors.dart';

/// Donut with a value list. At most 6 segments: the rest fold into "Other" in the donut,
/// while the list keeps every row. Hovering a segment or a list row moves the segment out,
/// dims the others and shows its value and share in the center. The donut sweeps in.
class DonutChart extends StatefulWidget {
  final DatasetPage page;
  final FieldInfo label;
  final FieldInfo value;
  final FieldInfo? share;

  /// Largest height of the value list (full view); the list scrolls inside it.
  final double? listMaxHeight;

  const DonutChart({super.key, required this.page, required this.label, required this.value, this.share, this.listMaxHeight});

  /// Largest number of segments in the donut.
  static const int maxSegments = 6;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  String? _hover;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = widget.page.rows;
    final label = widget.label, value = widget.value;
    final colors = SeriesColorScope.of(context);
    final keys = [for (final r in rows) '${r[label.name]}'];
    final totals = {for (final r in rows) '${r[label.name]}': asDouble(r[value.name]) ?? 0};
    final total = totals.values.fold<double>(0, (a, b) => a + b);
    final segments = foldCategories(keys, totals, DonutChart.maxSegments - 1, domain: colors.domain(label.name));
    final kept = segments.where((k) => k != otherKey).toSet();
    double segValue(String k) => k == otherKey ? keys.where((x) => !kept.contains(x)).fold<double>(0, (s, x) => s + totals[x]!) : totals[k]!;
    Color colorOf(String k) => k == otherKey ? p.other : colors.color(p, label.name, k, keys.indexOf(k));
    String nameOf(String k) => k == otherKey ? context.tr('other') : valueText(rows[keys.indexOf(k)][label.name], label);
    // A list row of a folded category highlights the Other segment.
    String segmentOf(String k) => kept.contains(k) ? k : otherKey;
    final hoverSeg = _hover == null ? null : segmentOf(_hover!);
    final center = hoverSeg == null
        ? (valueText(total, value), value.unit ?? '', '')
        : (valueText(segValue(hoverSeg), value), nameOf(hoverSeg), total > 0 ? '${numberText(segValue(hoverSeg) / total * 100, 1)}%' : '');

    final donut = SizedBox(
      width: 200,
      height: 200,
      child: Stack(alignment: Alignment.center, children: [
        EntryAnimation(
          duration: const Duration(milliseconds: 700),
          builder: (context, t) => PieChart(
            duration: Duration.zero,
            PieChartData(
              sectionsSpace: 1.5,
              centerSpaceRadius: 58,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final i = event.isInterestedForInteractions ? response?.touchedSection?.touchedSectionIndex : null;
                  final k = i == null || i < 0 || i >= segments.length ? null : segments[i];
                  if (k != _hover) setState(() => _hover = k);
                },
              ),
              sections: [
                for (final k in segments)
                  PieChartSectionData(
                    value: segValue(k) * t,
                    color: colorOf(k).withValues(alpha: dimmed(hoverSeg != null, hoverSeg == k)),
                    radius: hoverSeg == k ? 40 : 36,
                    showTitle: false,
                  ),
                // The rest of the circle stays empty until the sweep ends.
                if (t < 1) PieChartSectionData(value: total * (1 - t), color: Colors.transparent, radius: 36, showTitle: false),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: SizedBox(
            width: 104,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(center.$1, key: const Key('donut_center_value'), textAlign: TextAlign.center, maxLines: 1,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.textPrimary)),
              if (center.$2.isNotEmpty)
                Text(center.$2, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.textMuted)),
              if (center.$3.isNotEmpty) Text(center.$3, style: TextStyle(fontSize: 10.5, color: p.textMuted)),
            ]),
          ),
        ),
      ]),
    );
    final maxRow = totals.values.fold<double>(0, (a, b) => a > b ? a : b);
    final rowsList = Column(children: [
      for (var i = 0; i < rows.length; i++)
        MouseRegion(
          key: Key('donut_row_$i'),
          onEnter: (_) => setState(() => _hover = keys[i]),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _hover = _hover == keys[i] ? null : keys[i]),
            child: Opacity(
              opacity: dimmed(hoverSeg != null, hoverSeg == segmentOf(keys[i])),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(segmentOf(keys[i])), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: Text(valueText(rows[i][label.name], label),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textPrimary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: LayoutBuilder(builder: (context, c) {
                      final v = totals[keys[i]]!;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 8,
                          width: maxRow <= 0 ? 0 : c.maxWidth * (v / maxRow).clamp(0.0, 1.0),
                          decoration: BoxDecoration(color: colorOf(segmentOf(keys[i])), borderRadius: BorderRadius.circular(4)),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: Text(
                      '${valueText(rows[i][value.name], value)}  ${widget.share != null ? valueText(rows[i][widget.share!.name], widget.share) : (total > 0 ? '${numberText(totals[keys[i]]! / total * 100, 1)}%' : '')}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()], color: p.textPrimary),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
    final list = widget.listMaxHeight == null
        ? rowsList
        : ConstrainedBox(
            key: const Key('donut_list_frame'),
            constraints: BoxConstraints(maxHeight: widget.listMaxHeight!),
            child: SingleChildScrollView(child: rowsList),
          );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 640) {
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [donut, const SizedBox(width: 24), Expanded(child: list)]);
      }
      return Column(children: [donut, const SizedBox(height: 16), list]);
    });
  }
}
