import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../themes/report_palette.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

enum CatalogViewMode { grid, list }

class DataTierBadge extends StatelessWidget {
  final String tier;
  const DataTierBadge({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final normalized = tier.toLowerCase();
    final key = normalized == 'real' ? 'data_tier_real' : normalized == 'hybrid' ? 'data_tier_hybrid' : 'data_tier_sample';
    final color = normalized == 'real' ? p.positive : normalized == 'hybrid' ? p.info : p.warning;
    return Container(
      key: Key('data_tier_$normalized'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), border: Border.all(color: color), borderRadius: BorderRadius.circular(3)),
      child: Text(context.tr(key), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Tier filter of a list or a report: All, then the given tiers (real, hybrid, sample).
/// The engine filters; this only picks the value it sends.
class TierFilter extends StatelessWidget {
  final List<String> tiers;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const TierFilter({super.key, required this.tiers, required this.selected, required this.onChanged});

  static const all = ['real', 'hybrid', 'sample'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget chip(String? tier) {
      final on = tier == selected;
      final label = tier == null ? context.tr('tier_all') : context.tr('data_tier_$tier');
      return ChoiceChip(
        key: Key('tier_filter_${tier ?? 'all'}'),
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => onChanged(tier),
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? p.onAccent : p.textPrimary),
        selectedColor: p.accent,
        backgroundColor: p.surface,
        side: BorderSide(color: on ? p.accent : p.border),
        visualDensity: VisualDensity.compact,
      );
    }

    return Semantics(
      container: true,
      label: context.tr('tier_filter'),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(context.tr('tier_filter'), style: TextStyle(fontSize: 12.5, color: p.textMuted)),
        chip(null),
        for (final t in tiers) chip(t),
      ]),
    );
  }
}

/// Grid or list view choice, shared by the catalog pages and kept in the browser.
class CatalogViewModeStore {
  static const _key = 'catalog_view_mode';

  static Future<CatalogViewMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) == 'list' ? CatalogViewMode.list : CatalogViewMode.grid;
    } catch (_) {
      return CatalogViewMode.grid;
    }
  }

  static Future<void> save(CatalogViewMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

class ViewModeSwitch extends StatelessWidget {
  final CatalogViewMode mode;
  final ValueChanged<CatalogViewMode> onChanged;

  const ViewModeSwitch({super.key, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button(CatalogViewMode m, IconData icon, String tooltip) {
      final selected = m == mode;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: Key('view_${m.name}'),
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          onTap: () => onChanged(m),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: selected ? p.accent : Colors.transparent, borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
            child: Icon(icon, size: 18, color: selected ? p.onAccent : p.textMuted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button(CatalogViewMode.grid, Icons.grid_view_rounded, context.tr('grid_view')),
        button(CatalogViewMode.list, Icons.view_list_rounded, context.tr('list_view')),
      ]),
    );
  }
}

/// Page controls under a catalog list.
class Pager extends StatelessWidget {
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  const Pager({super.key, required this.page, required this.pages, required this.onPage});

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) return const SizedBox.shrink();
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('page_previous'),
          tooltip: context.tr('previous_page'),
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(context.tr('page_of', {'page': page, 'pages': pages}), style: TextStyle(color: p.textMuted, fontSize: 13)),
        IconButton(
          key: const Key('page_next'),
          tooltip: context.tr('next_page'),
          onPressed: page < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// Lays out cards in a responsive grid or a single-column list, using the full width.
class CatalogLayout extends StatelessWidget {
  final CatalogViewMode mode;
  final List<Widget> Function(bool compact) cards;

  const CatalogLayout({super.key, required this.mode, required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (mode == CatalogViewMode.list) {
        return Column(children: [
          for (final card in cards(true)) Padding(padding: const EdgeInsets.only(bottom: 10), child: card),
        ]);
      }
      final columns = (c.maxWidth / 340).floor().clamp(1, 6);
      final width = (c.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [for (final card in cards(false)) SizedBox(width: width, child: card)],
      );
    });
  }
}

class _CardFrame extends StatelessWidget {
  final Key? cardKey;
  final VoidCallback? onTap;
  final Widget child;

  const _CardFrame({this.cardKey, this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
      child: InkWell(
        key: cardKey,
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius)),
          child: child,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: p.textMuted),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: p.textMuted)),
      ]),
    );
  }
}

String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

class ReportCard extends StatelessWidget {
  final ReportSummary report;
  final bool compact;
  final VoidCallback onOpen;

  const ReportCard({super.key, required this.report, required this.compact, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chips = Wrap(spacing: 6, runSpacing: 6, children: [
      if (report.period != null) _Chip(Icons.date_range_rounded, '${_date(report.period!.start)} → ${_date(report.period!.end)}'),
      _Chip(Icons.dataset_outlined, context.tr('dataset_count', {'n': report.datasetCount})),
      DataTierBadge(tier: report.dataTier),
      if (report.updatedAt.isNotEmpty) _Chip(Icons.update_rounded, '${context.tr('updated')} ${_date(report.updatedAt)}'),
      for (final t in report.tags.take(3)) _Chip(Icons.sell_outlined, t),
    ]);
    final title = Text(report.title,
        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.textPrimary));
    final desc = Text(report.description,
        maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.45));
    return _CardFrame(
      cardKey: Key('report_card_${report.slug}'),
      onTap: onOpen,
      child: compact
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.insert_chart_outlined_rounded, color: p.accent),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 4), desc, const SizedBox(height: 8), chips])),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.insert_chart_outlined_rounded, color: p.accent),
                const Spacer(),
                Text(context.tr('open'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.accent)),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.accent),
              ]),
              const SizedBox(height: 10),
              SizedBox(height: 44, child: title),
              const SizedBox(height: 4),
              SizedBox(height: 58, child: desc),
              const SizedBox(height: 10),
              chips,
            ]),
    );
  }
}

/// Loading, error and empty states of a page.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  const StateMessage({super.key, required this.icon, required this.title, this.detail, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: p.textMuted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: Text(context.tr('retry'))),
          ],
        ]),
      ),
    );
  }
}

/// Error state of a call to the engine, by access meaning:
/// 401 asks for a login (a button, never an automatic redirect), 403 says that access is
/// limited (no login loop), 404 is not found, anything else can be retried.
class ApiErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  /// Internal page to come back to after a login.
  final String? returnTo;

  const ApiErrorState({super.key, required this.error, this.onRetry, this.returnTo});

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e is ApiException && e.needsLogin) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StateMessage(key: const Key('state_login_needed'), icon: Icons.login_rounded, title: context.tr('access_login_title'), detail: context.tr('access_login_detail')),
          FilledButton(
            key: const Key('state_sign_in'),
            onPressed: () => AuthService.instance.signIn(returnTo: returnTo),
            child: Text(context.tr('sign_in')),
          ),
        ]),
      );
    }
    if (e is ApiException && e.accessLimited) {
      return StateMessage(key: const Key('state_access_limited'), icon: Icons.lock_outline_rounded, title: context.tr('access_limited_title'), detail: context.tr('access_limited_detail'));
    }
    if (e is ApiException && e.status == 404) {
      return StateMessage(key: const Key('state_not_found'), icon: Icons.search_off_rounded, title: context.tr('not_found'));
    }
    return StateMessage(key: const Key('state_error'), icon: Icons.cloud_off_rounded, title: context.tr('error_loading'), onRetry: onRetry);
  }
}
