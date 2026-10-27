import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';
import 'breadcrumbs.dart';

/// Top of a page: breadcrumb trail, title, optional subtitle and actions.
class PageHeader extends StatelessWidget {
  final List<Crumb> crumbs;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// With a value, a long subtitle shows that many lines and a "Show more" link.
  final int? subtitleLines;

  const PageHeader({
    super.key,
    required this.crumbs,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.subtitleLines,
  });

  /// Below this width the actions go under the title.
  static const double narrow = 600;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Breadcrumbs(crumbs: crumbs),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final heading = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        subtitleLines == null
                            ? Text(
                                subtitle!,
                                style: text.bodyMedium?.copyWith(
                                  color: p.textMuted,
                                ),
                              )
                            : ClampedText(
                                subtitle!,
                                lines: subtitleLines!,
                                style: text.bodyMedium?.copyWith(
                                  color: p.textMuted,
                                  height: 1.5,
                                ),
                              ),
                      ],
                    ],
                  ),
                ),
                if (c.maxWidth >= narrow) ...actions,
              ],
            );
            // Narrow screens put the actions on their own line under the title.
            if (c.maxWidth >= narrow || actions.isEmpty) return heading;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final a in actions) Flexible(child: a)],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Long text that shows [lines] lines at most (a readable width), with a "Show more" link
/// when it does not fit and "Show less" once open.
class ClampedText extends StatefulWidget {
  final String text;
  final int lines;
  final TextStyle? style;

  const ClampedText(this.text, {super.key, required this.lines, this.style});

  @override
  State<ClampedText> createState() => _ClampedTextState();
}

class _ClampedTextState extends State<ClampedText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            maxLines: widget.lines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: c.maxWidth);
          final long = painter.didExceedMaxLines;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                key: const Key('clamped_text'),
                style: widget.style,
                maxLines: _open ? null : widget.lines,
                overflow: _open ? null : TextOverflow.ellipsis,
              ),
              if (long)
                track(
                  'report.description.expand',
                  InkWell(
                    key: const Key('clamped_toggle'),
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        context.tr(_open ? 'show_less' : 'show_more'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                          decoration: TextDecoration.underline,
                          decorationColor: p.border,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
