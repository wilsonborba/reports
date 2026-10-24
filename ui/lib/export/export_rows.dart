import '../layouts/report_layout.dart';
import '../models/report.dart';
import '../widgets/charts/visual_chooser.dart';

/// Rows of a card in a short table (Markdown and PDF): the preview rows of the card, or
/// at most [fallback] rows when the card shows every row.
class ExportRows {
  static const int fallback = 12;

  static int limitFor(DatasetPage page, Slot slot) => VisualChooser.previewLimit(VisualChooser.resolve(page, slot)) ?? fallback;

  static List<Map<String, dynamic>> preview(DatasetPage page, Slot slot) {
    final n = limitFor(page, slot);
    return page.rows.length > n ? page.rows.sublist(0, n) : page.rows;
  }

  /// Total rows of the dataset (the API total when it is larger than the loaded rows).
  static int total(DatasetPage page) => page.totalRows > page.rows.length ? page.totalRows : page.rows.length;

  /// True when one row holds key figures (a KPI card): the table shows one line per field.
  static bool isKpi(DatasetPage page, Slot slot) => VisualChooser.resolve(page, slot) == Visual.kpi;
}
