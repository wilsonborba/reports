import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_registry.dart';
import '../../widgets/catalog/catalog_widgets.dart';
import '../../widgets/landing/project_tile.dart';
import '../../widgets/public/project_logo.dart';
import '../../widgets/public/public_blocks.dart';
import '../../widgets/public/public_layout.dart';
import '../../widgets/public/public_motion.dart';
import '../../widgets/public/public_page.dart';
import 'overview_view.dart';

/// Projects page (/v1/home/projects): one block per active project of the catalog API
/// (texts, links, Domain details, facts and theme colors), then the methods of Reports.
/// Everything about a project comes from the engine, which composes domain_api data.
class ProjectsView extends StatelessWidget {
  const ProjectsView({super.key});

  @override
  Widget build(BuildContext context) {
    return PublicPage(sections: (context, data) {
      final p = context.palette;
      return [
        PublicHero(
          eyebrow: context.tr('pub_nav_projects'),
          title: context.tr('pub_projects_title'),
          lead: context.tr('pub_projects_lead'),
        ),
        if (data.projectsFailed)
          PublicSection(topBorder: true, child: StateMessage(icon: Icons.cloud_off_rounded, title: context.tr('error_loading')))
        else if (data.projects.isEmpty)
          PublicSection(topBorder: true, child: StateMessage(icon: Icons.folder_off_outlined, title: context.tr('no_projects')))
        else
          for (var i = 0; i < data.projects.length; i++)
            PublicSection(
              key: Key('project_block_${data.projects[i].slug}'),
              background: i.isEven ? p.surface : p.canvas,
              child: _ProjectBlock(project: data.projects[i], reverse: i.isOdd),
            ),
        PublicSection(
          topBorder: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeading(title: context.tr('pub_methods_title'), intro: context.tr('pub_methods_intro')),
            CardGrid(columns: 4, children: [
              for (final (icon, label, key) in [
                (Icons.rule_rounded, 'pub_topic_de', 'schemas'),
                (Icons.functions_rounded, 'pub_topic_st', 'calculations'),
                (Icons.lock_outline_rounded, 'pub_nav_architecture', 'access'),
                (Icons.file_download_outlined, 'pub_nav_reports', 'exports'),
              ])
                PublicCard(
                  key: Key('method_$key'),
                  top: Icon(icon, size: 28, color: p.textPrimary),
                  label: context.tr(label),
                  title: context.tr('pub_method_${key}_t'),
                  text: context.tr('pub_method_${key}_d'),
                ),
            ]),
          ]),
        ),
        ...nextStepBand(context),
      ];
    });
  }
}

class _ProjectBlock extends StatelessWidget {
  final ProjectSummary project;
  final bool reverse;

  const _ProjectBlock({required this.project, required this.reverse});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = project;
    final phone = PublicLayout.isPhone(context);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 4, width: 64, color: projectAccent(context, pr.slug)),
      const SizedBox(height: 24),
      ProjectLogo(project: pr, height: 48),
      const SizedBox(height: 20),
      Text(pr.name, style: TextStyle(fontSize: phone ? 28 : 36, fontWeight: FontWeight.w300, color: p.textPrimary, height: 1.2)),
      if (pr.tagline.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(pr.tagline, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: p.textPrimary, height: 1.4)),
      ],
      if (pr.description.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(pr.description, style: TextStyle(fontSize: 15, color: p.textMuted, height: 1.6)),
      ],
      if (pr.domain != null && pr.domain!.categories.isNotEmpty) ...[
        const SizedBox(height: 16),
        Wrap(key: Key('proj_categories_${pr.slug}'), spacing: 8, runSpacing: 8, children: [
          for (final c in pr.domain!.categories)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
              child: Text(c.item, style: TextStyle(fontSize: 12.5, color: p.textMuted)),
            ),
        ]),
      ],
      const SizedBox(height: 28),
      Wrap(spacing: 12, runSpacing: 12, children: [
        // The page repeats one block per project, so no block has a primary button
        // (Carbon): the reports of the project first, the outside links as ghosts.
        PublicButton(
          key: Key('proj_reports_${pr.slug}'),
          label: context.tr('open_reports'),
          kind: ButtonKind.tertiary,
          onPressed: () => context.go(AppRoutes.project(pr.slug)),
        ),
        if (pr.websiteUrl != null)
          PublicButton(
            key: Key('proj_website_${pr.slug}'),
            label: context.tr('website'),
            kind: ButtonKind.ghost,
            icon: Icons.open_in_new_rounded,
            onPressed: () => openPublicLink(pr.websiteUrl!),
          ),
        if (pr.repositoryUrl != null && pr.repositoryUrl != pr.websiteUrl)
          PublicButton(
            key: Key('proj_repository_${pr.slug}'),
            label: context.tr('pub_project_repository'),
            kind: ButtonKind.ghost,
            icon: Icons.code_rounded,
            onPressed: () => openPublicLink(pr.repositoryUrl!),
          ),
      ]),
    ]);
    return SplitBlock(reverse: reverse, text: text, visual: Reveal(delay: const Duration(milliseconds: 150), child: _Facts(project: pr)));
  }
}

/// Facts of a project from the catalog: website, contact, report count and theme colors.
class _Facts extends StatelessWidget {
  final ProjectSummary project;

  const _Facts({required this.project});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = project;
    final none = context.tr('pub_fact_none');
    final domain = pr.domain;
    final series = ThemeRegistry.palette(pr.slug, Theme.of(context).brightness).series;
    Widget row(String label, Widget value) => Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 14, color: p.textMuted))),
            Expanded(child: value),
          ]),
        );
    Text value(String v) => Text(v, style: TextStyle(fontSize: 15, color: p.textPrimary));
    return Container(
      key: Key('project_facts_${pr.slug}'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('pub_facts_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary)),
        const SizedBox(height: 12),
        row(context.tr('website'), value(pr.websiteUrl == null ? context.tr('no_website') : ProjectTile.domainOf(pr.websiteUrl!))),
        row(context.tr('pub_project_repository'), value(pr.repositoryUrl == null ? none : ProjectTile.domainOf(pr.repositoryUrl!))),
        if (domain?.status != null) row(context.tr('pub_fact_status'), value(domain!.status!)),
        row(context.tr('stat_reports'), value('${pr.reportCount}')),
        // domain_api statistics, as domain_api sends them (not translated).
        for (final s in (domain?.statistics ?? const <DomainStatistic>[]).take(6)) row(s.name, value(s.value)),
        if (domain != null && domain.collaborators.isNotEmpty)
          row(context.tr('pub_fact_collaborators'), value(domain.collaborators.map((c) => c.githubUsername ?? c.name).join(', '))),
        row(
          context.tr('pub_fact_colors'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in series) Container(width: 22, height: 22, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(ReportPalette.controlRadius))),
          ]),
        ),
        if (pr.domainStatus == 'stale' || (domain?.detailStale ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(context.tr('pub_domain_stale').replaceAll('{time}', domain?.fetchedAt.split('T').first ?? ''),
                key: Key('domain_stale_${pr.slug}'), style: TextStyle(fontSize: 12, color: p.textMuted)),
          ),
      ]),
    );
  }
}
