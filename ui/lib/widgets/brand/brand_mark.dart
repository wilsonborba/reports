import 'package:flutter/material.dart';
import '../../services/catalog_service.dart';
import '../../themes/catalog_brands.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_registry.dart';

/// Square brand mark of a project: the icon (or logo) from the catalog API, or the first
/// letter of the project name while it loads or when the project has no image.
class BrandMark extends StatelessWidget {
  final String? project;
  final double size;

  const BrandMark({super.key, required this.project, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogBrands.instance,
      builder: (context, _) {
        final p = context.palette;
        final asset = ThemeRegistry.mark(project, Theme.of(context).brightness);
        final brand = ThemeRegistry.brandColor(project ?? '', Theme.of(context).brightness);
        if (asset == null) return _initial(p, brand);
        return SizedBox(
          width: size,
          height: size,
          child: Image.network(
            CatalogService.instance.assetUrl(asset.url),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // A plain browser image element: no decode work in the app.
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            semanticLabel: ThemeRegistry.brandTitle(project),
            errorBuilder: (_, _, _) => _initial(p, brand),
          ),
        );
      },
    );
  }

  /// Initial on a tint of the project brand color; the letter keeps the text color.
  Widget _initial(ReportPalette p, Color brand) {
    final name = ThemeRegistry.brandTitle(project);
    return Container(
      key: const Key('brand_initial'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: brand),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: p.textPrimary),
      ),
    );
  }
}
