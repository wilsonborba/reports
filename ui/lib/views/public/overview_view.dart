import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/session_store.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../widgets/catalog/catalog_widgets.dart';
import '../../widgets/public/code_panel.dart';
import '../../widgets/public/flow_diagram.dart';
import '../../widgets/public/project_logo.dart';
import '../../widgets/public/public_blocks.dart';
import '../../widgets/public/public_layout.dart';
import '../../widgets/public/public_motion.dart';
import '../../widgets/public/public_page.dart';
import '../../widgets/public/science_charts.dart';
import 'api_examples.dart';

/// Example ingestion batch of the data engineering panel: one Cortex record (sample data).
const String ingestionEnvelopeJson = '''{
  "schema_version": 1,
  "records": [{
    "idempotency_key": "cortex-req-00001",
    "event_time": "2026-10-21T09:14:03Z",
    "payload": {
      "request_id": "req-00001",
      "execution_id": "exe-00001",
      "strategy_id": "tier1-default",
      "tier_requested": 1,
      "tier_executed": 1,
      "task_type": "chat",
      "provider": "ollama",
      "model": "qwen2.5:7b",
      "role": "primary",
      "input_tokens": 812,
      "output_tokens": 240,
      "total_tokens": 1052,
      "started_at": "2026-10-21T09:14:03Z",
      "latency_ms": 2140,
      "success": true
    }
  }]
}''';

/// Overview of the public site (/v1/home): Reports and the projects
/// from the catalog API, the five fields of data work, the ingestion envelope and the
/// next steps. Layout after the IBM solutions page.
class OverviewView extends StatelessWidget {
  const OverviewView({super.key});

