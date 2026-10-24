import 'package:flutter/material.dart';
import '../../models/catalog.dart';
import '../../services/catalog_service.dart';
import '../../themes/theme_registry.dart';
import '../brand/brand_mark.dart';

/// Wide logo of a project from the catalog API (dark variant in dark mode), or its
/// brand mark when the project has no logo.
class ProjectLogo extends StatelessWidget {
  final ProjectSummary project;
  final double height;

  const ProjectLogo({super.key, required this.project, this.height = 40});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final logo = (dark ? project.assets['logo_dark'] : null) ?? project.assets['logo'];
    if (logo == null) return BrandMark(project: project.slug, size: height);
    // The API gives the logo size, so the layout stays still while the image loads.
    final width = logo.height <= 0 ? height : (height * logo.width / logo.height).clamp(height * 0.6, height * 4);
    return SizedBox(
      width: width,
      height: height,
      child: Image.network(
        CatalogService.instance.assetUrl(logo.url),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        semanticLabel: project.name,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => BrandMark(project: project.slug, size: height),
      ),
    );
  }
}

/// Mark color of a project: the first chart series color of its catalog theme (it keeps
/// its contrast as a line, unlike a light accent). Never used for text.
Color projectAccent(BuildContext context, String slug) =>
    ThemeRegistry.palette(slug, Theme.of(context).brightness).seriesAt(0);
