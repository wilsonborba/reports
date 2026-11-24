import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import '../catalog/catalog_widgets.dart';

/// Card actions that the section gives to a card. A null callback hides the control.
class CardControls {
  final bool minimized;
  final VoidCallback? onToggleMinimize;

  /// Starts the edit layout mode of the section.
  final VoidCallback? onMove;

  /// True when the signed-in viewer owns this card; non-owners never see owner actions.
  final bool isOwner;

  /// True for live cards, false for static cards, null when unspecified.
  final bool? isLive;

  /// Changes card visibility (`public`, `asodya`, `personal`); null hides owner visibility items.
  final ValueChanged<String>? onChangeVisibility;

  /// Optional pre-delete reuse check returning a warning string if the item is referenced elsewhere.
  final Future<String?> Function()? onCheckDelete;

  /// Optional static reuse warning shown in the delete confirmation dialog.
  final String? deleteReuseWarning;

  /// Deletes the owned card after confirmation; null hides the delete item.
  final VoidCallback? onDelete;

  const CardControls({
    this.minimized = false,
    this.onToggleMinimize,
    this.onMove,
    this.isOwner = false,
    this.isLive,
    this.onChangeVisibility,
    this.onCheckDelete,
    this.deleteReuseWarning,
    this.onDelete,
  });

  static const none = CardControls();
}

/// Card frame of one dataset: title with the options menu, body, and the equation
/// in the footer (one line, monospace). Flat surface, outline on hover. With [fill] the card fills its board cell and
/// the body takes the remaining height.
class DatasetCard extends StatefulWidget {
  final DatasetDescriptor descriptor;
  final Widget body;
  final List<Widget> headerActions;
  final Widget? toolbar;
  final Widget? footer;
  final bool loading;
  final CardControls controls;
  final bool fill;

  /// True when the body shows the table instead of the chart.
  final bool tableView;

  /// Switches between chart and table; null hides the menu item.
  final VoidCallback? onToggleTable;

  /// Opens the share dialog of a public chart; null hides the menu item.
  final VoidCallback? onShare;

  const DatasetCard({
    super.key,
    required this.descriptor,
    required this.body,
    this.headerActions = const [],
    this.toolbar,
    this.footer,
    this.loading = false,
    this.controls = CardControls.none,
    this.fill = false,
    this.tableView = false,
    this.onToggleTable,
    this.onShare,
  });

  @override
  State<DatasetCard> createState() => _DatasetCardState();
}

class _DatasetCardState extends State<DatasetCard> {
  bool _hover = false;

