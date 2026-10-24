import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/strings.dart';
import '../layouts/report_layout.dart';
import '../models/catalog.dart';
import '../models/report.dart';
import '../routes.dart';
import '../services/catalog_service.dart';
import '../export/artifact_jobs.dart';
import '../export/report_artifacts.dart';
import '../services/report_service.dart';
import '../services/section_name_store.dart';
import '../themes/report_palette.dart';
import '../utils/download_helper.dart';
import '../widgets/catalog/catalog_widgets.dart';
import '../widgets/charts/series_colors.dart';
import '../widgets/report/artifacts_menu.dart';
import '../widgets/report/section_board.dart';
import '../widgets/report/section_pills.dart';
import '../widgets/shell/breadcrumbs.dart';
import '../widgets/shell/page_header.dart';

/// Report page (/v1/menu/:project/:report?section=N): one section at a time,
/// cards over the full content width.
class ReportPageView extends StatefulWidget {
  final String project;
  final String report;

  /// Selected section, starting at 1 (from the URL query).
  final int section;

  const ReportPageView({super.key, required this.project, required this.report, this.section = 1});

  @override
  State<ReportPageView> createState() => _ReportPageViewState();
}

class _ReportPageViewState extends State<ReportPageView> {
  Future<ReportView>? _future;
  Future<ProjectSummary?>? _project;
  String? _key;

  /// Custom section names of this report (browser).
  Map<int, String> _names = {};

  void _rename(int index, String? name) {
    setState(() {
      _names = {..._names};
      name == null ? _names.remove(index) : _names[index] = name;
    });
    SectionNameStore.save(widget.project, widget.report, _names);
  }

  /// Category colors of this report, fixed by the report view (kept across sections).
  SeriesColorMap _colors = SeriesColorMap();
  ReportView? _colorsFor;

  void _load(String lang) {
    _lang = lang;
    final key = '${widget.project}/${widget.report}/$lang';
    if (key == _key) return;
    final reportChanged = _key == null || !_key!.startsWith('${widget.project}/${widget.report}/');
    _key = key;
    if (reportChanged) {
      _jobs?.dispose();
      _jobs = _jobsFor();
      _names = {};
      final project = widget.project, report = widget.report;
      SectionNameStore.load(project, report).then((n) {
        if (mounted && project == widget.project && report == widget.report) setState(() => _names = n);
      });
    }
    _future = ReportService.instance.report(widget.project, widget.report, lang: lang);
    _project = CatalogService.instance.project(widget.project, lang: lang);
  }

  /// Export jobs of this report (PDF, Markdown, CSV) with their progress.
  ArtifactJobs? _jobs;
  String _lang = 'en';

  ArtifactJobs _jobsFor() {
    final project = widget.project, report = widget.report;
    return ArtifactJobs(
      runner: ReportArtifacts(project: project, report: report, language: () => _lang, sectionNames: () => _names).run,
      save: (f) => saveBytes(f.bytes, f.name, f.mime),
    );
  }

  @override
  void dispose() {
    _jobs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    final p = context.palette;
    return FutureBuilder<ReportView>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ApiErrorState(error: snap.error, onRetry: () => setState(() => _key = null), returnTo: AppRoutes.report(widget.project, widget.report));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final view = snap.data!;
        if (!identical(_colorsFor, view)) {
          _colorsFor = view;
          _colors = SeriesColorMap()..registerReport(view);
        }
        final sections = LayoutRegistry.sectionsFor(view);
        final index = (widget.section - 1).clamp(0, sections.isEmpty ? 0 : sections.length - 1);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<ProjectSummary?>(
                future: _project,
                builder: (context, ps) => PageHeader(
                  crumbs: [
                    Crumb(context.tr('menu'), AppRoutes.menu),
                    Crumb(ps.data?.name ?? widget.project, AppRoutes.project(widget.project)),
                    if (sections.length > 1) ...[
                      Crumb(view.title, AppRoutes.report(widget.project, widget.report)),
                      Crumb(SectionPills.nameOf(context, _names, index)),
                    ] else
                      Crumb(view.title),
                  ],
                  title: view.title,
                  subtitle: view.description,
                  actions: [ArtifactsMenu(jobs: _jobs!)],
                ),
              ),
              if (view.period != null) ...[
                const SizedBox(height: 10),
                Text('${context.tr('period')}: ${view.period!.start} → ${view.period!.end}',
                    style: TextStyle(fontSize: 12.5, color: p.textMuted)),
              ],
              const SizedBox(height: 18),
              if (sections.length > 1) ...[
                SectionPills(
                  count: sections.length,
                  selected: index,
                  names: _names,
                  onRename: _rename,
                  onSelect: (i) => context.go('${AppRoutes.report(widget.project, widget.report)}?section=${i + 1}'),
                ),
                const SizedBox(height: 18),
              ],
              if (sections.isEmpty)
                StateMessage(icon: Icons.inbox_outlined, title: context.tr('no_data'))
              else
                SeriesColorScope(
                  map: _colors,
                  child: SectionBoard(
                    key: ValueKey('section_$index'),
                    project: widget.project,
                    report: widget.report,
                    view: view,
                    section: index + 1,
                    slots: sections[index],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
