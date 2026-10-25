import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/strings.dart';
import '../layouts/report_layout.dart';
import '../models/catalog.dart';
import '../models/report.dart';
import '../routes.dart';
import '../services/catalog_service.dart';
import '../services/report_service.dart';
import '../themes/report_palette.dart';
import '../widgets/catalog/catalog_widgets.dart';
import '../widgets/charts/format.dart';
import '../widgets/charts/visual_chooser.dart';
import '../widgets/charts/data_table_view.dart';
import '../widgets/report/card_filters.dart';
import '../widgets/report/share_dialog.dart';
import '../widgets/report/dataset_card.dart';
import '../widgets/shell/breadcrumbs.dart';
import '../widgets/shell/page_header.dart';

/// One chart with all its rows (/v1/menu/:project/:report/:dataset). The card
/// filters, the visual and the table view come in the URL query, so a shared link opens
/// the chart in the state it was shared, with the filter bar showing its values.
class DatasetFullView extends StatefulWidget {
  final String project;
  final String report;
  final String datasetId;
  final Visual? visual;
  final Map<String, String> filters;

  /// Table instead of the chart (`view=table`).
  final bool table;

  const DatasetFullView({
    super.key,
    required this.project,
    required this.report,
    required this.datasetId,
    this.visual,
    this.filters = const {},
    this.table = false,
  });

  /// Filters from URL query parameters (keys that start with `f.`).
  static Map<String, String> filtersOf(Map<String, String> query) =>
      {for (final e in query.entries) if (e.key.startsWith('f.')) e.key: e.value};

  static Visual? visualOf(String? name) => Visual.values.where((v) => v.name == name).firstOrNull;

  @override
  State<DatasetFullView> createState() => _DatasetFullViewState();
}

class _DatasetFullViewState extends State<DatasetFullView> {
  Future<ReportView>? _view;
  Future<ProjectSummary?>? _project;
  Future<(DatasetPage, Map<String, DatasetPage>)>? _rows;
  String? _key;
  (DatasetPage, Map<String, DatasetPage>)? _last;

  Slot _slot(ReportView view) {
    for (final section in LayoutRegistry.sectionsFor(view)) {
      for (final s in section) {
        if (s.datasetId == widget.datasetId && (widget.visual == null || s.visual == widget.visual)) return s;
      }
    }
    return Slot(widget.datasetId, visual: widget.visual ?? Visual.auto);
  }

  void _load(String lang) {
    final sorted = widget.filters.keys.toList()..sort();
    final key = '${widget.project}/${widget.report}/${widget.datasetId}/$lang/${sorted.map((k) => '$k=${widget.filters[k]}').join('&')}';
    if (key == _key) return;
    _key = key;
    final service = ReportService.instance;
    _view = service.report(widget.project, widget.report, lang: lang);
    _project = CatalogService.instance.project(widget.project, lang: lang);
    _rows = _view!.then((view) async {
      final slot = _slot(view);
      final page = await service.allRows(widget.project, widget.report, widget.datasetId, lang: lang, filters: widget.filters);
      final companions = <String, DatasetPage>{};
      for (final c in slot.companions.where((c) => view.dataset(c) != null)) {
        companions[c] = await service.allRows(widget.project, widget.report, c, lang: lang);
      }
      return (page, companions);
    });
  }

  /// This chart with the given state (the URL holds the whole state).
  String _path({Map<String, String>? filters, bool? table}) => chartPath(
        project: widget.project,
        report: widget.report,
        datasetId: widget.datasetId,
        visual: widget.visual ?? Visual.auto,
        table: table ?? widget.table,
        filters: filters ?? widget.filters,
      );

  void _setFilters(Map<String, String> filters) => context.go(_path(filters: filters));

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    final p = context.palette;
    return FutureBuilder<ReportView>(
      future: _view,
      builder: (context, vs) {
        if (vs.hasError) {
          return ApiErrorState(error: vs.error, onRetry: () => setState(() => _key = null), returnTo: AppRoutes.report(widget.project, widget.report));
        }
        if (!vs.hasData) return const Center(child: CircularProgressIndicator());
        final view = vs.data!;
        final descriptor = view.dataset(widget.datasetId);
        if (descriptor == null) {
          return StateMessage(icon: Icons.search_off_rounded, title: context.tr('not_found'));
        }
        final slot = _slot(view);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FutureBuilder<ProjectSummary?>(
              future: _project,
              builder: (context, ps) => PageHeader(
                crumbs: [
                  Crumb(context.tr('menu'), AppRoutes.menu),
                  Crumb(ps.data?.name ?? widget.project, AppRoutes.project(widget.project)),
                  Crumb(view.title, AppRoutes.report(widget.project, widget.report)),
                  Crumb(descriptor.title),
                ],
                title: descriptor.title,
                subtitle: descriptor.description,
              ),
            ),
            const SizedBox(height: 18),
            FutureBuilder<(DatasetPage, Map<String, DatasetPage>)>(
              future: _rows,
              builder: (context, rs) {
                if (rs.hasData) _last = rs.data;
                final loading = rs.connectionState != ConnectionState.done;
                final data = rs.hasData ? rs.data : (loading ? _last : null);
                final Widget body;
                if (rs.hasError) {
                  body = Text(context.tr('error_loading'), style: TextStyle(color: p.negative));
                } else if (data == null) {
                  body = const SizedBox(height: 200);
                } else if (data.$1.rows.isEmpty) {
                  body = Text(context.tr('no_data'), style: TextStyle(color: p.textMuted));
                } else {
                  body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      context.tr('rows_shown', {'shown': numberText(data.$1.rows.length, 0), 'total': numberText(data.$1.totalRows, 0)}),
                      key: const Key('full_view_rows'),
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                    const SizedBox(height: 10),
                    // The chart frame is at most 80% of the screen height.
                    if (widget.table)
                      DataTableView(page: data.$1, maxHeight: (MediaQuery.sizeOf(context).height * 0.8).clamp(320.0, 4000.0))
                    else
                      VisualChooser.build(data.$1, slot,
                          companions: data.$2, full: true, frame: (MediaQuery.sizeOf(context).height * 0.8).clamp(320.0, 4000.0)),
                  ]);
                }
                return DatasetCard(
                  key: const Key('full_view_card'),
                  descriptor: descriptor,
                  body: body,
                  loading: loading,
                  tableView: widget.table,
                  onToggleTable: () => context.go(_path(table: !widget.table)),
                  onShare: descriptor.visibility == 'public' ? () => showShareDialog(context, _path()) : null,
                  toolbar: descriptor.filters.isEmpty
                      ? null
                      : CardFilterBar(filters: descriptor.filters, values: widget.filters, onChanged: _setFilters),
                );
              },
            ),
          ]),
        );
      },
    );
  }
}
