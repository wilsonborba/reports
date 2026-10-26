import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../widgets/catalog/catalog_widgets.dart';
import '../../widgets/public/code_panel.dart';
import '../../widgets/public/formula_card.dart';
import '../../widgets/public/public_blocks.dart';
import '../../widgets/public/public_layout.dart';
import '../../widgets/public/public_motion.dart';
import '../../widgets/public/public_page.dart';
import '../../widgets/public/science_charts.dart';
import 'overview_view.dart';
import 'science_content.dart';

/// Science index (/v1/home/science): the five fields of work and every formula, each
/// linked to its topic page.
class ScienceView extends StatelessWidget {
  const ScienceView({super.key});

  @override
  Widget build(BuildContext context) {
    return PublicPage(
      sections: (context, data) {
        final p = context.palette;
        return [
          PublicHero(
            eyebrow: context.tr('pub_nav_science'),
            title: context.tr('pub_sci_title'),
            lead: context.tr('pub_sci_lead'),
            visual: const NeuralNetDiagram(),
          ),
          PublicSection(
            topBorder: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: context.tr('pub_sci_topics_title')),
                CardGrid(
                  columns: 3,
                  children: [
                    for (var i = 0; i < scienceContent.length; i++)
                      PublicCard(
                        key: Key('science_topic_${scienceContent[i].id}'),
                        label: '0${i + 1}',
                        title: context.tr(scienceContent[i].titleKey),
                        text: context.tr(scienceContent[i].summaryKey),
                        linkLabel: context.tr('pub_read_more'),
                        onTap: () => context.go(
                          AppRoutes.scienceTopic(scienceContent[i].id),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PublicSection(
            background: p.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  title: context.tr('pub_sci_math_title'),
                  intro: context.tr('pub_sci_math_intro'),
                ),
                FormulaGrid(
                  cards: [
                    for (final topic in scienceContent)
                      for (final f in topic.formulas)
                        FormulaCard(
                          key: Key('formula_${f.nameKey}'),
                          name: context.tr(f.nameKey),
                          tex: f.tex,
                          caption:
                              '${context.tr(topic.titleKey)} · ${context.tr(f.captionKey)}',
                          onTap: () =>
                              context.go(AppRoutes.scienceTopic(topic.id)),
                        ),
                  ],
                ),
              ],
            ),
          ),
          ...nextStepBand(context),
        ];
      },
    );
  }
}

/// Page of one Science topic (/v1/home/science/:topic): hero with the decorative chart,
/// topic tabs, key ideas, code panels, formulas, the link to the projects and the next topic.
class ScienceTopicView extends StatelessWidget {
  final String topic;

  const ScienceTopicView({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final t = scienceTopic(topic);
    if (t == null) {
      return StateMessage(
        icon: Icons.search_off_rounded,
        title: context.tr('not_found'),
      );
    }
    final index = scienceContent.indexOf(t);
    final next = scienceContent[(index + 1) % scienceContent.length];
    // A new topic gets a new page state: the scroll starts at the top and the blocks play again.
    return PublicPage(
      key: ValueKey('science_${t.id}'),
      sections: (context, data) {
        final p = context.palette;
        return [
          PublicHero(
            eyebrow: context.tr('pub_nav_science'),
            title: context.tr(t.titleKey),
            lead: context.tr(t.leadKey),
            visual: t.chart(),
          ),
          _TopicTabs(current: t.id),
          PublicSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: context.tr('pub_sci_ideas')),
                CardGrid(
                  columns: 3,
                  children: [
                    for (var i = 1; i <= 3; i++)
                      PublicCard(
                        label: '0$i',
                        title: context.tr(t.pointTitle(i)),
                        text: context.tr(t.pointText(i)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (t.code.isNotEmpty)
            PublicSection(
              background: p.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(
                    title: context.tr(t.codeTitleKey),
                    intro: context.tr(t.codeTextKey),
                  ),
                  _CodeRow(
                    panels: [
                      for (final (title, code, language) in t.code)
                        CodePanel(title: title, code: code, language: language),
                    ],
                  ),
                ],
              ),
            ),
          PublicSection(
            topBorder: t.code.isEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(title: context.tr('pub_sci_math')),
                FormulaGrid(
                  cards: [
                    for (final f in t.formulas)
                      FormulaCard(
                        key: Key('formula_${f.nameKey}'),
                        name: context.tr(f.nameKey),
                        tex: f.tex,
                        caption: context.tr(f.captionKey),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PublicSection(
            background: p.surface,
            child: Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.tr('pub_sci_in_projects')),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Text(
                      context.tr(t.projectsKey),
                      style: TextStyle(
                        fontSize: PublicLayout.isPhone(context) ? 20 : 26,
                        fontWeight: FontWeight.w300,
                        color: p.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      ArrowLink(
                        label: context.tr('pub_home_cta_projects'),
                        onTap: () => context.go(AppRoutes.homeProjects),
                      ),
                      ArrowLink(
                        key: const Key('science_next'),
                        label: context.tr('pub_sci_next', {
                          'name': context.tr(next.titleKey),
                        }),
                        onTap: () =>
                            context.go(AppRoutes.scienceTopic(next.id)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ...nextStepBand(context),
        ];
      },
    );
  }
}

/// Tabs of the five topics under the hero (scrolls sideways on phones).
class _TopicTabs extends StatelessWidget {
  final String current;

  const _TopicTabs({required this.current});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border),
          bottom: BorderSide(color: p.border),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: PublicLayout.gutter(context)),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: PublicLayout.maxContent),
          child: Semantics(
            label: context.tr('pub_sci_topic_nav'),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in scienceContent)
                    track(
                      'public.science.topic',
                      InkWell(
                        key: Key('topic_tab_${t.id}'),
                        onTap: () => context.go(AppRoutes.scienceTopic(t.id)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: t.id == current
                                    ? p.accent
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            context.tr(t.titleKey),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: t.id == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: t.id == current
                                  ? p.textPrimary
                                  : p.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Code panels side by side on wide screens, stacked on narrow screens.
class _CodeRow extends StatelessWidget {
  final List<Widget> panels;

  const _CodeRow({required this.panels});

  @override
  Widget build(BuildContext context) {
    if (panels.length == 1 || !PublicLayout.isWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < panels.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            panels[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: panels[i]),
        ],
      ],
    );
  }
}