  void _showInfo() {
    final d = widget.descriptor;
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('card_info_dialog'),
        title: Text(d.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctx.tr('description'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  d.description.isEmpty ? '' : d.description,
                  style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                ),
                if (d.equation != null && d.equation!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    ctx.tr('equation'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    d.equation!,
                    style: TextStyle(
                      fontFamily: ReportPalette.monoFont,
                      fontSize: 12.5,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          track(
            'dataset.info.close',
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.tr('close')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final c = widget.controls;
    String? warning = c.deleteReuseWarning;
    if (c.onCheckDelete != null) {
      warning = await c.onCheckDelete!();
    }
    if (!mounted) return;
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('card_delete_dialog'),
        title: Text(ctx.tr('delete_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.tr('delete_confirm_body')),
            if (warning != null && warning.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('card_delete_reuse_warning'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.warning.withValues(alpha: 0.16),
                  border: Border.all(color: p.warning),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  warning,
                  style: TextStyle(fontSize: 12.5, color: p.textPrimary),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('card_delete_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            key: const Key('card_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: p.negative),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('delete_card')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      c.onDelete?.call();
    }
  }

  Widget _menu(BuildContext context) {
    final c = widget.controls;
    final p = context.palette;
    final showOwnerActions =
        c.isOwner && (c.onChangeVisibility != null || c.onDelete != null);
    return track(
      'dataset.menu.open',
      PopupMenuButton<String>(
        key: const Key('card_menu'),
        tooltip: context.tr('card_menu'),
        icon: Icon(Icons.more_vert_rounded, size: 18, color: p.textMuted),
        onSelected: (v) {
          trackInput(context, 'dataset.menu.open', v);
          switch (v) {
            case 'info':
              _showInfo();
            case 'minimize':
              c.onToggleMinimize?.call();
            case 'move':
              c.onMove?.call();
            case 'table':
              widget.onToggleTable?.call();
            case 'share':
              widget.onShare?.call();
            case 'visibility_public':
              c.onChangeVisibility?.call('public');
            case 'visibility_asodya':
              c.onChangeVisibility?.call('asodya');
            case 'visibility_personal':
              c.onChangeVisibility?.call('personal');
            case 'delete':
              _confirmDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'info',
            key: const Key('card_menu_info'),
            child: track(
              'dataset.menu.info',
              _menuRow(context, Icons.info_outline_rounded, context.tr('info')),
            ),
          ),
          if (widget.onToggleTable != null && !c.minimized)
            PopupMenuItem(
              value: 'table',
              key: const Key('card_menu_table'),
              child: track(
                'dataset.menu.table',
                _menuRow(
                  context,
                  widget.tableView
                      ? Icons.bar_chart_rounded
                      : Icons.table_rows_outlined,
                  context.tr(widget.tableView ? 'show_chart' : 'show_table'),
                ),
              ),
            ),
          if (widget.onShare != null)
            PopupMenuItem(
              value: 'share',
              key: const Key('card_menu_share'),
              child: track(
                'dataset.menu.share',
                _menuRow(context, Icons.share_outlined, context.tr('share')),
              ),
            ),
          if (c.onToggleMinimize != null)
            PopupMenuItem(
              value: 'minimize',
              key: const Key('card_menu_minimize'),
              child: track(
                'dataset.menu.minimize',
                _menuRow(
                  context,
                  c.minimized
                      ? Icons.unfold_more_rounded
                      : Icons.unfold_less_rounded,
                  context.tr(c.minimized ? 'restore' : 'minimize'),
                ),
              ),
            ),
          if (c.onMove != null)
            PopupMenuItem(
              value: 'move',
              key: const Key('card_menu_move'),
              child: track(
                'dataset.menu.move',
                _menuRow(context, Icons.open_with_rounded, context.tr('move')),
              ),
            ),
          if (showOwnerActions) const PopupMenuDivider(),
          if (c.isOwner && c.onChangeVisibility != null) ...[
            for (final vis in const ['public', 'asodya', 'personal'])
              PopupMenuItem(
                value: 'visibility_$vis',
                key: Key('card_menu_visibility_$vis'),
                child: _menuRow(
                  context,
                  widget.descriptor.visibility == vis
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  '${context.tr('visibility_label')}: ${context.tr('visibility_$vis')}',
                ),
              ),
          ],
          if (c.isOwner && c.onDelete != null)
            PopupMenuItem(
              value: 'delete',
              key: const Key('card_menu_delete'),
              child: _menuRow(
                context,
                Icons.delete_outline_rounded,
                context.tr('delete_card'),
                color: p.negative,
              ),
            ),
        ],
      ),
    );
  }

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color ?? context.palette.textMuted),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: color == null ? null : TextStyle(color: color),
        ),
      ),
    ],
  );

  Widget _smallMark(BuildContext context, Key key, String text, Color color) =>
      Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.controls;
    final d = widget.descriptor;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: track('dataset.chart.surface', widget.body),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // Flat surface (Carbon): the surface color separates the card; an outline on hover only.
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
          border: Border.all(
            color: _hover ? p.textMuted.withValues(alpha: 0.6) : p.surface,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: widget.fill && !c.minimized
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 4, c.minimized ? 8 : 4),
              child: Row(
                children: [
                  // The title takes the free width; the access tag follows it (none when public).
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (d.visibility != 'public') ...[
                          const SizedBox(width: 8),
                          AccessTag(visibility: d.visibility),
                        ],
                        if (c.isLive != null) ...[
                          const SizedBox(width: 6),
                          _smallMark(
                            context,
                            Key(
                              c.isLive! ? 'card_mark_live' : 'card_mark_static',
                            ),
                            context.tr(c.isLive! ? 'mark_live' : 'mark_static'),
                            c.isLive! ? p.positive : p.textMuted,
                          ),
                        ],
                        if (c.isOwner) ...[
                          const SizedBox(width: 6),
                          _smallMark(
                            context,
                            const Key('card_mark_owner'),
                            context.tr('mark_owner'),
                            p.info,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (c.minimized)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        context.tr('minimized'),
                        style: TextStyle(fontSize: 11.5, color: p.textMuted),
                      ),
                    ),
                  ...widget.headerActions,
                  _menu(context),
                ],
              ),
            ),
            if (!c.minimized) ...[
              if (widget.toolbar != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: widget.toolbar,
                ),
              SizedBox(
                height: 2,
                child: widget.loading
                    ? LinearProgressIndicator(
                        minHeight: 2,
                        color: p.accent,
                        backgroundColor: Colors.transparent,
                      )
                    : null,
              ),
              // While new rows load, the old chart stays at half opacity.
              if (widget.fill)
                Expanded(
                  child: AnimatedOpacity(
                    opacity: widget.loading ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: body,
                  ),
                )
              else
                AnimatedOpacity(
                  opacity: widget.loading ? 0.5 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: body,
                ),
              if (widget.footer != null) widget.footer!,
              if (d.equation != null && d.equation!.isNotEmpty)
                Container(
                  key: const Key('equation_footer'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: Tooltip(
                    message: d.equation!,
                    child: Text(
                      d.equation!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ReportPalette.monoFont,
                        fontSize: 11.5,
                        color: p.textMuted,
                      ),
                      semanticsLabel:
                          '${context.tr('equation')}: ${d.equation}',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
