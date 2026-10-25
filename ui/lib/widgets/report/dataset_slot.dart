import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../export/card_filter_state.dart';
import '../../layouts/report_layout.dart';
import '../../models/report.dart';
import '../../services/report_service.dart';
import '../../themes/report_palette.dart';
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

  const DatasetSlot({
    super.key,
    required this.project,
    required this.report,
    required this.view,
    required this.slot,
    this.controls = CardControls.none,
    this.fill = false,
  });

  @override
  State<DatasetSlot> createState() => _DatasetSlotState();
}

class _DatasetSlotState extends State<DatasetSlot> {
  Future<SlotData>? _future;
  String? _key;
  SlotData? _last;
  /// Active card filters; they stay in session memory for the exports.
  late Map<String, String> _filters = CardFilterState.instance.get(widget.project, widget.report, widget.slot.key);
  bool _filtersOpen = false;
  bool _asTable = false;

  Future<SlotData> _fetch(String lang, Map<String, String> filters) async {
    final service = ReportService.instance;
    final ids = [widget.slot.datasetId, ...widget.slot.companions.where((c) => widget.view.dataset(c) != null)];
    final pages = await Future.wait([
      for (final id in ids)
        service.dataset(widget.project, widget.report, id,
            lang: lang, filters: id == widget.slot.datasetId ? filters : const {}, limit: id == widget.slot.datasetId ? 500 : 2000),
    ]);
    return SlotData(pages.first, {for (var i = 1; i < ids.length; i++) ids[i]: pages[i]});
  }

  void _load(String lang) {
    final descriptor = widget.view.dataset(widget.slot.datasetId);
    if (descriptor == null || !descriptor.canView) {
      _future = null;
      return;
    }
    final sorted = _filters.keys.toList()..sort();
    final key = '${widget.slot.key}/$lang/${sorted.map((k) => '$k=${_filters[k]}').join('&')}';
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
    final shown = VisualChooser.previewLimit(VisualChooser.resolve(page, widget.slot)) ?? page.rows.length;
    final total = page.totalRows > page.rows.length ? page.totalRows : page.rows.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(children: [
        Expanded(
          child: Text(context.tr('rows_shown', {'shown': numberText(shown, 0), 'total': numberText(total, 0)}), style: TextStyle(fontSize: 12, color: p.textMuted)),
        ),
        TextButton.icon(
          key: const Key('card_see_all'),
          onPressed: () => context.go(_fullViewUrl()),
          icon: const Icon(Icons.open_in_full_rounded, size: 15),
          label: Text(context.tr('see_all')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    final p = context.palette;
    final descriptor = widget.view.dataset(widget.slot.datasetId)!;
    if (!descriptor.canView) {
      return _GatedChartSkeleton(descriptor: descriptor, fill: widget.fill);
    }
    final active = CardFilterQuery.active(_filters);
    final headerActions = <Widget>[
      if (descriptor.filters.isNotEmpty)
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
            child: Icon(Icons.tune_rounded, size: 18, color: _filtersOpen || active > 0 ? p.accent : p.textMuted),
          ),
        ),
    ];
    final toolbar = _filtersOpen
        ? CardFilterBar(
            filters: descriptor.filters,
            values: _filters,
            onChanged: (v) {
              CardFilterState.instance.set(widget.project, widget.report, widget.slot.key, v);
              setState(() => _filters = v);
            },
          )
        : null;
    return FutureBuilder<SlotData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) _last = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        final data = snap.hasData ? snap.data : (loading ? _last : null);
        final Widget body;
        if (snap.hasError) {
          body = Text(context.tr('error_loading'), style: TextStyle(color: p.negative));
        } else if (data == null) {
          body = const SizedBox(height: 120);
        } else if (data.page.rows.isEmpty) {
          body = Text(context.tr('no_data'), style: TextStyle(color: p.textMuted));
        } else if (_asTable) {
          final page = data.page;
          body = widget.fill
              ? LayoutBuilder(builder: (context, c) => DataTableView(page: page, maxHeight: (c.maxHeight - 48).clamp(80.0, 4000.0)))
              : DataTableView(page: page);
        } else {
          final page = data.page;
          body = widget.fill
              ? LayoutBuilder(builder: (context, c) => VisualChooser.build(page, widget.slot, companions: data.companions, height: c.maxHeight))
              : VisualChooser.build(page, widget.slot, companions: data.companions);
        }
        final seeAll = !_asTable && data != null && data.page.rows.isNotEmpty && VisualChooser.needsFullView(data.page, widget.slot);
        return DatasetCard(
          descriptor: descriptor,
          body: body,
          loading: loading,
          controls: widget.controls,
          fill: widget.fill,
          tableView: _asTable,
          onToggleTable: () => setState(() => _asTable = !_asTable),
          // Only a public chart opens for anyone who gets the link.
          onShare: descriptor.visibility == 'public' ? () => showShareDialog(context, _fullViewUrl()) : null,
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
            Icon(needsAdmin ? Icons.admin_panel_settings_outlined : Icons.lock_outline_rounded, size: 28, color: p.textMuted),
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
