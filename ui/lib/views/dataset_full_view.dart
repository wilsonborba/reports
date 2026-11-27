import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/strings.dart';
import '../layouts/report_layout.dart';
import '../models/catalog.dart';
import '../routes.dart';
import '../services/api_client.dart';
import '../services/catalog_service.dart';
import '../services/report_service.dart';
import '../services/session_store.dart';
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
  final bool compact;
  final String? language;
  final ReportService? service;
  final ApiClient? apiClient;
  final VoidCallback? onReady;

  const DatasetFullView({
    super.key,
    required this.project,
    required this.report,
    required this.datasetId,
    this.visual,
    this.filters = const {},
    this.table = false,
    this.compact = false,
    this.language,
    this.service,
    this.apiClient,
    this.onReady,
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

  ApiClient get _api => widget.apiClient ?? widget.service?.api ?? ApiClient();
  String? _ownerItemId;
  bool _resolvedOwner = false;
  int _ownerRefCount = 0;
  String? _ownerVisibility;
  bool _mutating = false;
  bool _deleted = false;
  int _probeGeneration = 0;
  String? _probedUserId;
  String _sessionScope = SessionStore.instance.hasSession
      ? (SessionStore.instance.user?.userId ?? '__authenticated__')
      : '__guest__';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_onSessionChanged);
    _probeOwnership();
  }

  @override
  void didUpdateWidget(DatasetFullView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project ||
        oldWidget.report != widget.report ||
        oldWidget.datasetId != widget.datasetId) {
      setState(() {
        _ownerItemId = null;
        _resolvedOwner = false;
        _ownerRefCount = 0;
        _ownerVisibility = null;
        _mutating = false;
        _deleted = false;
        _probeGeneration++;
        _loadGeneration++;
        _last = null;
        _key = null;
      });
      _probeOwnership();
    }
  }

  @override
  void dispose() {
    SessionStore.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final currentUserId = SessionStore.instance.user?.userId;
    final currentScope = SessionStore.instance.hasSession
        ? (currentUserId ?? '__authenticated__')
        : '__guest__';
    if (currentScope != _sessionScope) {
      setState(() {
        _sessionScope = currentScope;
        _key = null;
        _last = null;
        _view = null;
        _rows = null;
        _loadGeneration++;
        _resolvedOwner = false;
        _ownerItemId = null;
        _ownerRefCount = 0;
        _ownerVisibility = null;
        _probedUserId = currentUserId;
        _mutating = false;
        _probeGeneration++;
      });
      if (SessionStore.instance.hasSession) {
        _probeOwnership();
      }
    } else if (!SessionStore.instance.hasSession || currentUserId == null) {
      if (_resolvedOwner || _ownerItemId != null || _probedUserId != null || _mutating) {
        setState(() {
          _resolvedOwner = false;
          _ownerItemId = null;
          _ownerRefCount = 0;
          _ownerVisibility = null;
          _probedUserId = null;
          _mutating = false;
          _probeGeneration++;
        });
      }
    } else if (currentUserId != _probedUserId) {
      setState(() {
        _resolvedOwner = false;
        _ownerItemId = null;
        _ownerRefCount = 0;
        _ownerVisibility = null;
        _probedUserId = currentUserId;
        _mutating = false;
        _probeGeneration++;
      });
      _probeOwnership();
    }
  }

  Future<void> _probeOwnership() async {
    if (!SessionStore.instance.hasSession) return;
    final gen = ++_probeGeneration;
    final datasetId = widget.datasetId;
    final currentUserId = SessionStore.instance.user?.userId;
    _probedUserId = currentUserId;
    try {
      final res = await _api.getOwnerItem(
        datasetId,
        project: widget.project,
        report: widget.report,
      );
      final item = res['item'];
      if (!mounted || gen != _probeGeneration || !SessionStore.instance.hasSession) return;
      if (SessionStore.instance.user?.userId != currentUserId) return;
      if (item is! Map<String, dynamic>) return;
      if (item['control_authority'] == 'user_owned') {
        setState(() {
          _resolvedOwner = true;
          _ownerItemId = item['id'] as String?;
          _ownerRefCount = (item['reference_count'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // Viewer is not owner or static card.
    }
  }

  Future<void> _handleVisibilityChange(String next) async {
    final itemId = _ownerItemId;
    final currentUserId = SessionStore.instance.user?.userId;
    final gen = _probeGeneration;
    if (itemId == null || _mutating || currentUserId == null) return;
    setState(() => _mutating = true);
    try {
      await _api.patchOwnerItemVisibility(itemId, next);
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      setState(() {
        _ownerVisibility = next;
        _mutating = false;
      });
    } catch (e) {
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error_loading')}: $e'),
          action: SnackBarAction(
            label: context.tr('retry'),
            onPressed: () {
              if (!mounted || _probeGeneration != gen || _ownerItemId != itemId || SessionStore.instance.user?.userId != currentUserId) {
                return;
              }
              _handleVisibilityChange(next);
            },
          ),
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final itemId = _ownerItemId;
    final currentUserId = SessionStore.instance.user?.userId;
    final gen = _probeGeneration;
    if (itemId == null || _mutating || currentUserId == null) return;
    setState(() => _mutating = true);
    try {
      var outcome = await _api.deleteOwnerItem(itemId, confirm: false);
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      if (outcome.requiresConfirmation) {
        setState(() => _mutating = false);
        final count = outcome.referenceCount > 0 ? outcome.referenceCount : _ownerRefCount;
        final warningText = count > 0
            ? context.tr('delete_reuse_warning', {'n': count})
            : context.tr('delete_confirm_body');
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            key: const Key('card_delete_dialog'),
            title: Text(ctx.tr('delete_confirm_title')),
            content: Text(
              warningText,
              key: const Key('card_delete_reuse_warning'),
            ),
            actions: [
              TextButton(
                key: const Key('card_delete_cancel'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ctx.tr('cancel')),
              ),
              FilledButton(
                key: const Key('card_delete_confirm'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(ctx.tr('delete_card')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) {
          if (mounted && gen == _probeGeneration && SessionStore.instance.user?.userId == currentUserId) {
            setState(() => _mutating = false);
          }
          return;
        }
        setState(() => _mutating = true);
        outcome = await _api.deleteOwnerItem(itemId, confirm: true);
        if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      }
      setState(() {
        _mutating = false;
        if (outcome.deleted) _deleted = true;
      });
      if (outcome.deleted && mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.report(widget.project, widget.report));
        }
      }
    } catch (e) {
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error_loading')}: $e'),
          action: SnackBarAction(
            label: context.tr('retry'),
            onPressed: () {
              if (!mounted || _probeGeneration != gen || _ownerItemId != itemId || SessionStore.instance.user?.userId != currentUserId) {
                return;
              }
              _handleDelete();
            },
          ),
        ),
      );
    }
  }

  Slot _slot(ReportView view) {
    for (final section in LayoutRegistry.sectionsFor(view)) {
      for (final s in section) {
        if (s.datasetId == widget.datasetId && (widget.visual == null || s.visual == widget.visual)) return s;
      }
    }
    return Slot(widget.datasetId, visual: widget.visual ?? Visual.auto);
  }

  void _load(String lang) {
    final currentScope = SessionStore.instance.hasSession
        ? (SessionStore.instance.user?.userId ?? '__authenticated__')
        : '__guest__';
    final sorted = widget.filters.keys.toList()..sort();
    final key = '$currentScope/${widget.project}/${widget.report}/${widget.datasetId}/$lang/${sorted.map((k) => '$k=${widget.filters[k]}').join('&')}';
    if (key == _key) return;
    _key = key;
    _last = null;
    final gen = ++_loadGeneration;
    final service = widget.service ?? ReportService.instance;
    final viewFuture = service.report(widget.project, widget.report, lang: lang);
    _view = viewFuture;
    if (!widget.compact) _project = CatalogService.instance.project(widget.project, lang: lang);
    _rows = viewFuture.then((view) async {
      final slot = _slot(view);
      final page = await service.allRows(widget.project, widget.report, widget.datasetId, lang: lang, filters: widget.filters);
      final companions = <String, DatasetPage>{};
      for (final c in slot.companions.where((c) => view.dataset(c) != null)) {
        companions[c] = await service.allRows(widget.project, widget.report, c, lang: lang);
      }
      if (!mounted || gen != _loadGeneration) {
        throw StateError('Outdated session response fenced');
      }
      return (page, companions);
    });
    _rows!.ignore();
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
    _load(widget.language ?? context.langCode);
    final p = context.palette;
    return FutureBuilder<ReportView>(
      key: ValueKey('full_view_report_$_loadGeneration'),
      future: _view,
      builder: (context, vs) {
        if (vs.hasError) {
          return ApiErrorState(error: vs.error, onRetry: () => setState(() => _key = null), returnTo: AppRoutes.report(widget.project, widget.report));
        }
        if (_deleted) {
          return StateMessage(
            key: const Key('full_view_deleted_state'),
            icon: Icons.delete_outline_rounded,
            title: context.tr('delete_card'),
          );
        }
        if (!vs.hasData) return const Center(child: CircularProgressIndicator());
        final view = vs.data!;
        final rawDescriptor = view.dataset(widget.datasetId);
        if (rawDescriptor == null) {
          return StateMessage(icon: Icons.search_off_rounded, title: context.tr('not_found'));
        }
        final descriptor = _ownerVisibility == null
            ? rawDescriptor
            : DatasetDescriptor(
                datasetId: rawDescriptor.datasetId,
                title: rawDescriptor.title,
                description: rawDescriptor.description,
                equation: rawDescriptor.equation,
                fields: rawDescriptor.fields,
                filters: rawDescriptor.filters,
                dataTier: rawDescriptor.dataTier,
                canView: rawDescriptor.canView,
                visibility: _ownerVisibility!,
                meta: rawDescriptor.meta,
              );
        final slot = _slot(view);
        return SingleChildScrollView(
          padding: EdgeInsets.all(widget.compact ? 12 : 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!widget.compact) FutureBuilder<ProjectSummary?>(
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
            if (!widget.compact) const SizedBox(height: 18),
            FutureBuilder<(DatasetPage, Map<String, DatasetPage>)>(
              key: ValueKey('full_view_rows_$_loadGeneration'),
              future: _rows,
              builder: (context, rs) {
                if (rs.hasData) _last = rs.data;
                final loading = rs.connectionState != ConnectionState.done;
                if (rs.hasData && !loading && widget.onReady != null) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.onReady!(); });
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
                  controls: CardControls(
                    isOwner: _resolvedOwner && _ownerItemId != null,
                    isLive: descriptor.meta?.freshnessMode == 'live'
                        ? true
                        : (descriptor.meta?.freshnessMode == 'snapshot' ||
                                descriptor.meta?.freshnessMode == 'static')
                            ? false
                            : null,
                    onChangeVisibility: _mutating ? null : _handleVisibilityChange,
                    onCheckDelete: _ownerRefCount > 0
                        ? () async => context.tr('delete_confirm_body')
                        : null,
                    deleteReuseWarning: _ownerRefCount > 0
                        ? context.tr('delete_reuse_warning', {'n': _ownerRefCount})
                        : null,
                    onDelete: _mutating ? null : _handleDelete,
                  ),
                  tableView: widget.table,
                  onToggleTable: widget.compact ? null : () => context.go(_path(table: !widget.table)),
                  onShare: !widget.compact && descriptor.visibility == 'public' ? () => showShareDialog(context, _path(), full: true) : null,
                  toolbar: widget.compact || descriptor.filters.isEmpty
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
