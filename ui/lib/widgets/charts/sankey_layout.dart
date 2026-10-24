import 'dart:math' as math;
import '../../models/report.dart';
import 'format.dart';
import 'series_colors.dart' show foldCategories, otherKey;

/// One node of a Sankey diagram: one category of one stage.
class SankeyNode {
  final int stage;

  /// Category value as text, or [otherKey] for the folded categories.
  final String key;

  /// First raw value of the category (for the label format of its field).
  final dynamic raw;

  double inValue = 0;
  double outValue = 0;
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;

  SankeyNode(this.stage, this.key, this.raw);

  /// Size of the node: the larger of its inflow and outflow.
  double get value => math.max(inValue, outValue);

  bool get isOther => key == otherKey;
}

/// One flow between two nodes of neighbor stages.
class SankeyLink {
  final SankeyNode source;
  final SankeyNode target;
  final double value;

  /// Top of the band at the source and at the target, and its thickness.
  double sourceY = 0;
  double targetY = 0;
  double thickness = 0;

  SankeyLink(this.source, this.target, this.value);
}

/// Nodes, links and positions of a Sankey diagram. The rows give one value per
/// combination of stage categories; each stage keeps [keep] categories and folds the
/// rest into "Other". [place] fits the diagram into a box; the same layout serves the
/// dashboard and the PDF.
class SankeyLayout {
  final List<FieldInfo> stages;
  final FieldInfo measure;
  final List<List<SankeyNode>> columns;
  final List<SankeyLink> links;

  /// Sum of the measure over the rows (the flow that enters the first stage).
  final double total;

  static const int keep = 7;

  SankeyLayout._(this.stages, this.measure, this.columns, this.links, this.total);

  factory SankeyLayout.build(List<Map<String, dynamic>> rows, List<FieldInfo> stages, FieldInfo measure,
      {List<String>? Function(String field)? domain}) {
    final values = <double>[];
    final keys = <List<String>>[];
    final raws = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final v = asDouble(r[measure.name]) ?? 0;
      if (v <= 0) continue;
      values.add(v);
      keys.add([for (final f in stages) '${r[f.name] ?? ''}']);
      for (var s = 0; s < stages.length; s++) {
        (raws[s] ??= {}).putIfAbsent('${r[stages[s].name] ?? ''}', () => r[stages[s].name]);
      }
    }
    // Each stage keeps its largest categories (or the first ones of the field order).
    final folded = <Map<String, String>>[];
    for (var s = 0; s < stages.length; s++) {
      final totals = <String, double>{};
      for (var i = 0; i < values.length; i++) {
        totals[keys[i][s]] = (totals[keys[i][s]] ?? 0) + values[i];
      }
      final kept = foldCategories(totals.keys.toList(), totals, keep, domain: domain?.call(stages[s].name)).toSet();
      folded.add({for (final k in totals.keys) k: kept.contains(k) ? k : otherKey});
    }
    final nodes = <int, Map<String, SankeyNode>>{};
    SankeyNode node(int s, String k) =>
        (nodes[s] ??= {}).putIfAbsent(k, () => SankeyNode(s, k, k == otherKey ? null : raws[s]?[k]));
    final sums = <String, double>{};
    for (var i = 0; i < values.length; i++) {
      for (var s = 0; s + 1 < stages.length; s++) {
        final a = folded[s][keys[i][s]]!, b = folded[s + 1][keys[i][s + 1]]!;
        final id = '$s\u0001$a\u0001$b';
        sums[id] = (sums[id] ?? 0) + values[i];
        node(s, a);
        node(s + 1, b);
      }
    }
    final links = <SankeyLink>[];
    sums.forEach((id, v) {
      final parts = id.split('\u0001');
      final s = int.parse(parts[0]);
      final link = SankeyLink(nodes[s]![parts[1]]!, nodes[s + 1]![parts[2]]!, v);
      link.source.outValue += v;
      link.target.inValue += v;
      links.add(link);
    });
    // Largest nodes first in each column; Other always last.
    final columns = [
      for (var s = 0; s < stages.length; s++)
        (nodes[s]?.values.toList() ?? <SankeyNode>[])
          ..sort((a, b) => a.isOther != b.isOther ? (a.isOther ? 1 : -1) : b.value.compareTo(a.value)),
    ];
    return SankeyLayout._(stages, measure, columns, links, values.fold<double>(0, (a, b) => a + b));
  }

  bool get isEmpty => links.isEmpty;

  /// Places the nodes and the link bands in a box of [width] x [height]. [left] and
  /// [right] keep room for the labels of the first and the last stage.
  void place(double width, double height, {double nodeWidth = 12, double gap = 10, double left = 0, double right = 0}) {
    final n = columns.length;
    if (n < 2) return;
    final span = math.max(1.0, width - left - right - nodeWidth);
    // One scale for all columns: the fullest column fills the height.
    var scale = double.infinity;
    for (final col in columns) {
      final sum = col.fold<double>(0, (a, c) => a + c.value);
      if (sum <= 0) continue;
      scale = math.min(scale, math.max(0.0, height - gap * (col.length - 1)) / sum);
    }
    if (!scale.isFinite) scale = 0;
    for (var s = 0; s < n; s++) {
      final col = columns[s];
      final used = col.fold<double>(0, (a, c) => a + c.value * scale) + gap * (col.length - 1);
      var y = math.max(0.0, (height - used) / 2);
      for (final node in col) {
        node
          ..x = left + span * s / (n - 1)
          ..y = y
          ..width = nodeWidth
          ..height = node.value * scale;
        y += node.height + gap;
      }
    }
    // Bands leave each source in target order and enter each target in source order.
    final order = {for (final col in columns) for (var i = 0; i < col.length; i++) col[i]: i};
    final out = <SankeyNode, double>{}, into = <SankeyNode, double>{};
    final bySource = [...links]..sort((a, b) => a.source.stage != b.source.stage
        ? a.source.stage.compareTo(b.source.stage)
        : order[a.source]! != order[b.source]!
            ? order[a.source]!.compareTo(order[b.source]!)
            : order[a.target]!.compareTo(order[b.target]!));
    for (final l in bySource) {
      l.thickness = l.value * scale;
      l.sourceY = l.source.y + (out[l.source] ?? 0);
      out[l.source] = (out[l.source] ?? 0) + l.thickness;
    }
    final byTarget = [...links]..sort((a, b) => order[a.target]! != order[b.target]!
        ? order[a.target]!.compareTo(order[b.target]!)
        : order[a.source]!.compareTo(order[b.source]!));
    for (final l in byTarget) {
      l.targetY = l.target.y + (into[l.target] ?? 0);
      into[l.target] = (into[l.target] ?? 0) + l.thickness;
    }
  }

  /// Share of the source node that a link carries (0 to 1).
  static double shareOfSource(SankeyLink l) => l.source.outValue <= 0 ? 0 : l.value / l.source.outValue;
}
