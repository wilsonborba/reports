import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../export/card_filter_state.dart';
import '../../services/api_client.dart';
import '../../services/report_service.dart';
import '../../services/session_store.dart';
import '../charts/data_table_view.dart';
import '../charts/format.dart';
import '../charts/visual_chooser.dart';
import 'card_filters.dart';
import 'dataset_card.dart';
import 'share_dialog.dart';

/// Rows and companion datasets of one slot.
class SlotData {
  final DatasetPage page;
  final Map<String, DatasetPage> companions;
  const SlotData(this.page, this.companions);
}

/// Loads one dataset (and the companions of its visual) and shows it in a card.
/// Card filters reload only this card; results stay in the session cache.
class DatasetSlot extends StatefulWidget {
  final String project;
  final String report;
  final ReportView view;
  final Slot slot;
  final CardControls controls;

  /// True on the board: the card fills its cell and the chart takes the body height.
  final bool fill;
  final Map<String, String>? initialFilters;
  final bool initialTable;
  final bool interactive;
  final String? language;
  final ReportService? service;
  final ApiClient? apiClient;
  final VoidCallback? onReady;
  final VoidCallback? onMutated;

  const DatasetSlot({
    super.key,
    required this.project,
    required this.report,
    required this.view,
    required this.slot,
    this.controls = CardControls.none,
    this.fill = false,
    this.initialFilters,
    this.initialTable = false,
    this.interactive = true,
    this.language,
    this.service,
    this.apiClient,
    this.onReady,
    this.onMutated,
  });

  @override
  State<DatasetSlot> createState() => _DatasetSlotState();
}

class _DatasetSlotState extends State<DatasetSlot> {
  Future<SlotData>? _future;
  String? _key;
  SlotData? _last;

  /// Active card filters; they stay in session memory for the exports.
  late Map<String, String> _filters =
      widget.initialFilters ??
      CardFilterState.instance.get(
        widget.project,
        widget.report,
        widget.slot.key,
      );
  bool _filtersOpen = false;
  late bool _asTable = widget.initialTable;
  String? _ownerItemId;
  bool _resolvedOwner = false;
  int _ownerRefCount = 0;
  String? _ownerVisibility;
  bool _mutating = false;
  bool _deleted = false;
  int _probeGeneration = 0;
  String? _probedUserId;

