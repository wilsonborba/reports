import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../themes/report_palette.dart';
import 'public_layout.dart';
import 'public_motion.dart';

/// One formula: a name, the TeX source and a short caption.
class Formula {
  final String nameKey;
  final String tex;

  /// Caption key; by convention the name key with `_d`.
  String get captionKey => '${nameKey}_d';

  const Formula(this.nameKey, this.tex);
}

/// Formula typeset with flutter_math_fork (KaTeX layout and fonts, pure Dart). A wide
/// formula scales down to fit a phone. A formula that cannot be parsed shows its source.
class MathFormula extends StatelessWidget {
  final String tex;
  final double fontSize;

  const MathFormula(this.tex, {super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Math.tex(
        tex,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(fontSize: fontSize, color: p.textPrimary),
        onErrorFallback: (e) => Text(
          tex,
          style: TextStyle(
            fontFamily: ReportPalette.monoFont,
            color: p.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Card of one formula: the name, the typeset formula and the caption.
class FormulaCard extends StatelessWidget {
  final String name;
  final String tex;
  final String caption;
  final VoidCallback? onTap;

  const FormulaCard({
    super.key,
    required this.name,
    required this.tex,
    required this.caption,
    this.onTap,
  });

  static const double height = 210;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: publicCardColor(context),
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_rounded, size: 16, color: p.textMuted),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: MathFormula(tex),
            ),
          ),
          Text(
            caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.45),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      link: true,
      child: track('public.formula.open', InkWell(onTap: onTap, child: card)),
    );
  }
}

/// Grid of formula cards of the same height (1, 2 or 3 columns from the width).
class FormulaGrid extends StatelessWidget {
  final List<Widget> cards;

  const FormulaGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final width = PublicLayout.width(context);
    final cols = width < PublicLayout.md
        ? 1
        : (width < PublicLayout.lg ? 2 : 3);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(
                width: w,
                child: Reveal(
                  delay: Duration(milliseconds: 60 * (i % cols)),
                  child: cards[i],
                ),
              ),
          ],
        );
      },
    );
  }
}
