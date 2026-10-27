import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';
import '../models/catalog.dart';
import '../routes.dart';
import '../services/catalog_service.dart';
import '../themes/report_palette.dart';
import '../widgets/catalog/catalog_widgets.dart';
import '../widgets/charts/format.dart';
import '../widgets/landing/project_carousel.dart';
import '../widgets/landing/project_tile.dart';

enum LandingViewMode { carousel, list }

/// Carousel or list choice of the landing page, kept in the browser.
class LandingViewModeStore {
  static const key = 'landing_view_mode';

  static Future<LandingViewMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) == 'list'
          ? LandingViewMode.list
          : LandingViewMode.carousel;
    } catch (_) {
      return LandingViewMode.carousel;
    }
  }

  static Future<void> save(LandingViewMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, mode.name);
    } catch (_) {}
  }
}

/// Landing page (/v1/menu), without the sidebar: a lead area with the totals of all
/// projects, then one tile per project in a carousel or a list. The catalog is public;
/// opening a project/report still goes through the SSO-protected routes below it.
class LandingView extends StatefulWidget {
  const LandingView({super.key});

  @override
  State<LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<LandingView> {
  LandingViewMode _mode = LandingViewMode.carousel;
  Future<(Paged<ProjectSummary>, GlobalStats)>? _future;
  String? _key;

  @override
  void initState() {
    super.initState();
    LandingViewModeStore.load().then(
      (m) => mounted ? setState(() => _mode = m) : null,
    );
  }

  void _load(String lang) {
    if (lang == _key) return;
    _key = lang;
    final service = CatalogService.instance;
    // The catalog landing page is public. Report data and project pages remain protected.
    _future =
        Future.wait<Object?>([
          service.projects(lang: lang),
          service.stats(lang: lang).catchError((_) => const GlobalStats()),
        ]).then((r) {
          final all = r[0] as Paged<ProjectSummary>;
          return (all, r[1] as GlobalStats);
        });
  }

  void _setMode(LandingViewMode m) {
    setState(() => _mode = m);
    LandingViewModeStore.save(m);
  }

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    final p = context.palette;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return FutureBuilder<(Paged<ProjectSummary>, GlobalStats)>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return StateMessage(
            icon: Icons.cloud_off_rounded,
            title: context.tr('error_loading'),
            onRetry: () => setState(() => _key = null),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snap.data!.$1.items;
        final stats = snap.data!.$2;
        Widget tile(ProjectSummary pr, double? height) => ProjectTile(
          project: pr,
          stats: stats.byProject[pr.slug],
          height: height,
          onOpen: () => context.go(AppRoutes.project(pr.slug)),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: phone ? 16 : 40,
            vertical: phone ? 24 : 40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('landing_title'),
                    style: TextStyle(
                      fontSize: phone ? 30 : 42,
                      fontWeight: FontWeight.w300,
                      color: p.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      context.tr('landing_text'),
                      style: TextStyle(
                        fontSize: 16,
                        color: p.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _StatsStrip(stats: stats, projects: projects.length),
                  SizedBox(height: phone ? 32 : 48),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('hub_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      _ModeSwitch(mode: _mode, onChanged: _setMode),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (projects.isEmpty)
                    StateMessage(
                      icon: Icons.folder_off_outlined,
                      title: context.tr('no_projects'),
                    )
                  else if (_mode == LandingViewMode.carousel)
                    ProjectCarousel(
                      count: projects.length,
                      itemBuilder: (context, i, h) => tile(projects[i], h),
                    )
                  else
                    Column(
                      key: const Key('landing_list'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < projects.length; i++) ...[
                          if (i > 0) const SizedBox(height: 16),
                          tile(projects[i], null),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Totals of all projects in one strip (Carbon style: big light numbers, small labels).
class _StatsStrip extends StatelessWidget {
  final GlobalStats stats;
  final int projects;

  const _StatsStrip({required this.stats, required this.projects});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = [
      (
        'projects',
        numberText(stats.projects > 0 ? stats.projects : projects, 0),
        context.tr('stat_projects'),
      ),
      ('reports', numberText(stats.reports, 0), context.tr('stat_reports')),
      ('charts', numberText(stats.charts, 0), context.tr('stat_charts')),
      ('rows', numberText(stats.rows, 0), context.tr('stat_rows')),
      ('stored', bytesText(stats.bytes), context.tr('stat_stored')),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 5 : (c.maxWidth >= 520 ? 3 : 2);
        final w = (c.maxWidth - (cols - 1)) / cols;
        return Wrap(
          key: const Key('landing_stats'),
          spacing: 1,
          runSpacing: 1,
          children: [
            for (final (key, value, label) in items)
              Container(
                key: Key('stat_$key'),
                width: w,
                color: p.surface,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final LandingViewMode mode;
  final ValueChanged<LandingViewMode> onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button(LandingViewMode m, IconData icon, String tip) {
      final selected = m == mode;
      return Tooltip(
        message: tip,
        child: track(
          'catalog.project_mode.select',
          InkWell(
            key: Key('view_${m.name}'),
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.all(8),
              color: selected ? p.surfaceAlt : Colors.transparent,
              child: Icon(
                icon,
                size: 18,
                color: selected ? p.textPrimary : p.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: p.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            LandingViewMode.carousel,
            Icons.view_carousel_outlined,
            context.tr('carousel_view'),
          ),
          button(
            LandingViewMode.list,
            Icons.view_agenda_outlined,
            context.tr('list_view'),
          ),
        ],
      ),
    );
  }
}
