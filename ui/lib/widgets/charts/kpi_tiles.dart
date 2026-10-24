import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'format.dart';
import 'motion.dart';

/// Key figures of a one-row dataset: one tile per field. Numbers count up from 0 on
/// the first show, and a tile lifts a little under the pointer.
class KpiTiles extends StatelessWidget {
  final DatasetPage page;

  const KpiTiles({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    if (page.rows.isEmpty) return const SizedBox.shrink();
    final row = page.rows.first;
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 190).floor().clamp(1, 6);
      final width = (c.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final f in page.descriptor.fields) SizedBox(width: width, child: _KpiTile(field: f, value: row[f.name])),
        ],
      );
    });
  }
}

class _KpiTile extends StatefulWidget {
  final FieldInfo field;
  final dynamic value;

  const _KpiTile({required this.field, required this.value});

  @override
  State<_KpiTile> createState() => _KpiTileState();
}

class _KpiTileState extends State<_KpiTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = widget.field;
    final number = asDouble(widget.value);
    Widget valueText_(dynamic v) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: valueText(v, f),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.textPrimary, fontFeatures: const [FontFeature.tabularFigures()])),
            if (f.unit != null && f.unit != '%' && f.unit!.isNotEmpty) TextSpan(text: ' ${f.unit}', style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          ])),
        );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover && !reduceMotion(context) ? -2 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.surfaceAlt.withValues(alpha: _hover ? 0.9 : 0.6),
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          border: Border(left: BorderSide(color: p.accent, width: 3)),
          boxShadow: _hover ? [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))] : const [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.label.toUpperCase(),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, letterSpacing: 0.5, fontWeight: FontWeight.w600, color: p.textMuted)),
          const SizedBox(height: 6),
          if (number == null)
            valueText_(widget.value)
          else
            EntryAnimation(
              duration: const Duration(milliseconds: 800),
              builder: (context, t) => valueText_(t >= 1 ? widget.value : (widget.value is int ? (number * t).round() : number * t)),
            ),
        ]),
      ),
    );
  }
}
