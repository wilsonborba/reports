import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../models/site.dart';
import '../../themes/report_palette.dart';
import '../../widgets/catalog/catalog_widgets.dart';
import '../../widgets/landing/project_tile.dart';
import '../../widgets/public/project_logo.dart';
import '../../widgets/public/public_blocks.dart';
import '../../widgets/public/public_layout.dart';
import '../../widgets/public/public_motion.dart';
import '../../widgets/public/public_page.dart';

/// Contact page (/v1/home/contact): the Asodya community groups, and the website and
/// repository of every project (GET /catalog). A missing value hides its row.
class ContactView extends StatelessWidget {
  const ContactView({super.key});

  /// `tel:` link of a phone number (digits and the plus sign only).
  static String telLink(String phone) => 'tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}';

  @override
  Widget build(BuildContext context) {
    return PublicPage(sections: (context, data) {
      final p = context.palette;
      final site = data.site;
      return [
        PublicHero(
          eyebrow: context.tr('pub_nav_contact'),
          title: context.tr('pub_contact_title'),
          lead: context.tr('pub_contact_lead'),
          actions: [
            for (final (i, s) in site.social.indexed)
              PublicButton(
                key: Key('contact_group_${s.network}'),
                label: socialName(s.network),
                primary: i == 0,
                icon: Icons.forum_outlined,
                onPressed: () => openPublicLink(s.url),
              ),
          ],
        ),
        PublicSection(
          topBorder: true,
          child: site.isEmpty
              ? StateMessage(icon: Icons.contact_mail_outlined, title: context.tr('pub_contact_none'))
              : SplitBlock(
                  text: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Eyebrow(context.tr('pub_footer_company')),
                    const SizedBox(height: 12),
                    Text(site.companyName ?? context.tr('pub_company_fallback'),
                        key: const Key('contact_company_name'),
                        style: TextStyle(fontSize: PublicLayout.isPhone(context) ? 26 : 32, fontWeight: FontWeight.w300, color: p.textPrimary, height: 1.25)),
                    if (site.companyTagline != null) ...[
                      const SizedBox(height: 8),
                      Text(site.companyTagline!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: p.textPrimary)),
                    ],
                    if (site.about != null) ...[
                      const SizedBox(height: 16),
                      Text(site.about!, style: TextStyle(fontSize: 15, color: p.textMuted, height: 1.6)),
                    ],
                  ]),
                  visual: Reveal(delay: const Duration(milliseconds: 120), child: _CompanyCard(site: site)),
                ),
        ),
        PublicSection(
          background: p.surface,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeading(title: context.tr('pub_contact_projects_title'), intro: context.tr('pub_contact_projects_intro')),
            if (data.projectsFailed)
              StateMessage(icon: Icons.cloud_off_rounded, title: context.tr('error_loading'))
            else if (data.projects.isEmpty)
              StateMessage(icon: Icons.folder_off_outlined, title: context.tr('no_projects'))
            else
              Reveal(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final pr in data.projects) _ProjectContactRow(project: pr),
                ]),
              ),
          ]),
        ),
      ];
    });
  }
}

/// Company details: address, phone, email, website, contact page and social links.
class _CompanyCard extends StatelessWidget {
  final SiteInfo site;

  const _CompanyCard({required this.site});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String key, IconData icon, String label, Widget value) => Container(
          key: Key('contact_row_$key'),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: p.textPrimary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 13, color: p.textMuted)),
                const SizedBox(height: 4),
                value,
              ]),
            ),
          ]),
        );
    Widget link(String text, String url) => ArrowLink(label: text, onTap: () => openPublicLink(url), icon: Icons.open_in_new_rounded);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (site.address != null)
          row('address', Icons.location_on_outlined, context.tr('pub_contact_address'),
              Text(site.address!, style: TextStyle(fontSize: 15, color: p.textPrimary, height: 1.5))),
        if (site.phone != null)
          row('phone', Icons.call_outlined, context.tr('pub_contact_phone'),
              ArrowLink(label: site.phone!, onTap: () => openPublicLink(ContactView.telLink(site.phone!)), icon: Icons.call_made_rounded)),
        if (site.email != null)
          row('email', Icons.mail_outline_rounded, context.tr('pub_contact_email'),
              ArrowLink(label: site.email!, onTap: () => openPublicLink('mailto:${site.email}'), icon: Icons.call_made_rounded)),
        if (site.websiteUrl != null)
          row('website', Icons.language_rounded, context.tr('website'), link(ProjectTile.domainOf(site.websiteUrl!), site.websiteUrl!)),
        if (site.contactUrl != null)
          row('page', Icons.contact_page_outlined, context.tr('pub_footer_contact_page'),
              link(ProjectTile.domainOf(site.contactUrl!), site.contactUrl!)),
        if (site.social.isNotEmpty)
          row('social', Icons.public_rounded, context.tr('pub_contact_social'),
              Wrap(spacing: 16, children: [for (final s in site.social) link(socialName(s.network), s.url)])),
      ]),
    );
  }
}

/// One project: logo and name, website link and repository link.
class _ProjectContactRow extends StatelessWidget {
  final ProjectSummary project;

  const _ProjectContactRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = project;
    final none = Text(context.tr('pub_fact_none'), style: TextStyle(fontSize: 14, color: p.textMuted));
    final website = pr.websiteUrl == null
        ? none
        : ArrowLink(label: ProjectTile.domainOf(pr.websiteUrl!), onTap: () => openPublicLink(pr.websiteUrl!), icon: Icons.open_in_new_rounded);
    final contact = <Widget>[
      if (pr.repositoryUrl != null && pr.repositoryUrl != pr.websiteUrl)
        ArrowLink(label: ProjectTile.domainOf(pr.repositoryUrl!), onTap: () => openPublicLink(pr.repositoryUrl!), icon: Icons.code_rounded),
    ];
    final name = Row(children: [
      Container(width: 4, height: 32, color: projectAccent(context, pr.slug)),
      const SizedBox(width: 14),
      ProjectLogo(project: pr, height: 28),
      const SizedBox(width: 12),
      Flexible(child: Text(pr.name, style: TextStyle(fontSize: 17, color: p.textPrimary))),
    ]);
    Widget labeled(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          const SizedBox(height: 2),
          child,
        ]);
    final websiteCell = labeled(context.tr('website'), website);
    final contactCell = labeled(context.tr('pub_project_repository'),
        contact.isEmpty ? none : Wrap(spacing: 16, children: contact));
    return Container(
      key: Key('contact_project_${pr.slug}'),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: PublicLayout.isPhone(context)
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [name, const SizedBox(height: 12), websiteCell, const SizedBox(height: 8), contactCell])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 4, child: name),
              const SizedBox(width: 24),
              Expanded(flex: 3, child: websiteCell),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: contactCell),
            ]),
    );
  }
}
