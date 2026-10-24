import 'package:flutter/material.dart';
import '../../themes/report_palette.dart';
import 'breadcrumbs.dart';

/// Top of a page: breadcrumb trail, title, optional subtitle and actions.
class PageHeader extends StatelessWidget {
  final List<Crumb> crumbs;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.crumbs,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Breadcrumbs(crumbs: crumbs),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: p.textPrimary)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: text.bodyMedium?.copyWith(color: p.textMuted)),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ],
    );
  }
}
