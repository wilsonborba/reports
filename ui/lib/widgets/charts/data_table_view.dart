import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'format.dart';

/// Rich table for any dataset: sticky header, horizontal and vertical scroll when it
/// does not fit, numbers right-aligned, units in the header, sort by column. With
/// [pageSize] the rows come in pages (sorting covers all rows) with a pager below.
class DataTableView extends StatefulWidget {
  final DatasetPage page;
  final int? maxRows;
  final double maxHeight;
  final int? pageSize;

  const DataTableView({super.key, required this.page, this.maxRows, this.maxHeight = 380, this.pageSize});

  @override
  State<DataTableView> createState() => _DataTableViewState();
}

class _DataTableViewState extends State<DataTableView> {
  String? _sortField;
  bool _ascending = true;
  final _horizontal = ScrollController();
  int? _hoverRow;
  int _pageIndex = 0;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  static double _width(FieldInfo f, List<Map<String, dynamic>> rows) {
    var longest = labelWithUnit(f).length;
    for (final r in rows.take(200)) {
      final l = valueText(r[f.name], f).length;
      if (l > longest) longest = l;
    }
    return (longest * 7.4 + 28).clamp(72, 420).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fields = widget.page.descriptor.fields;
    var rows = widget.page.rows;
    if (_sortField != null) {
      final f = _sortField!;
      rows = [...rows]..sort((a, b) {
          final x = a[f], y = b[f];
          final c = (x is num && y is num) ? x.compareTo(y) : '${x ?? ''}'.compareTo('${y ?? ''}');
          return _ascending ? c : -c;
        });
    }
    if (widget.maxRows != null) rows = rows.take(widget.maxRows!).toList();
    final size = widget.pageSize;
    final allCount = rows.length;
    final pages = size == null ? 1 : (allCount / size).ceil().clamp(1, 1 << 30);
    final pageIndex = _pageIndex.clamp(0, pages - 1);
    if (size != null) rows = rows.sublist(pageIndex * size, ((pageIndex + 1) * size).clamp(0, allCount));
    final widths = [for (final f in fields) _width(f, widget.page.rows)];
    final total = widths.fold<double>(0, (s, w) => s + w);

    Widget cell(String text, double w, bool numeric, {bool header = false, VoidCallback? onTap, IconData? sortIcon}) => SizedBox(
          width: w,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: header || !numeric ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: numeric ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        fontSize: header ? 11.5 : 12.5,
                        fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                        color: header ? p.textMuted : p.textPrimary,
                        fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
                      ),
                    ),
                  ),
                  if (sortIcon != null) Icon(sortIcon, size: 14, color: p.textMuted),
                ],
              ),
            ),
          ),
        );

    final header = Container(
      decoration: BoxDecoration(color: p.surfaceAlt, border: Border(bottom: BorderSide(color: p.border))),
      child: Row(children: [
        for (var i = 0; i < fields.length; i++)
          cell(
            labelWithUnit(fields[i]),
            widths[i],
            fields[i].isNumeric && !fields[i].isDimension,
            header: true,
            sortIcon: _sortField == fields[i].name ? (_ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : null,
            onTap: () => setState(() {
              _pageIndex = 0;
              if (_sortField == fields[i].name) {
                _ascending = !_ascending;
              } else {
                _sortField = fields[i].name;
                _ascending = !(fields[i].isNumeric && !fields[i].isDimension);
              }
            }),
          ),
      ]),
    );
    final pager = size == null || pages <= 1
        ? null
        : Padding(
            key: const Key('table_pager'),
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(
                context.tr('rows_range', {
                  'from': numberText(pageIndex * size + 1, 0),
                  'to': numberText(((pageIndex + 1) * size).clamp(0, allCount), 0),
                  'total': numberText(allCount, 0),
                }),
                key: const Key('table_range'),
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('table_prev'),
                tooltip: context.tr('previous_page'),
                visualDensity: VisualDensity.compact,
                onPressed: pageIndex > 0 ? () => setState(() => _pageIndex = pageIndex - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                key: const Key('table_next'),
                tooltip: context.tr('next_page'),
                visualDensity: VisualDensity.compact,
                onPressed: pageIndex < pages - 1 ? () => setState(() => _pageIndex = pageIndex + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
          );
    final table = LayoutBuilder(builder: (context, c) {
      final width = total < c.maxWidth ? c.maxWidth : total;
      final scale = width / total;
      return Scrollbar(
        controller: _horizontal,
        thumbVisibility: total > c.maxWidth,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, r) => MouseRegion(
                    key: Key('table_row_$r'),
                    onEnter: (_) => setState(() => _hoverRow = r),
                    onExit: (_) => setState(() => _hoverRow = _hoverRow == r ? null : _hoverRow),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _hoverRow == r ? p.accent.withValues(alpha: 0.10) : (r.isOdd ? p.surfaceAlt.withValues(alpha: 0.35) : null),
                        border: Border(left: BorderSide(color: _hoverRow == r ? p.accent : Colors.transparent, width: 2)),
                      ),
                      child: Row(children: [
                        for (var i = 0; i < fields.length; i++)
                          cell(valueWithUnitCell(rows[r][fields[i].name], fields[i]), widths[i] * scale - (i == 0 ? 2 : 0), fields[i].isNumeric && !fields[i].isDimension),
                      ]),
                    ),
                  ),
                ),
              ),
              // Room for the scrollbar so it does not cover the last row.
              if (total > c.maxWidth) const SizedBox(height: 10),
            ]),
          ),
        ),
      );
    });
    if (pager == null) return table;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [table, pager]);
  }

  /// Cells show the value only; the unit is in the header.
  static String valueWithUnitCell(dynamic v, FieldInfo f) => valueText(v, f);
}
