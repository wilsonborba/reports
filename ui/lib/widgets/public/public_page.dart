import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../models/site.dart';
import '../../routes.dart';
import '../../core/build_info.dart';
import '../../services/catalog_service.dart';
import '../../themes/report_palette.dart';
import '../brand/asodya_brand.dart';
import 'public_layout.dart';

/// Topics of the Science pages: route id and title key, in menu order.
const List<(String id, String titleKey)> scienceTopics = [
  ('data-engineering', 'pub_topic_de'),
  ('data-science', 'pub_topic_ds'),
  ('machine-learning', 'pub_topic_ml'),
  ('deep-learning', 'pub_topic_dl'),
  ('statistics', 'pub_topic_st'),
];

/// Data of the public pages from the API: the projects of the catalog and the company block.
class PublicData {
  final List<ProjectSummary> projects;
  final SiteInfo site;

  /// True when the project catalog could not be loaded.
  final bool projectsFailed;

  const PublicData({
    this.projects = const [],
    this.site = SiteInfo.asodya,
    this.projectsFailed = false,
  });
}

/// Frame of a public page: loads the projects and the company block once per language,
/// then shows the sections of the page and the footer in one scroll view.
class PublicPage extends StatefulWidget {
  final List<Widget> Function(BuildContext context, PublicData data) sections;

  const PublicPage({super.key, required this.sections});

  @override
  State<PublicPage> createState() => _PublicPageState();
}

class _PublicPageState extends State<PublicPage> {
  Future<PublicData>? _future;
  String? _lang;

  void _load(String lang) {
    if (lang == _lang) return;
    _lang = lang;
    final service = CatalogService.instance;
    // A page still shows its texts and the company block when the catalog call fails.
    _future = service
        .projects(lang: lang)
        .then((p) => PublicData(projects: p.items))
        .catchError((Object _) => const PublicData(projectsFailed: true));
  }

  @override
  Widget build(BuildContext context) {
    _load(context.langCode);
    return FutureBuilder<PublicData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        return SingleChildScrollView(
          key: const Key('public_scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...widget.sections(context, data),
              PublicFooter(data: data),
            ],
          ),
        );
      },
    );
  }
}

/// Footer with link columns (Company, Projects, Science, Developers, Contact) and a bottom line.
/// The project links and the company data come from the API.
class PublicFooter extends StatelessWidget {
  final PublicData data;

  const PublicFooter({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final site = data.site;
    final company = site.companyName ?? context.tr('pub_company_fallback');
    Widget column(String key, String title, List<Widget> links) => Column(
      key: Key('footer_$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...links,
      ],
    );
    final columns = [
      column('company', context.tr('pub_footer_company'), [
        _FooterLink(
          context.tr('pub_nav_overview'),
          () => context.go(AppRoutes.home),
        ),
        if (site.websiteUrl != null)
          _FooterLink(
            company,
            () => openPublicLink(site.websiteUrl!),
            external: true,
          ),
        _FooterLink(
          context.tr('pub_nav_reports'),
          () => context.go(AppRoutes.menu),
        ),
      ]),
      column('projects', context.tr('pub_nav_projects'), [
        for (final pr in data.projects)
          _FooterLink(
            pr.name,
            pr.websiteUrl == null
                ? () => context.go(AppRoutes.homeProjects)
                : () => openPublicLink(pr.websiteUrl!),
            external: pr.websiteUrl != null,
          ),
        _FooterLink(
          context.tr('pub_footer_all_projects'),
          () => context.go(AppRoutes.homeProjects),
        ),
      ]),
      column('science', context.tr('pub_nav_science'), [
        for (final (id, titleKey) in scienceTopics)
          _FooterLink(
            context.tr(titleKey),
            () => context.go(AppRoutes.scienceTopic(id)),
          ),
      ]),
      column('developers', context.tr('pub_footer_developers'), [
        _FooterLink(
          context.tr('pub_nav_architecture'),
          () => context.go(AppRoutes.homeArchitecture),
        ),
        _FooterLink(
          context.tr('pub_api_docs'),
          () => openPublicLink(engineUrl(apiDocsPath)),
          external: true,
        ),
        _FooterLink(
          context.tr('pub_api_openapi'),
          () => openPublicLink(engineUrl(openApiPath)),
          external: true,
        ),
      ]),
      column('contact', context.tr('pub_nav_contact'), [
        _FooterLink(
          context.tr('pub_footer_contact_page'),
          () => context.go(AppRoutes.homeContact),
        ),
        if (site.email != null)
          _FooterLink(
            site.email!,
            () => openPublicLink('mailto:${site.email}'),
          ),
        if (site.phone != null)
          _FooterLink(
            site.phone!,
            () => openPublicLink(
              'tel:${site.phone!.replaceAll(RegExp(r'[^0-9+]'), '')}',
            ),
          ),
        for (final s in site.social)
          _FooterLink(
            socialName(s.network),
            () => openPublicLink(s.url),
            external: true,
          ),
      ]),
    ];
    final width = PublicLayout.width(context);
    final cols = width < PublicLayout.md
        ? 1
        : (width < PublicLayout.lg ? 2 : columns.length);
    return Container(
      key: const Key('public_footer'),
      color: p.surface,
      padding: EdgeInsets.symmetric(
        horizontal: PublicLayout.gutter(context),
        vertical: 48,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PublicLayout.maxContent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AsodyaBrand(logoSize: 34),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - (cols - 1) * 24) / cols;
                  return Wrap(
                    spacing: 24,
                    runSpacing: 32,
                    children: [
                      for (final col in columns) SizedBox(width: w, child: col),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              Divider(height: 1, color: p.border),
              const SizedBox(height: 20),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text(
                    '© ${DateTime.now().year} $company',
                    style: TextStyle(fontSize: 12.5, color: p.textMuted),
                  ),
                  if (site.companyTagline != null)
                    Text(
                      site.companyTagline!,
                      style: TextStyle(fontSize: 12.5, color: p.textMuted),
                    ),
                  if (buildTimestamp.isNotEmpty)
                    Text(
                      buildTimestamp,
                      key: const Key('public_deploy_stamp'),
                      style: TextStyle(fontSize: 12.5, color: p.textMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Display name of a social network.
String socialName(String network) => switch (network) {
  'facebook' => 'Facebook',
  'linkedin' => 'LinkedIn',
  'youtube' => 'YouTube',
  'line' => 'LINE',
  'discord' => 'Discord',
  'slack' => 'Slack',
  'telegram' => 'Telegram',
  'x' => 'X',
  'instagram' => 'Instagram',
  'github' => 'GitHub',
  _ => network,
};

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool external;

  const _FooterLink(this.label, this.onTap, {this.external = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
              ),
              if (external) ...[
                const SizedBox(width: 6),
                Icon(Icons.open_in_new_rounded, size: 13, color: p.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
