import 'dart:typed_data';
import '../layouts/board_layout.dart';
import '../layouts/report_layout.dart';
import '../models/catalog.dart';
import '../models/report.dart';
import '../services/board_layout_store.dart';
import 'card_filter_state.dart';

/// Static text of an export in its language.
typedef Translate = String Function(String key, [Map<String, Object> args]);

/// Progress of one export: a text for the user and the done part.
class ExportProgress {
  final String text;
  final int done;
  final int total;

  const ExportProgress(this.text, {this.done = 0, this.total = 0});

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

typedef ProgressSink = void Function(ExportProgress progress);

/// A finished export file.
class ExportFile {
  final String name;
  final Uint8List bytes;
  final String mime;

  const ExportFile(this.name, this.bytes, this.mime);
}

/// One card of the dashboard in an export.
class ExportCard {
  final int section;
  final Slot slot;
  final DatasetDescriptor descriptor;

  /// Active card filters (query parameters such as `f.vclass`).
  final Map<String, String> filters;

  const ExportCard({required this.section, required this.slot, required this.descriptor, this.filters = const {}});
}

class ExportSection {
  final String name;
  final List<ExportCard> cards;

  const ExportSection(this.name, this.cards);
}

/// What an export contains: the sections with their names and the cards in board order.
class ExportPlan {
  final String project;
  final String report;
  final String lang;
  final ReportView view;
  final ProjectSummary? projectInfo;
  final List<ExportSection> sections;
  final DateTime createdAt;

  const ExportPlan({
    required this.project,
    required this.report,
    required this.lang,
    required this.view,
    required this.sections,
    required this.createdAt,
    this.projectInfo,
  });

  List<ExportCard> get cards => [for (final s in sections) ...s.cards];

  String get projectName => projectInfo?.name ?? project;

  /// `<project>_<report>_<yyyymmdd>`.
  String get fileBase => '${project}_${report}_${dateStamp(createdAt)}';

  static String dateStamp(DateTime t) => '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

  /// Creation time as `yyyy-mm-dd hh:mm`.
  String get createdText =>
      '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

  /// Sections from the layout of [view], cards in the board order of each section (browser
  /// layout or the default one), names from [sectionName], filters from the open cards.
  static Future<ExportPlan> build({
    required String project,
    required String report,
    required String lang,
    required ReportView view,
    required String Function(int index) sectionName,
    ProjectSummary? projectInfo,
    DateTime? now,
  }) async {
    final sections = <ExportSection>[];
    final layouts = LayoutRegistry.sectionsFor(view);
    for (var i = 0; i < layouts.length; i++) {
      final slots = layouts[i];
      final saved = await BoardLayoutStore.load(BoardLayoutStore.key(project, report, i + 1));
      final order = BoardLayout.resolve(saved, slots).readingOrder.map((item) => item.key).toList();
      final byKey = {for (final s in slots) s.key: s};
      final ordered = [
        for (final k in order)
          if (byKey[k] != null) byKey[k]!,
        // Slots that the saved layout does not know go last.
        for (final s in slots)
          if (!order.contains(s.key)) s,
      ];
      final cards = [
        for (final s in ordered)
          if (view.dataset(s.datasetId) != null && view.dataset(s.datasetId)!.canView)
            ExportCard(
              section: i,
              slot: s,
              descriptor: view.dataset(s.datasetId)!,
              filters: CardFilterState.instance.get(project, report, s.key),
            ),
      ];
      // A section whose cards are all gated for this viewer has nothing to export.
      if (cards.isNotEmpty) sections.add(ExportSection(sectionName(i), cards));
    }
    return ExportPlan(
      project: project,
      report: report,
      lang: lang,
      view: view,
      sections: sections,
      createdAt: now ?? DateTime.now(),
      projectInfo: projectInfo,
    );
  }
}

/// Active filters of a card as text lines ("Task: Chat, Embedding").
List<String> describeFilters(DatasetDescriptor d, Map<String, String> q, Translate t) {
  final lines = <String>[];
  for (final f in d.filters) {
    final selected = q['f.${f.field}'];
    if (selected != null && selected.isNotEmpty) {
      final labels = {for (final o in f.options) '${o.value}': o.label};
      lines.add('${f.label}: ${selected.split(',').where((v) => v.isNotEmpty).map((v) => labels[v] ?? v).join(', ')}');
    }
    final from = q['f.${f.field}.from'], to = q['f.${f.field}.to'];
    if (from != null && to != null) {
      lines.add('${f.label}: ${t('date_range', {'start': from, 'end': to})}');
    } else if (from != null) {
      lines.add('${f.label}: ${t('filter_from', {'v': from})}');
    } else if (to != null) {
      lines.add('${f.label}: ${t('filter_to', {'v': to})}');
    }
  }
  return lines;
}
