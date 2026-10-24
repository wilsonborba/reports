/// The Asodya company block of the public site. These are the community group links of
/// asodya.com (domain/lib/presentation/widgets/landing/on_landing.dart); they are brand
/// facts, not project data, so they live here and not in the engine.
library;

/// Community or social link of the company.
class SocialLink {
  /// discord, slack, telegram or line
  final String network;
  final String url;

  const SocialLink(this.network, this.url);
}

class SiteInfo {
  final String? companyName;
  final String? companyTagline;
  final String? about;
  final String? address;
  final String? phone;

  /// Plain email address; links add `mailto:`.
  final String? email;
  final String? websiteUrl;
  final String? contactUrl;
  final List<SocialLink> social;

  const SiteInfo({
    this.companyName,
    this.companyTagline,
    this.about,
    this.address,
    this.phone,
    this.email,
    this.websiteUrl,
    this.contactUrl,
    this.social = const [],
  });

  /// Asodya and its community groups.
  static const SiteInfo asodya = SiteInfo(
    companyName: 'Asodya',
    websiteUrl: 'https://asodya.com',
    social: [
      SocialLink('discord', 'https://discord.gg/asodya'),
      SocialLink('slack', 'https://join.slack.com/t/asodya/shared_invite/zt-2026-asodya'),
      SocialLink('telegram', 'https://t.me/+lGee9j-d2iplZTg0'),
      SocialLink('line', 'https://line.me/R/ti/p/@579lhloi'),
    ],
  );

  bool get isEmpty =>
      companyName == null && address == null && phone == null && email == null && websiteUrl == null && contactUrl == null && social.isEmpty;
}
