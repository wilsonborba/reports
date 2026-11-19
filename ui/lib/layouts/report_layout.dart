import 'package:reports_view/reports_view.dart';
export 'package:reports_view/reports_view.dart' show Slot, Visual;

class ReportLayout {
  final List<List<Slot>> sections;
  const ReportLayout(this.sections);
}

/// Layouts that the frontend owns, per report. Reports without an entry get the
/// automatic grouping.
class LayoutRegistry {
  static final Map<String, ReportLayout> layouts = {};

  /// Visual of one dataset in a report without a full layout (key: project/report/dataset).
  /// The automatic grouping keeps the dataset in its place and uses this slot.
  static final Map<String, Slot> visuals = {};

  static Slot _slot(ReportView view, String datasetId) => visuals['${view.project}/${view.report}/$datasetId'] ?? Slot(datasetId);

  static const int maxPerSection = 4;
  static const int minPerSection = 2;

  static List<List<Slot>> sectionsFor(ReportView view) {
    final ids = view.datasets.map((d) => d.datasetId).toSet();
    final registered = layouts['${view.project}/${view.report}'];
    if (registered != null) {
      final sections = registered.sections
          .map((s) => s.where((slot) => ids.contains(slot.datasetId)).toList())
          .where((s) => s.isNotEmpty)
          .toList();
      final used = {for (final s in sections) for (final slot in s) ...[slot.datasetId, ...slot.companions]};
      final rest = view.datasets.where((d) => !used.contains(d.datasetId)).map((d) => _slot(view, d.datasetId)).toList();
      return [...sections, ...group(rest)];
    }
    return group(view.datasets.map((d) => _slot(view, d.datasetId)).toList());
  }

  /// Splits items in API order into sections of at most 4. The last sections are
  /// balanced so that no section has fewer than 2 items (when there are 2 or more).
  static List<List<T>> group<T>(List<T> items) {
    if (items.isEmpty) return [];
    if (items.length <= maxPerSection) return [items];
    final sizes = <int>[];
    var left = items.length;
    while (left > 0) {
      if (left <= maxPerSection) {
        sizes.add(left);
        left = 0;
      } else if (left == maxPerSection + 1) {
        sizes.addAll([3, 2]);
        left = 0;
      } else {
        sizes.add(maxPerSection);
        left -= maxPerSection;
      }
    }
    final out = <List<T>>[];
    var i = 0;
    for (final n in sizes) {
      out.add(items.sublist(i, i + n));
      i += n;
    }
    return out;
  }
}
