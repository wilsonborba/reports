import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';

class Crumb {
  final String label;

  /// Route of the crumb. The current page (last crumb) has no route.
  final String? route;

  const Crumb(this.label, [this.route]);
}

/// Small breadcrumb trail shown at the top of every page. It shows the hierarchy
/// (not the history), uses '>' separators, never wraps, and keeps the last two
/// levels on narrow screens.
class Breadcrumbs extends StatelessWidget {
  final List<Crumb> crumbs;

  const Breadcrumbs({super.key, required this.crumbs});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: context.tr('breadcrumb'),
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final visible = narrow && crumbs.length > 2
              ? crumbs.sublist(crumbs.length - 2)
              : crumbs;
          final children = <Widget>[];
          if (visible.length < crumbs.length) {
            children.add(
              Text('…', style: TextStyle(color: p.textMuted, fontSize: 12.5)),
            );
            children.add(_separator(p));
          }
          for (var i = 0; i < visible.length; i++) {
            final c = visible[i];
            final last = i == visible.length - 1;
            children.add(
              Flexible(
                flex: last ? 3 : 2,
                child: last || c.route == null
                    ? Text(
                        c.label,
                        key: Key('crumb_${crumbs.indexOf(c)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      )
                    : track(
                        'shell.breadcrumb.open',
                        InkWell(
                          key: Key('crumb_${crumbs.indexOf(c)}'),
                          borderRadius: BorderRadius.circular(
                            ReportPalette.controlRadius,
                          ),
                          onTap: () => context.go(c.route!),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: p.textMuted,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            );
            if (!last) children.add(_separator(p));
          }
          return Row(mainAxisSize: MainAxisSize.min, children: children);
        },
      ),
    );
  }

  Widget _separator(ReportPalette p) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Icon(Icons.chevron_right_rounded, size: 15, color: p.textMuted),
  );
}
