import 'package:flutter/material.dart';
import '../models/catalog.dart';
import 'catalog_brands.dart';
import 'report_palette.dart';
import 'reports_theme.dart';

/// Resolves the theme of a project from the catalog API tokens. Screens outside a
/// project, and projects without tokens for the mode, use the Reports theme.
class ThemeRegistry {
  static final Map<String, ReportPalette> _built = {};

  static ReportPalette palette(String? project, Brightness brightness) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';
    final tokens = CatalogBrands.instance.project(project)?.theme[mode];
    if (tokens != null) {
      final key = '$project:$mode:${tokens.hashCode}:${tokens.toString()}';
      final built = _built[key] ??= ReportPalette.fromTokens(tokens) ?? ReportsTheme.palette(brightness);
      return built;
    }
    return ReportsTheme.palette(brightness);
  }

  static ThemeData theme(String? project, Brightness brightness) => palette(project, brightness).toTheme(brightness);

  /// Logo or icon of a project for the mode: the `_dark` role first in dark mode.
  static AssetRef? asset(String? project, String role, Brightness brightness) {
    final assets = CatalogBrands.instance.project(project)?.assets ?? const {};
    return (brightness == Brightness.dark ? assets['${role}_dark'] : null) ?? assets[role];
  }

  /// Square mark: the icon, else the logo.
  static AssetRef? mark(String? project, Brightness brightness) =>
      asset(project, 'icon', brightness) ?? asset(project, 'logo', brightness);

  /// Project name from the catalog (the slug until the catalog answers).
  static String brandTitle(String? project) =>
      CatalogBrands.instance.project(project)?.name ?? project ?? 'Reports';

  // -- Compatibility API for the admin screen (stage two replaces it) ------------------
  static ThemeData getTheme(String? project, {bool isDark = true}) =>
      theme(project, isDark ? Brightness.dark : Brightness.light);

  static Color getPrimaryAccent(String? project, {bool isDark = true}) =>
      palette(project, isDark ? Brightness.dark : Brightness.light).accent;

  static String getBrandTitle(String? project) => brandTitle(project);

  static String getBrandSubtitle(String? project) => '';

  static IconData getBrandIcon(String? project) => Icons.insights_rounded;
}
