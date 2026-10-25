import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/strings.dart';
import '../models/catalog.dart';
import '../routes.dart';
import '../services/catalog_service.dart';
import '../themes/report_palette.dart';
import '../widgets/brand/brand_mark.dart';
import '../widgets/catalog/catalog_widgets.dart';
import '../widgets/shell/breadcrumbs.dart';
import '../widgets/shell/page_header.dart';

/// Report list of a project (/v1/menu/:project): professional cards with pages and search.
class ReportListView extends StatefulWidget {
  final String project;

  const ReportListView({super.key, required this.project});

  static const int pageSize = 12;

  @override
  State<ReportListView> createState() => _ReportListViewState();
}

class _ReportListViewState extends State<ReportListView> {
  CatalogViewMode _mode = CatalogViewMode.grid;
  int _page = 1;
  String _query = '';

  /// Tier of the reports to list (engine filter); null lists all.
  String? _tier;
  Timer? _debounce;
  Future<Paged<ReportSummary>>? _reports;
  Future<ProjectSummary?>? _projectInfo;
  String? _key;

  @override
  void initState() {
    super.initState();
    CatalogViewModeStore.load().then((m) => mounted ? setState(() => _mode = m) : null);
  }

  @override
  void didUpdateWidget(covariant ReportListView old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) {
      _page = 1;
      _query = '';
      _tier = null;
      _key = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _load(String lang) {
    final key = '${widget.project}:$lang:$_page:$_query:${_tier ?? ''}';
    if (key == _key) return;
    _key = key;
    final catalog = CatalogService.instance;
    _projectInfo = catalog.project(widget.project, lang: lang);
    _reports = catalog.reports(widget.project, lang: lang, page: _page, pageSize: ReportListView.pageSize, query: _query, tier: _tier);
  }

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<ProjectSummary?>(
        future: _projectInfo,
        builder: (context, projectSnap) {
          final project = projectSnap.data;
          final name = project?.name ?? '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                crumbs: [Crumb(context.tr('menu'), AppRoutes.menu), Crumb(name)],
                leading: BrandMark(project: widget.project, size: 48),
                title: name,
                subtitle: project?.description,
                subtitleLines: 2,
              ),
              const SizedBox(height: 20),
              // Toolbar (Carbon): search, the data filter and the view switch on one row.
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 320,
                    height: TierFilter.height,
                    child: TextField(
                      key: const Key('report_search'),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: context.tr('search_reports'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ReportPalette.controlRadius), borderSide: BorderSide(color: p.border)),
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => setState(() {
                              _query = v.trim();
                              _page = 1;
                            }));
                      },
                    ),
                  ),
                  TierFilter(
                    key: const Key('report_tier_filter'),
                    tiers: TierFilter.all,
                    selected: _tier,
                    onChanged: (t) => setState(() {
                      _tier = t;
                      _page = 1;
                    }),
                  ),
                  ViewModeSwitch(mode: _mode, onChanged: (m) {
                    setState(() => _mode = m);
                    CatalogViewModeStore.save(m);
                  }),
              ]),
              const SizedBox(height: 20),
              FutureBuilder<Paged<ReportSummary>>(
                future: _reports,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ApiErrorState(error: snap.error, onRetry: () => setState(() => _key = null), returnTo: AppRoutes.project(widget.project));
                  }
                  if (!snap.hasData) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                  final data = snap.data!;
                  if (data.items.isEmpty) {
                    return StateMessage(icon: Icons.inbox_outlined, title: context.tr('no_reports'), detail: context.tr('no_reports_detail'));
                  }
                  return Column(children: [
                    CatalogLayout(
                      mode: _mode,
                      cards: (compact) => [
                        for (final r in data.items)
                          ReportCard(report: r, compact: compact, onOpen: () => context.go(AppRoutes.report(widget.project, r.slug))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Pager(page: data.page, pages: data.pages, onPage: (n) => setState(() => _page = n)),
                  ]);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