  static List<FlowStep> flowSteps(BuildContext context) => [
    FlowStep(
      context.tr('pub_flow_sources'),
      context.tr('pub_flow_sources_d'),
      Icons.sensors_rounded,
    ),
    FlowStep(
      context.tr('pub_flow_ingest'),
      context.tr('pub_flow_ingest_d'),
      Icons.input_rounded,
    ),
    FlowStep(
      context.tr('pub_flow_lake'),
      context.tr('pub_flow_lake_d'),
      Icons.storage_rounded,
    ),
    FlowStep(
      context.tr('pub_flow_models'),
      context.tr('pub_flow_models_d'),
      Icons.hub_outlined,
    ),
    FlowStep(
      context.tr('pub_flow_reports'),
      context.tr('pub_flow_reports_d'),
      Icons.insert_chart_outlined_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PublicPage(
      sections: (context, data) {
        final p = context.palette;
        return [
          PublicHero(
            eyebrow: context.tr('pub_home_eyebrow'),
            title: context.tr('pub_home_title'),
            lead: context.tr('pub_home_lead'),
            // One primary action and the session action. Projects and science have their
            // tabs and their sections further down this page.
            actions: [
              track(
                'public.overview.reports',
                PublicButton(
                  key: const Key('home_cta_reports'),
                  label: context.tr('pub_cta_reports_title'),
                  onPressed: () => context.go(AppRoutes.menu),
                ),
              ),
              const _SessionAction(),
            ],
            // The data path, then the kind of chart that the reports show at its end.
            visual: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FlowDiagram(steps: flowSteps(context)),
                const SizedBox(height: 16),
                const GrowingBars(),
              ],
            ),
          ),
          PublicSection(
            topBorder: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeading(
                  title: context.tr('pub_home_projects_title'),
                  intro: context.tr('pub_home_projects_intro'),
                ),
                if (data.projectsFailed)
                  StateMessage(
                    icon: Icons.cloud_off_rounded,
                    title: context.tr('error_loading'),
                  )
                else if (data.projects.isEmpty)
                  StateMessage(
                    icon: Icons.folder_off_outlined,
                    title: context.tr('no_projects'),
                  )
                else
                  CardGrid(
                    columns: data.projects.length >= 4 ? 4 : 3,
                    children: [
                      for (final pr in data.projects)
                        PublicCard(
                          key: Key('home_project_${pr.slug}'),
                          top: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 3,
                                width: 48,
                                color: projectAccent(context, pr.slug),
                              ),
                              const SizedBox(height: 20),
                              ProjectLogo(project: pr, height: 36),
                            ],
                          ),
                          label: context.tr('pub_project_label'),
                          title: pr.name,
                          text: pr.tagline.isEmpty ? null : pr.tagline,
                          linkLabel: pr.websiteUrl == null
                              ? context.tr('pub_learn_more')
                              : context.tr('pub_visit_website'),
                          linkIcon: pr.websiteUrl == null
                              ? Icons.arrow_forward_rounded
                              : Icons.open_in_new_rounded,
                          onTap: pr.websiteUrl == null
                              ? () => context.go(AppRoutes.homeProjects)
                              : () => openPublicLink(pr.websiteUrl!),
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
                  title: context.tr('pub_home_science_title'),
                  intro: context.tr('pub_home_science_intro'),
                ),
                CardGrid(
                  columns: 3,
                  children: [
                    for (var i = 0; i < scienceTopics.length; i++)
                      PublicCard(
                        key: Key('home_topic_${scienceTopics[i].$1}'),
                        top: Container(
                          height: 3,
                          width: 48,
                          color: p.seriesAt(i + 1),
                        ),
                        label: '0${i + 1}',
                        title: context.tr(scienceTopics[i].$2),
                        text: context.tr('${scienceTopics[i].$2}_short'),
                        linkLabel: context.tr('pub_read_more'),
                        onTap: () => context.go(
                          AppRoutes.scienceTopic(scienceTopics[i].$1),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PublicSection(
            child: SplitBlock(
              text: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.tr('pub_home_data_eyebrow')),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('pub_home_data_title'),
                    style: TextStyle(
                      fontSize: PublicLayout.isPhone(context) ? 26 : 32,
                      fontWeight: FontWeight.w300,
                      color: p.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('pub_home_data_text'),
                    style: TextStyle(
                      fontSize: 16,
                      color: p.textMuted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final k in [
                    'pub_home_data_p1',
                    'pub_home_data_p2',
                    'pub_home_data_p3',
                  ])
                    CheckLine(context.tr(k)),
                  const SizedBox(height: 16),
                  ArrowLink(
                    label: context.tr('pub_read_more'),
                    onTap: () =>
                        context.go(AppRoutes.scienceTopic('data-engineering')),
                  ),
                ],
              ),
              visual: const CodePanel(
                title: 'ingest_batch.json',
                code: ingestionEnvelopeJson,
                language: CodeLanguage.json,
              ),
            ),
          ),
          PublicSection(
            key: const Key('home_architecture_teaser'),
            background: p.surface,
            child: SplitBlock(
              reverse: true,
              text: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.tr('pub_nav_architecture')),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('architecture_title'),
                    style: TextStyle(
                      fontSize: PublicLayout.isPhone(context) ? 26 : 32,
                      fontWeight: FontWeight.w300,
                      color: p.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('architecture_subtitle'),
                    style: TextStyle(
                      fontSize: 16,
                      color: p.textMuted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      ArrowLink(
                        key: const Key('home_architecture_more'),
                        label: context.tr('pub_read_more'),
                        onTap: () => context.go(AppRoutes.homeArchitecture),
                      ),
                    ],
                  ),
                ],
              ),
              visual: const CodePanel(
                title: 'request.sh',
                code: datasetRequestShell,
                language: CodeLanguage.shell,
              ),
            ),
          ),
          PublicSection(
            topBorder: true,
            vertical: PublicLayout.isPhone(context) ? 32 : 56,
            child: Reveal(
              child: StatBand(
                items: [
                  ('${data.projects.length}', context.tr('pub_stat_projects')),
                  ('2', context.tr('pub_stat_languages')),
                  ('${scienceTopics.length}', context.tr('pub_stat_fields')),
                  ('1', context.tr('pub_nav_architecture')),
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

/// "Take the next step" band shared by the public pages: reports and contact.
List<Widget> nextStepBand(BuildContext context) => [
  CtaBand(
    title: context.tr('pub_cta_title'),
    text: context.tr('pub_cta_text'),
    items: [
      CtaItem(
        key: const Key('cta_reports'),
        icon: Icons.insert_chart_outlined_rounded,
        title: context.tr('pub_cta_reports_title'),
        text: context.tr('pub_cta_reports_text'),
        onTap: () => context.go(AppRoutes.menu),
      ),
      CtaItem(
        key: const Key('cta_contact'),
        icon: Icons.mail_outline_rounded,
        title: context.tr('pub_nav_contact'),
        text: context.tr('pub_cta_contact_text'),
        onTap: () => context.go(AppRoutes.homeContact),
      ),
    ],
  ),
];

/// Sign in of a guest, as the ghost button next to the hero action. A signed-in user logs
/// out from the top bar.
class _SessionAction extends StatelessWidget {
  const _SessionAction();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionStore.instance,
      builder: (context, _) {
        final session = SessionStore.instance;
        if (!session.isLoaded || session.hasSession) {
          return const SizedBox.shrink();
        }
        return track(
          'public.overview.login',
          PublicButton(
            key: const Key('home_sign_in'),
            label: context.tr('sign_in'),
            kind: ButtonKind.ghost,
            icon: Icons.login_rounded,
            onPressed: () =>
                AuthService.instance.signIn(returnTo: AppRoutes.menu),
          ),
        );
      },
    );
  }
}
