import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/catalog_service.dart';
import '../../themes/report_palette.dart';

/// Breakpoints and spacing of the public site (IBM Carbon grid: md 672, lg 1056, max 1584).
class PublicLayout {
  static const double md = 672;
  static const double lg = 1056;

  /// Widest content column; wider screens keep side margins.
  static const double maxContent = 1312;

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isPhone(BuildContext context) => width(context) < md;

  static bool isWide(BuildContext context) => width(context) >= lg;

  /// Side margin of a section: 16 on phones, 32 on tablets, 48 on desktops.
  static double gutter(BuildContext context) {
    final w = width(context);
    return w < md ? 16 : (w < lg ? 32 : 48);
  }
}

/// Color of a card inside the current band: the surface color, or the canvas color when
/// the band itself uses the surface color (the card then still stands out).
Color publicCardColor(BuildContext context) {
  final p = context.palette;
  final band = context.dependOnInheritedWidgetOfExactType<_Band>()?.color;
  return band == p.surface ? p.canvas : p.surface;
}

class _Band extends InheritedWidget {
  final Color color;

  const _Band({required this.color, required super.child});

  @override
  bool updateShouldNotify(_Band old) => old.color != color;
}

/// Opens a link of the public site: web pages in a new tab, mail and phone links in place.
Future<void> openPublicLink(String url) async {
  final uri = Uri.parse(url);
  final external = uri.scheme == 'http' || uri.scheme == 'https';
  await launchUrl(uri, webOnlyWindowName: external ? '_blank' : '_self');
}

/// OpenAPI file of the engine (public).
const String openApiPath = '/openapi.json';

/// Absolute URL of an engine path (API docs, OpenAPI file): same origin as the app.
String engineUrl(String path) => Uri.base.resolve(CatalogService.instance.api.uri(path).toString()).toString();

/// Full-width band of a page with a centered content column.
class PublicSection extends StatelessWidget {
  final Widget child;

  /// Band color; null uses the page canvas.
  final Color? background;

  /// Thin line on top of the band.
  final bool topBorder;
  final double? vertical;

  /// Soft brand glow behind the content (hero bands only): accent at the top right,
  /// highlight at the bottom left.
  final bool glow;

  const PublicSection({super.key, required this.child, this.background, this.topBorder = false, this.vertical, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = PublicLayout.isPhone(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget content = Padding(
      padding: EdgeInsets.symmetric(horizontal: PublicLayout.gutter(context), vertical: vertical ?? (phone ? 40 : 72)),
      // The content column always takes the full width up to the maximum, so short blocks stay left.
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PublicLayout.maxContent),
          child: SizedBox(width: double.infinity, child: _Band(color: background ?? p.canvas, child: child)),
        ),
      ),
    );
    if (glow) {
      RadialGradient blob(Alignment at, Color color, double alpha) =>
          RadialGradient(center: at, radius: 1.1, colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]);
      content = DecoratedBox(
        decoration: BoxDecoration(gradient: blob(const Alignment(0.9, -0.8), p.accent, dark ? 0.20 : 0.12)),
        child: DecoratedBox(decoration: BoxDecoration(gradient: blob(const Alignment(-0.9, 0.9), p.highlight, dark ? 0.10 : 0.08)), child: content),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background ?? p.canvas,
        border: topBorder ? Border(top: BorderSide(color: p.border)) : null,
      ),
      child: content,
    );
  }
}
