import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../services/catalog_service.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_registry.dart';
import '../brand/brand_mark.dart';
import '../charts/format.dart';
import 'mini_charts.dart';

/// Landing tile of one project (IBM Carbon base tile: flat, no border, no shadow, a brand
/// band on top). Every text, link, logo, color and number comes from the API.
/// With [height] (carousel) the middle part scrolls and the buttons stay at the bottom.
class ProjectTile extends StatelessWidget {
  final ProjectSummary project;
  final ProjectStats? stats;
  final VoidCallback onOpen;
  final double? height;

  const ProjectTile({
    super.key,
    required this.project,
    required this.stats,
    required this.onOpen,
    this.height,
  });

  /// Host name of a website link, without "www.".
  static String domainOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  Widget build(BuildContext context) {
    // The tile uses the theme of its project (colors from the catalog API).
    return Theme(
      data: ThemeRegistry.theme(project.slug, Theme.of(context).brightness),
      child: Builder(builder: _tile),
    );
  }

  Widget _tile(BuildContext context) {
    final p = context.palette;
    final s = stats;
    final website =
        project.websiteUrl == null || project.websiteUrl!.trim().isEmpty
        ? null
        : project.websiteUrl!.trim();
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProjectLogo(project: project),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  if (website != null)
                    Text(
                      domainOf(website),
                      key: Key('domain_${project.slug}'),
                      style: TextStyle(fontSize: 12.5, color: p.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (project.tagline.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            project.tagline,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w300,
              color: p.textPrimary,
              height: 1.35,
            ),
          ),
        ],
        if (project.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            project.description,
            style: TextStyle(fontSize: 13.5, color: p.textMuted, height: 1.5),
          ),
        ],
      ],
    );
    final numbers = LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 420 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 1) / cols;
        Widget number(String key, String value, String label) => Container(
          key: Key('tile_${key}_${project.slug}'),
          width: w,
          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: p.textMuted),
              ),
            ],
          ),
        );
        return Wrap(
          spacing: 1,
          runSpacing: 4,
          children: [
            number(
              'reports',
              numberText(s?.reports ?? project.reportCount, 0),
              context.tr('stat_reports'),
            ),
            number(
              'charts',
              numberText(s?.charts ?? 0, 0),
              context.tr('stat_charts'),
            ),
            number(
              'rows',
              compactNumber(s?.rows ?? 0),
              context.tr('stat_rows'),
            ),
            number(
              'stored',
              bytesText(s?.bytes ?? 0),
              context.tr('stat_stored'),
            ),
          ],
        );
      },
    );
    // Phones keep the tile simple: texts, numbers and buttons, no mini charts.
    final phone = MediaQuery.sizeOf(context).width < 600;
    final charts = s == null || s.reports == 0 || phone
        ? const SizedBox.shrink()
        : LayoutBuilder(
            builder: (context, c) {
              final parts = [
                MiniChartFrame(
                  title: context.tr('rows_by_report'),
                  child: MiniBars(
                    items: s.rowsByReport,
                    format: (v) => compactNumber(v),
                    moreLabel: context.tr('more_reports', {
                      'n': '${s.rowsByReport.length - 4}',
                    }),
                  ),
                ),
                MiniChartFrame(
                  title: context.tr('charts_per_report'),
                  child: MiniBars(
                    items: s.chartsByReport,
                    format: (v) => '$v',
                    moreLabel: context.tr('more_reports', {
                      'n': '${s.chartsByReport.length - 4}',
                    }),
                    slot: 2,
                  ),
                ),
                MiniChartFrame(
                  title: context.tr('rows_per_day'),
                  child: Sparkline(
                    slot: 3,
                    days: s.rowsByDay,
                    tooltip: s.rowsByDay.isEmpty
                        ? ''
                        : '${context.tr('date_range', {'start': s.rowsByDay.first.date, 'end': s.rowsByDay.last.date})}: ${numberText(s.rowsByDay.fold<int>(0, (a, d) => a + d.rows), 0)}',
                  ),
                ),
              ];
              // Two bar lists side by side when they fit, the day line below them.
              if (c.maxWidth >= 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: parts[0]),
                        const SizedBox(width: 24),
                        Expanded(child: parts[1]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    parts[2],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    parts[i],
                  ],
                ],
              );
            },
          );
    final hasReports = project.reportCount > 0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
    );
    final buttons = Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        track(
          'catalog.project.reports',
          FilledButton.icon(
            key: Key('open_reports_${project.slug}'),
            onPressed: hasReports ? onOpen : null,
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              shape: shape,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(context.tr(hasReports ? 'open_reports' : 'no_reports')),
          ),
        ),
        Tooltip(
          message: website ?? context.tr('no_website'),
          child: track(
            'catalog.project.website',
            OutlinedButton.icon(
              key: Key('website_${project.slug}'),
              onPressed: website == null
                  ? null
                  : () => launchUrl(
                      Uri.parse(website),
                      webOnlyWindowName: '_blank',
                    ),
              // Text color, not the accent: a light accent has no contrast on a light tile.
              style: OutlinedButton.styleFrom(
                shape: shape,
                foregroundColor: p.textPrimary,
                side: BorderSide(
                  color: website == null
                      ? p.border.withValues(alpha: 0.5)
                      : p.textMuted,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(context.tr('website')),
            ),
          ),
        ),
      ],
    );
    final band = Container(height: 4, color: p.accent);
    return LayoutBuilder(
      builder: (context, c) {
        // A wide list tile puts the texts on the left and the numbers on the right.
        final split = height == null && c.maxWidth >= 920;
        final Widget content;
        if (split) {
          content = Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [head, const SizedBox(height: 24), buttons],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [numbers, const SizedBox(height: 20), charts],
                  ),
                ),
              ],
            ),
          );
        } else {
          final middle = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              const SizedBox(height: 20),
              numbers,
              const SizedBox(height: 20),
              charts,
            ],
          );
          content = Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: height == null
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              children: [
                if (height == null)
                  middle
                else
                  Expanded(child: SingleChildScrollView(child: middle)),
                const SizedBox(height: 20),
                buttons,
              ],
            ),
          );
        }
        return Container(
          key: Key('project_tile_${project.slug}'),
          height: height,
          color: p.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              band,
              if (height == null) content else Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

/// Wide logo of a project (dark variant in dark mode), or its brand mark.
class _ProjectLogo extends StatelessWidget {
  final ProjectSummary project;

  const _ProjectLogo({required this.project});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final logo =
        (dark ? project.assets['logo_dark'] : null) ?? project.assets['logo'];
    if (logo == null) return BrandMark(project: project.slug, size: 44);
    // The API gives the logo size, so the tile keeps its layout while the image loads.
    final width = logo.height <= 0
        ? 44.0
        : (44 * logo.width / logo.height).clamp(24.0, 160.0);
    return SizedBox(
      width: width,
      height: 44,
      child: Image.network(
        CatalogService.instance.assetUrl(logo.url),
        fit: BoxFit.contain,
        semanticLabel: project.name,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => BrandMark(project: project.slug, size: 44),
      ),
    );
  }
}
