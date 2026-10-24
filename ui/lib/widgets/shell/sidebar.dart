import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../routes.dart';
import '../../services/catalog_service.dart';
import '../../services/session_store.dart';
import '../../themes/report_palette.dart';
import '../brand/brand_mark.dart';
import 'sidebar_identity.dart';

/// Collapsible left sidebar. An arrow opens and closes it (no burger icon).
/// Open: 240 px with labels. Closed: 64 px with icons and tooltips. Hidden under 768 px.
class Sidebar extends StatefulWidget {
  final String? project;
  final String? report;

  const Sidebar({super.key, this.project, this.report});

  static const double openWidth = 240;
  static const double closedWidth = 64;
  static const double minScreenWidth = 768;
  static const int reportPreviewCount = 4;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  static const _key = 'sidebar_open';
  bool _open = true;
  bool _reportsOpen = true;
  bool _projectsOpen = false;
  Future<Paged<ProjectSummary>>? _projects;
  Future<Paged<ReportSummary>>? _reports;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_onSessionChanged);
    _projectsOpen = widget.project == null;
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_key);
      if (saved != null && mounted) setState(() => _open = saved);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    SessionStore.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _loadedFor = null;
    });
  }

  void _load(String lang) {
    final key = '$lang:${widget.project}';
    if (_loadedFor == key) return;
    _loadedFor = key;
    final catalog = CatalogService.instance;
    // Every viewer sees the whole catalog; the engine decides which reports each one reads.
    _projects = catalog.projects(lang: lang);
    _reports = widget.project == null
        ? null
        : catalog.reports(widget.project!, lang: lang, pageSize: Sidebar.reportPreviewCount);
  }

  @override
  void didUpdateWidget(covariant Sidebar old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) {
      _loadedFor = null;
      if (widget.project == null) _projectsOpen = true;
    }
  }

  void _setOpen(bool value) {
    setState(() => _open = value);
    SharedPreferences.getInstance().then((p) => p.setBool(_key, value)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Sidebar.minScreenWidth) return const SizedBox.shrink();
    _load(context.langCode);
    final p = context.palette;
    return AnimatedContainer(
      key: const Key('sidebar'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: _open ? Sidebar.openWidth : Sidebar.closedWidth,
      decoration: BoxDecoration(color: p.surface, border: Border(right: BorderSide(color: p.border))),
      child: ClipRect(
        child: FutureBuilder<Paged<ProjectSummary>>(
          future: _projects,
          builder: (context, projectsSnap) {
            final projects = projectsSnap.data?.items ?? const <ProjectSummary>[];
            ProjectSummary? current;
            for (final pr in projects) {
              if (pr.slug == widget.project) current = pr;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, current),
                Divider(height: 1, color: p.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (widget.project != null) ..._projectItems(context),
                      _group(
                        context,
                        key: 'projects',
                        icon: Icons.apps_rounded,
                        label: context.tr('projects'),
                        open: _projectsOpen,
                        onToggle: () => setState(() => _projectsOpen = !_projectsOpen),
                        children: [
                          for (final pr in projects)
                            _item(
                              context,
                              key: 'project_${pr.slug}',
                              leading: BrandMark(project: pr.slug, size: 18),
                              label: pr.name,
                              route: pr.reportCount > 0 ? AppRoutes.project(pr.slug) : null,
                              active: pr.slug == widget.project && widget.report == null,
                              nested: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Signed-in user and deploy time.
                SidebarFooter(open: _open),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ProjectSummary? current) {
    final p = context.palette;
    final name = current?.name ?? (widget.project == null ? context.tr('app_name') : '');
    final arrow = IconButton(
      key: const Key('sidebar_toggle'),
      tooltip: context.tr(_open ? 'close_sidebar' : 'open_sidebar'),
      icon: Icon(_open ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: p.textMuted),
      onPressed: () => _setOpen(!_open),
    );
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [BrandMark(project: widget.project, size: 30), const SizedBox(height: 6), arrow]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        children: [
          BrandMark(project: widget.project, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.textPrimary)),
          ),
          arrow,
        ],
      ),
    );
  }

  List<Widget> _projectItems(BuildContext context) {
    final project = widget.project!;
    return [
      _item(
        context,
        key: 'overview',
        icon: Icons.space_dashboard_outlined,
        label: context.tr('overview'),
        route: AppRoutes.project(project),
        active: widget.report == null,
      ),
      FutureBuilder<Paged<ReportSummary>>(
        future: _reports,
        builder: (context, snap) {
          final reports = snap.data?.items ?? const <ReportSummary>[];
          final total = snap.data?.total ?? 0;
          return _group(
            context,
            key: 'reports',
            icon: Icons.insert_chart_outlined_rounded,
            label: context.tr('reports'),
            open: _reportsOpen || reports.any((r) => r.slug == widget.report),
            onToggle: () => setState(() => _reportsOpen = !_reportsOpen),
            children: [
              for (final r in reports.take(Sidebar.reportPreviewCount))
                _item(context,
                    key: 'report_${r.slug}',
                    label: r.title,
                    route: AppRoutes.report(project, r.slug),
                    active: r.slug == widget.report,
                    nested: true),
              if (total > 0)
                _item(context,
                    key: 'see_all',
                    icon: Icons.arrow_forward_rounded,
                    label: context.tr('see_all'),
                    route: AppRoutes.project(project),
                    nested: true,
                    muted: true),
            ],
          );
        },
      ),
    ];
  }

  Widget _group(BuildContext context,
      {required String key,
      required IconData icon,
      required String label,
      required bool open,
      required VoidCallback onToggle,
      required List<Widget> children}) {
    final p = context.palette;
    if (!_open) {
      return _iconOnly(context, key: 'group_$key', icon: icon, label: label, onTap: () {
        _setOpen(true);
        if (!open) onToggle();
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: InkWell(
            key: Key('group_$key'),
            borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Icon(icon, size: 19, color: p.textMuted),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textPrimary))),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
                ),
              ]),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: open ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _item(BuildContext context,
      {required String key,
      required String label,
      String? route,
      IconData? icon,
      Widget? leading,
      bool active = false,
      bool nested = false,
      bool muted = false}) {
    final p = context.palette;
    final enabled = route != null;
    if (!_open) {
      if (nested) return const SizedBox.shrink();
      return _iconOnly(context, key: key, icon: icon ?? Icons.circle_outlined, label: label, active: active,
          onTap: enabled ? () => context.go(route) : null);
    }
    final color = !enabled ? p.textMuted.withValues(alpha: 0.5) : active ? p.textPrimary : (muted ? p.textMuted : p.textPrimary);
    return Padding(
      padding: EdgeInsets.fromLTRB(nested ? 22 : 8, 1, 8, 1),
      child: Material(
        color: active ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
        child: InkWell(
          key: Key('nav_$key'),
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          onTap: enabled ? () => context.go(route) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              if (leading != null) ...[leading, const SizedBox(width: 10)],
              if (leading == null && icon != null) ...[Icon(icon, size: nested ? 16 : 19, color: color), const SizedBox(width: 12)],
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: nested ? 12.5 : 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
              ),
              if (active) Container(width: 4, height: 18, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _iconOnly(BuildContext context,
      {required String key, required IconData icon, required String label, bool active = false, VoidCallback? onTap}) {
    final p = context.palette;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: active ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          child: InkWell(
            key: Key('nav_$key'),
            borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
            onTap: onTap,
            child: SizedBox(height: 40, child: Center(child: Icon(icon, size: 21, color: active ? p.accent : p.textMuted))),
          ),
        ),
      ),
    );
  }
}
