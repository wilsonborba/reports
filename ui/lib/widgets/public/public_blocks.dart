import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../themes/report_palette.dart';
import 'public_layout.dart';
import 'public_motion.dart';

/// Building blocks of the public pages, after the IBM solutions page structure: hero,
/// section heading, cards in a grid, call to action band and statistic band. Flat Carbon
/// style (square corners, no shadows), palette tokens only, Ubuntu Sans fonts.

/// Small label above a title (Carbon eyebrow).
class Eyebrow extends StatelessWidget {
  final String text;

  const Eyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: context.palette.highlight,
      letterSpacing: 0.16,
    ),
  );
}

/// Hero of a page: eyebrow, large light title, lead text and buttons on the left, a visual
/// on the right. Phones put the visual below the texts.
class PublicHero extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String lead;
  final List<Widget> actions;
  final Widget? visual;

  const PublicHero({
    super.key,
    this.eyebrow,
    required this.title,
    required this.lead,
    this.actions = const [],
    this.visual,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = PublicLayout.isPhone(context);
    final wide = PublicLayout.isWide(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 16)],
        Text(
          title,
          key: const Key('public_hero_title'),
          style: TextStyle(
            fontSize: phone ? 34 : (wide ? 54 : 44),
            fontWeight: FontWeight.w300,
            color: p.textPrimary,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            lead,
            style: TextStyle(
              fontSize: phone ? 16 : 20,
              fontWeight: FontWeight.w300,
              color: p.textMuted,
              height: 1.5,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 32),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ],
    );
    return PublicSection(
      vertical: phone ? 40 : 88,
      child: wide && visual != null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: Reveal(child: texts)),
                const SizedBox(width: 48),
                Expanded(flex: 6, child: visual!),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Reveal(child: texts),
                if (visual != null) ...[
                  SizedBox(height: phone ? 32 : 48),
                  visual!,
                ],
              ],
            ),
    );
  }
}

/// Heading of a section: optional eyebrow, title and intro text.
class SectionHeading extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? intro;

  const SectionHeading({
    super.key,
    this.eyebrow,
    required this.title,
    this.intro,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = PublicLayout.isPhone(context);
    return Reveal(
      child: Padding(
        padding: EdgeInsets.only(bottom: phone ? 24 : 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Eyebrow(eyebrow!),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: phone ? 26 : 32,
                fontWeight: FontWeight.w300,
                color: p.textPrimary,
                height: 1.25,
              ),
            ),
            if (intro != null) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  intro!,
                  style: TextStyle(
                    fontSize: 16,
                    color: p.textMuted,
                    height: 1.55,
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

/// Grid of equal-height cards. Columns: 1 on phones, 2 on tablets, [columns] on desktops.
class CardGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double gap;

  const CardGrid({
    super.key,
    required this.children,
    this.columns = 3,
    this.gap = 16,
  });

  static int columnsFor(double width, int max) => width < PublicLayout.md
      ? 1
      : (width < PublicLayout.lg ? (max < 2 ? max : 2) : max);

  @override
  Widget build(BuildContext context) {
    final cols = columnsFor(PublicLayout.width(context), columns);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final cells = <Widget>[];
      for (var c = 0; c < cols; c++) {
        if (c > 0) cells.add(SizedBox(width: gap));
        final index = i + c;
        cells.add(
          Expanded(
            child: index < children.length
                ? Reveal(
                    delay: Duration(milliseconds: 80 * c),
                    child: children[index],
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      // Every card of a row gets the height of the tallest one (cards keep their link line at the bottom).
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(
      key: Key('card_grid_$cols'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Flat card: label, title, text, optional top visual and a link line at the bottom.
/// The whole card is the link; hover shows the alternate surface.
class PublicCard extends StatefulWidget {
  final String? label;
  final String title;
  final String? text;
  final String? linkLabel;
  final VoidCallback? onTap;
  final Widget? top;
  final Widget? bottom;
  final IconData linkIcon;

  const PublicCard({
    super.key,
    this.label,
    required this.title,
    this.text,
    this.linkLabel,
    this.onTap,
    this.top,
    this.bottom,
    this.linkIcon = Icons.arrow_forward_rounded,
  });

  @override
  State<PublicCard> createState() => _PublicCardState();
}

class _PublicCardState extends State<PublicCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: _hover ? p.surfaceAlt : publicCardColor(context),
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.top != null) ...[widget.top!, const SizedBox(height: 20)],
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: TextStyle(
                fontSize: 13,
                color: p.textMuted,
                letterSpacing: 0.16,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: p.textPrimary,
              height: 1.3,
            ),
          ),
          if (widget.text != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.text!,
              style: TextStyle(fontSize: 14, color: p.textMuted, height: 1.5),
            ),
          ],
          if (widget.bottom != null) ...[
            const SizedBox(height: 16),
            widget.bottom!,
          ],
          const Spacer(),
          if (widget.linkLabel != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Flexible(
                  child: Text(
                    widget.linkLabel!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 150),
                  offset: Offset(_hover ? 0.25 : 0, 0),
                  child: Icon(widget.linkIcon, size: 18, color: p.textPrimary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (widget.onTap == null) return card;
    return Semantics(
      link: true,
      child: track(
        'public.feature.open',
        InkWell(
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hover = h),
          borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
          child: card,
        ),
      ),
    );
  }
}

/// Emphasis of a public page button (Carbon): one primary per page, tertiary for other
/// positive actions, ghost for the least pronounced ones.
enum ButtonKind { primary, tertiary, ghost }

/// Button of the public pages, with an icon after the label.
class PublicButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData icon;

  const PublicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.primary,
    this.icon = Icons.arrow_forward_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 18);
    final label = Text(this.label);
    final icon = Icon(this.icon, size: 18);
    return switch (kind) {
      ButtonKind.primary => FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          padding: padding,
        ),
        iconAlignment: IconAlignment.end,
        icon: icon,
        label: label,
      ),
      // Tertiary: outline and text in the interactive color.
      ButtonKind.tertiary => OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: padding,
          foregroundColor: p.accent,
          side: BorderSide(color: p.accent),
        ),
        iconAlignment: IconAlignment.end,
        icon: icon,
        label: label,
      ),
      ButtonKind.ghost => TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: padding,
          foregroundColor: p.accent,
        ),
        iconAlignment: IconAlignment.end,
        icon: icon,
        label: label,
      ),
    };
  }
}

