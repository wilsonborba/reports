import 'package:reports_ui/core/tracking_manifest.dart';
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
    final key = normalized == 'real'
        ? 'data_tier_real'
        : normalized == 'hybrid'
        ? 'data_tier_hybrid'
        : 'data_tier_sample';
    final color = normalized == 'real'
        ? p.positive
        : normalized == 'hybrid'
        ? p.info
        : p.warning;
    return Container(
      key: Key('data_tier_$normalized'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        context.tr(key),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Data tier filter (Carbon inline dropdown): the label "Data" on the left, then the
/// current value and a chevron, 40 px high like the search field next to it. The engine
/// filters; this only picks the value it sends.
class TierFilter extends StatelessWidget {
  final List<String> tiers;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const TierFilter({
    super.key,
    required this.tiers,
    required this.selected,
    required this.onChanged,
  });

  static const all = ['real', 'hybrid', 'sample'];

  static const double height = 40;

  String _label(BuildContext context, String? tier) =>
      tier == null ? context.tr('tier_all') : context.tr('data_tier_$tier');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      label: context.tr('tier_filter'),
      child: track(
        'catalog.tier.open',
        PopupMenuButton<String>(
          key: const Key('tier_filter_button'),
          tooltip: context.tr('tier_filter'),
          position: PopupMenuPosition.under,
          onSelected: (v) {
            trackInput(context, 'catalog.tier.open', v);
            onChanged(v == 'all' ? null : v);
          },
          itemBuilder: (context) => [
            for (final t in [null, ...tiers])
              CheckedPopupMenuItem<String>(
                key: Key('tier_filter_${t ?? 'all'}'),
                value: t ?? 'all',
                checked: t == selected,
                child: track('catalog.tier.option', Text(_label(context, t))),
              ),
          ],
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: selected == null ? p.border : p.accent),
              borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('tier_filter'),
                  style: TextStyle(fontSize: 13, color: p.textMuted),
                ),
                const SizedBox(width: 8),
                Text(
                  _label(context, selected),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only access tag (Carbon tag): "Members" for charts that any signed-in account
/// opens, "Admin" for charts of the project admin or a grant. Public items have none.
class AccessTag extends StatelessWidget {
  /// Effective visibility from the engine: signed_in or restricted.
  final String visibility;

  /// Number shown before the label ("3 member charts"); null shows the label alone.
  final int? count;

  const AccessTag({super.key, required this.visibility, this.count});

  @override
  Widget build(BuildContext context) {
    if (visibility != 'signed_in' && visibility != 'restricted') {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final admin = visibility == 'restricted';
    final color = admin ? p.caution : p.highlight;
    final text = count == null
        ? context.tr(admin ? 'access_tag_admin' : 'access_tag_members')
        : context.tr(
            admin ? 'access_tag_admin_count' : 'access_tag_members_count',
            {'n': count!},
          );
    return Tooltip(
      message: context.tr(
        admin ? 'access_tag_admin_hint' : 'access_tag_members_hint',
      ),
      child: Container(
        key: Key('access_tag_$visibility'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              admin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.group_outlined,
              size: 13,
              color: p.textPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid or list view choice, shared by the catalog pages and kept in the browser.
class CatalogViewModeStore {
  static const _key = 'catalog_view_mode';

  static Future<CatalogViewMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) == 'list'
          ? CatalogViewMode.list
          : CatalogViewMode.grid;
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

  const ViewModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button(CatalogViewMode m, IconData icon, String tooltip) {
      final selected = m == mode;
      return Tooltip(
        message: tooltip,
        child: track(
          'catalog.view.select',
          InkWell(
            key: Key('view_${m.name}'),
            borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.all(6),
              // Carbon content switcher: the selected item is inverse, not the brand color.
              decoration: BoxDecoration(
                color: selected ? p.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  ReportPalette.controlRadius,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? p.canvas : p.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            CatalogViewMode.grid,
            Icons.grid_view_rounded,
            context.tr('grid_view'),
          ),
          button(
            CatalogViewMode.list,
            Icons.view_list_rounded,
            context.tr('list_view'),
          ),
        ],
      ),
    );
  }
}

/// Page controls under a catalog list.
class Pager extends StatelessWidget {
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  const Pager({
    super.key,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) return const SizedBox.shrink();
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        track(
          'catalog.pagination.previous',
          IconButton(
            key: const Key('page_previous'),
            tooltip: context.tr('previous_page'),
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ),
        Text(
          context.tr('page_of', {'page': page, 'pages': pages}),
          style: TextStyle(color: p.textMuted, fontSize: 13),
        ),
        track(
          'catalog.pagination.next',
          IconButton(
            key: const Key('page_next'),
            tooltip: context.tr('next_page'),
            onPressed: page < pages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
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
    return LayoutBuilder(
      builder: (context, c) {
        if (mode == CatalogViewMode.list) {
          return Column(
            children: [
              for (final card in cards(true))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card,
                ),
            ],
          );
        }
        final columns = (c.maxWidth / 340).floor().clamp(1, 6);
        final width = (c.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards(false))
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
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
      child: track(
        'catalog.card.open',
        InkWell(
          key: cardKey,
          borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
            ),
            child: child,
          ),
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
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: p.textMuted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: p.textMuted)),
        ],
      ),
    );
  }
}

String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

class ReportCard extends StatelessWidget {
  final ReportSummary report;
  final bool compact;
  final VoidCallback onOpen;

  const ReportCard({
    super.key,
    required this.report,
    required this.compact,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // What opens the report or some of its charts (counts from the engine).
        if (report.visibility != 'public')
          AccessTag(visibility: report.visibility)
        else ...[
          if (report.signedInCards > 0)
            AccessTag(visibility: 'signed_in', count: report.signedInCards),
          if (report.restrictedCards > 0)
            AccessTag(visibility: 'restricted', count: report.restrictedCards),
        ],
        if (report.period != null)
          _Chip(
            Icons.date_range_rounded,
            '${_date(report.period!.start)} → ${_date(report.period!.end)}',
          ),
        _Chip(
          Icons.dataset_outlined,
          context.tr('dataset_count', {'n': report.datasetCount}),
        ),
        DataTierBadge(tier: report.dataTier),
        if (report.updatedAt.isNotEmpty)
          _Chip(
            Icons.update_rounded,
            '${context.tr('updated')} ${_date(report.updatedAt)}',
          ),
        for (final t in report.tags.take(3)) _Chip(Icons.sell_outlined, t),
      ],
    );
    final title = Text(
      report.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
      ),
    );
    final desc = Text(
      report.description,
      maxLines: compact ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.45),
    );
    return _CardFrame(
      cardKey: Key('report_card_${report.slug}'),
      onTap: onOpen,
      child: compact
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.insert_chart_outlined_rounded, color: p.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 4),
                      desc,
                      const SizedBox(height: 8),
                      chips,
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.textMuted),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insert_chart_outlined_rounded,
                      color: p.textMuted,
                    ),
                    const Spacer(),
                    Text(
                      context.tr('open'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: p.textPrimary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(height: 44, child: title),
                const SizedBox(height: 4),
                SizedBox(height: 58, child: desc),
                const SizedBox(height: 10),
                chips,
              ],
            ),
    );
  }
}

/// Loading, error and empty states of a page.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textMuted),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              track(
                'catalog.error.retry',
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text(context.tr('retry')),
                ),
              ),
            ],
          ],
        ),
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

  const ApiErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.returnTo,
  });

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e is ApiException && e.needsLogin) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StateMessage(
              key: const Key('state_login_needed'),
              icon: Icons.login_rounded,
              title: context.tr('access_login_title'),
              detail: context.tr('access_login_detail'),
            ),
            track(
              'catalog.session.login',
              FilledButton(
                key: const Key('state_sign_in'),
                onPressed: () =>
                    AuthService.instance.signIn(returnTo: returnTo),
                child: Text(context.tr('sign_in')),
              ),
            ),
          ],
        ),
      );
    }
    if (e is ApiException && e.accessLimited) {
      return StateMessage(
        key: const Key('state_access_limited'),
        icon: Icons.lock_outline_rounded,
        title: context.tr('access_limited_title'),
        detail: context.tr('access_limited_detail'),
      );
    }
    if (e is ApiException && e.status == 404) {
      return StateMessage(
        key: const Key('state_not_found'),
        icon: Icons.search_off_rounded,
        title: context.tr('not_found'),
      );
    }
    return StateMessage(
      key: const Key('state_error'),
      icon: Icons.cloud_off_rounded,
      title: context.tr('error_loading'),
      onRetry: onRetry,
    );
  }
}