  ApiClient get _api => widget.apiClient ?? ApiClient();

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_onSessionChanged);
    _probeOwnership();
  }

  @override
  void dispose() {
    SessionStore.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final currentUserId = SessionStore.instance.user?.userId;
    if (!SessionStore.instance.hasSession || currentUserId == null) {
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
    if (!widget.interactive ||
        widget.controls.isOwner ||
        !SessionStore.instance.hasSession) {
      return;
    }
    final gen = ++_probeGeneration;
    final datasetId = widget.slot.datasetId;
    final currentUserId = SessionStore.instance.user?.userId;
    _probedUserId = currentUserId;
    try {
      final res = await _api.getOwnerItem(datasetId);
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
      // 403/404 or static catalog card: viewer is not owner.
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
      widget.onMutated?.call();
    } catch (e) {
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error_loading')}: $e'),
          action: SnackBarAction(
            label: context.tr('retry'),
            onPressed: () => _handleVisibilityChange(next),
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
      if (outcome.deleted) widget.onMutated?.call();
    } catch (e) {
      if (!mounted || gen != _probeGeneration || SessionStore.instance.user?.userId != currentUserId) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('error_loading')}: $e'),
          action: SnackBarAction(
            label: context.tr('retry'),
            onPressed: _handleDelete,
          ),
        ),
      );
    }
  }

  CardControls _effectiveControls(DatasetDescriptor descriptor) {
    final bool? isLive = widget.controls.isLive ??
        (descriptor.meta?.freshnessMode == 'live'
            ? true
            : (descriptor.meta?.freshnessMode == 'snapshot' ||
                    descriptor.meta?.freshnessMode == 'static')
                ? false
                : null);

    if (widget.controls.isOwner || !_resolvedOwner || _ownerItemId == null) {
      if (isLive != widget.controls.isLive) {
        return CardControls(
          minimized: widget.controls.minimized,
          onToggleMinimize: widget.controls.onToggleMinimize,
          onMove: widget.controls.onMove,
          isOwner: widget.controls.isOwner,
          isLive: isLive,
          onChangeVisibility: widget.controls.onChangeVisibility,
          onCheckDelete: widget.controls.onCheckDelete,
          deleteReuseWarning: widget.controls.deleteReuseWarning,
          onDelete: widget.controls.onDelete,
        );
      }
      return widget.controls;
    }
    return CardControls(
      minimized: widget.controls.minimized,
      onToggleMinimize: widget.controls.onToggleMinimize,
      onMove: widget.controls.onMove,
      isOwner: true,
      isLive: isLive,
      onChangeVisibility: _mutating ? null : _handleVisibilityChange,
      onCheckDelete: _ownerRefCount > 0
          ? () async => context.tr('delete_confirm_body')
          : null,
      onDelete: _mutating ? null : _handleDelete,
    );
  }

  @override
  void didUpdateWidget(DatasetSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The same place on the board can show another card: take that card's own state.
    if (oldWidget.project != widget.project ||
        oldWidget.report != widget.report ||
        oldWidget.slot.key != widget.slot.key) {
      _ownerItemId = null;
      _resolvedOwner = false;
      _ownerRefCount = 0;
      _ownerVisibility = null;
      _mutating = false;
      _deleted = false;
      _probeGeneration++;
      _probeOwnership();
      _filters =
          widget.initialFilters ??
          CardFilterState.instance.get(
            widget.project,
            widget.report,
            widget.slot.key,
          );
      _filtersOpen = false;
      _asTable = widget.initialTable;
      _last = null;
    }
  }

  Future<SlotData> _fetch(String lang, Map<String, String> filters) async {
    final service = widget.service ?? ReportService.instance;
    final ids = [
      widget.slot.datasetId,
      ...widget.slot.companions.where((c) => widget.view.dataset(c) != null),
    ];
    final pages = await Future.wait([
      for (final id in ids)
        service.dataset(
          widget.project,
          widget.report,
          id,
          lang: lang,
          filters: id == widget.slot.datasetId ? filters : const {},
          limit: id == widget.slot.datasetId ? 500 : 2000,
        ),
    ]);
    return SlotData(pages.first, {
      for (var i = 1; i < ids.length; i++) ids[i]: pages[i],
    });
  }

  void _load(String lang) {
    final descriptor = widget.view.dataset(widget.slot.datasetId);
    if (descriptor == null || !descriptor.canView) {
      _future = null;
      return;
    }
    final sorted = _filters.keys.toList()..sort();
    final key =
        '${widget.project}/${widget.report}/${widget.slot.key}/$lang/${sorted.map((k) => '$k=${_filters[k]}').join('&')}';
    if (key == _key) return;
    _key = key;
    _future = _fetch(lang, _filters);
  }

  /// Full view URL with the visual, the chart or table view and the card filters.
  String _fullViewUrl() => chartPath(
    project: widget.project,
    report: widget.report,
    datasetId: widget.slot.datasetId,
    visual: widget.slot.visual,
    table: _asTable,
    filters: _filters,
  );

  Widget _seeAllFooter(BuildContext context, DatasetPage page) {
    final p = context.palette;
    final shown =
        VisualChooser.previewLimit(VisualChooser.resolve(page, widget.slot)) ??
        page.rows.length;
    final total = page.totalRows > page.rows.length
        ? page.totalRows
        : page.rows.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('rows_shown', {
                'shown': numberText(shown, 0),
                'total': numberText(total, 0),
              }),
              style: TextStyle(fontSize: 12, color: p.textMuted),
            ),
          ),
          track(
            'dataset.view.expand',
            TextButton.icon(
              key: const Key('card_see_all'),
              onPressed: () => context.go(_fullViewUrl()),
              icon: const Icon(Icons.open_in_full_rounded, size: 15),
              label: Text(context.tr('see_all')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load(widget.language ?? context.langCode);
    final p = context.palette;
    final rawDescriptor = widget.view.dataset(widget.slot.datasetId)!;
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
    if (_deleted) {
      return const SizedBox.shrink();
    }
    if (!descriptor.canView) {
      return _GatedChartSkeleton(descriptor: descriptor, fill: widget.fill);
    }
    final active = CardFilterQuery.active(_filters);
    final headerActions = <Widget>[
      if (widget.interactive && descriptor.filters.isNotEmpty)
        track(
          'dataset.error.retry',
          IconButton(
            key: const Key('card_filters_toggle'),
            tooltip: context.tr('filters'),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              backgroundColor: p.accent,
              textColor: p.onAccent,
              child: Icon(
                Icons.tune_rounded,
                size: 18,
                color: _filtersOpen || active > 0 ? p.accent : p.textMuted,
              ),
            ),
          ),
        ),
    ];
    final toolbar = _filtersOpen
        ? CardFilterBar(
            filters: descriptor.filters,
            values: _filters,
            onChanged: (v) {
              CardFilterState.instance.set(
                widget.project,
                widget.report,
                widget.slot.key,
                v,
              );
              setState(() => _filters = v);
            },
          )
        : null;
    return FutureBuilder<SlotData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) _last = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        if (snap.hasData && !loading && widget.onReady != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onReady!();
          });
        }
        final data = snap.hasData ? snap.data : (loading ? _last : null);
        final Widget body;
        if (snap.hasError) {
          body = Text(
            context.tr('error_loading'),
            style: TextStyle(color: p.negative),
          );
        } else if (data == null) {
          body = const SizedBox(height: 120);
        } else if (data.page.rows.isEmpty) {
          body = Text(
            context.tr('no_data'),
            style: TextStyle(color: p.textMuted),
          );
        } else if (_asTable) {
          final page = data.page;
          body = widget.fill
              ? LayoutBuilder(
                  builder: (context, c) => DataTableView(
                    page: page,
                    maxHeight: (c.maxHeight - 48).clamp(80.0, 4000.0),
                  ),
                )
              : DataTableView(page: page);
        } else {
          final page = data.page;
          body = widget.fill
              ? LayoutBuilder(
                  builder: (context, c) => VisualChooser.build(
                    page,
                    widget.slot,
                    companions: data.companions,
                    height: c.maxHeight,
                  ),
                )
              : VisualChooser.build(
                  page,
                  widget.slot,
                  companions: data.companions,
                );
        }
        final seeAll =
            widget.interactive &&
            !_asTable &&
            data != null &&
            data.page.rows.isNotEmpty &&
            VisualChooser.needsFullView(data.page, widget.slot);
        return DatasetCard(
          descriptor: descriptor,
          body: body,
          loading: loading || _mutating,
          controls: _effectiveControls(descriptor),
          fill: widget.fill,
          tableView: _asTable,
          onToggleTable: widget.interactive
              ? () => setState(() => _asTable = !_asTable)
              : null,
          // Only a public chart opens for anyone who gets the link.
          onShare: widget.interactive && descriptor.visibility == 'public'
              ? () => showShareDialog(context, _fullViewUrl())
              : null,
          headerActions: headerActions,
          toolbar: toolbar,
          footer: seeAll ? _seeAllFooter(context, data.page) : null,
        );
      },
    );
  }
}

/// Placeholder of a card that the caller cannot open: a faded chart, a lock and what
/// opens it. The sign in action lives once in the report access notice, not on each card.
class _GatedChartSkeleton extends StatelessWidget {
  final DatasetDescriptor descriptor;
  final bool fill;

  const _GatedChartSkeleton({required this.descriptor, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // The engine sends the effective visibility (the stricter of report and card).
    final needsAdmin = descriptor.visibility == 'restricted';
    return DatasetCard(
      descriptor: descriptor,
      body: Container(
        key: Key('gated_card_${descriptor.datasetId}'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(p, 40, 24),
                const SizedBox(width: 8),
                _bar(p, 70, 24),
                const SizedBox(width: 8),
                _bar(p, 55, 24),
                const SizedBox(width: 8),
                _bar(p, 90, 24),
                const SizedBox(width: 8),
                _bar(p, 60, 24),
              ],
            ),
            const SizedBox(height: 20),
            Icon(
              needsAdmin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.lock_outline_rounded,
              size: 28,
              color: p.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr(needsAdmin ? 'gated_admin_text' : 'gated_login_text'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ],
        ),
      ),
      loading: false,
      fill: fill,
    );
  }

  Widget _bar(ReportPalette p, double height, double width) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