/// Text link with an arrow (Carbon link with icon).
class ArrowLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData icon;

  const ArrowLink({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = onTap == null ? p.textMuted : p.textPrimary;
    return Semantics(
      link: true,
      child: track(
        'public.link.open',
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color,
                      decoration: onTap == null
                          ? null
                          : TextDecoration.underline,
                      decorationColor: p.border,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(icon, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One item of a call to action band.
class CtaItem {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  final Key? key;

  const CtaItem({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.key,
  });
}

/// "Take the next step" band: a heading on the left, link tiles on the right.
class CtaBand extends StatelessWidget {
  final String title;
  final String text;
  final List<CtaItem> items;

  const CtaBand({
    super.key,
    required this.title,
    required this.text,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wide = PublicLayout.isWide(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w300,
            color: p.textPrimary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: TextStyle(fontSize: 16, color: p.textMuted, height: 1.5),
        ),
      ],
    );
    final tiles = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Semantics(
            link: true,
            child: track(
              'public.card.open',
              InkWell(
                key: item.key,
                onTap: item.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 28, color: p.textPrimary),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 18,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: p.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: p.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return PublicSection(
      background: p.surface,
      child: Reveal(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: heading),
                  const SizedBox(width: 48),
                  Expanded(flex: 7, child: tiles),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 24), tiles],
              ),
      ),
    );
  }
}

/// Statistic band: large light numbers or short words with a label under each.
class StatBand extends StatelessWidget {
  final List<(String value, String label)> items;

  const StatBand({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = CardGrid.columnsFor(
      PublicLayout.width(context),
      items.length.clamp(1, 4),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 24,
          children: [
            for (final (i, (value, label)) in items.indexed)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.only(top: 16),
                  // One asodya.com color per statistic, on the rail; the number keeps the text color.
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: p.seriesAt(i + 1), width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w300,
                          color: p.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          color: p.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Text on the left and a visual on the right; phones stack them.
class SplitBlock extends StatelessWidget {
  final Widget text;
  final Widget visual;

  /// Visual on the left on wide screens.
  final bool reverse;

  const SplitBlock({
    super.key,
    required this.text,
    required this.visual,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!PublicLayout.isWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(child: text),
          const SizedBox(height: 32),
          visual,
        ],
      );
    }
    final parts = [
      Expanded(flex: 5, child: Reveal(child: text)),
      const SizedBox(width: 48),
      Expanded(flex: 7, child: visual),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: reverse ? parts.reversed.toList() : parts,
    );
  }
}

/// Line with a check mark (short list of facts).
class CheckLine extends StatelessWidget {
  final String text;

  const CheckLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_rounded, size: 18, color: p.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 15, color: p.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
