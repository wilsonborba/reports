import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';

/// Colors of categories in one report. The report view arrives before any card data, and
/// it lists the options of every category filter. Those options fix the order of each
/// field, so a category gets the same slot in every chart and on every load, whatever card
/// loads first. Slots past the 8 colors use the "Other" gray, never a cycled color.
class SeriesColorMap {
  final Map<String, List<String>> _domains = {};

  /// Registers the category order of every filter field of the report.
  void registerReport(ReportView view) {
    for (final d in view.datasets) {
      for (final f in d.filters) {
        if (f.type == 'category' && f.options.isNotEmpty) {
          _domains.putIfAbsent(f.field, () => [for (final o in f.options) o.label]);
        }
      }
    }
  }

  /// Fixed order of a field, or null when no filter lists it.
  List<String>? domain(String field) => _domains[field];

  /// Color of [value] of [field]; [localIndex] is the position in the chart when the
  /// field has no fixed order.
  Color color(ReportPalette p, String field, String value, int localIndex) {
    final d = _domains[field];
    if (d != null) {
      final i = d.indexOf(value);
      if (i >= 0) return p.seriesAt(i);
    }
    return p.seriesAt(localIndex);
  }
}

/// Gives one [SeriesColorMap] to every chart below (one report page).
class SeriesColorScope extends InheritedWidget {
  final SeriesColorMap map;

  const SeriesColorScope({super.key, required this.map, required super.child});

  /// The report map, or an empty map for a chart outside a report page.
  static SeriesColorMap of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SeriesColorScope>()?.map ?? SeriesColorMap();

  @override
  bool updateShouldNotify(SeriesColorScope oldWidget) => oldWidget.map != map;
}

/// Name of the folded category in the data.
const otherKey = '\u0000other';

/// Categories to show, at most [keep] plus "Other". With a fixed field order, the first
/// [keep] categories of that order stay (the same in every chart); without it, the largest.
List<String> foldCategories(List<String> categories, Map<String, double> total, int keep, {List<String>? domain}) {
  if (categories.length <= keep + 1) return categories;
  final Set<String> kept;
  if (domain != null) {
    kept = categories.where((c) {
      final i = domain.indexOf(c);
      return i >= 0 && i < keep;
    }).toSet();
  } else {
    kept = ([...categories]..sort((a, b) => (total[b] ?? 0).compareTo(total[a] ?? 0))).take(keep).toSet();
  }
  return [...categories.where(kept.contains), otherKey];
}
