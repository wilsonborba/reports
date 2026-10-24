import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reports_ui/models/catalog.dart';
import 'package:reports_ui/themes/catalog_brands.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'support/fake_api.dart';

void main() {
  tearDown(() => CatalogBrands.instance.clear());

  group('ThemeRegistry (colors from the catalog API)', () {
    test('screens outside a project use the monochrome Reports theme', () {
      final dark = ThemeRegistry.palette(null, Brightness.dark);
      final light = ThemeRegistry.palette(null, Brightness.light);
      expect(dark.accent, const Color(0xFFFFFFFF));
      expect(light.accent, const Color(0xFF111111));
      expect(dark.positive, isNot(dark.negative));
    });

    test('a project uses its API tokens, and the fallback until they arrive', () {
      expect(ThemeRegistry.palette('cortex', Brightness.light).accent, const Color(0xFF111111), reason: 'fallback before the catalog');
      CatalogBrands.instance.update([ProjectSummary.fromJson(FakeApi.cortexProject())]);
      final p = ThemeRegistry.palette('cortex', Brightness.light);
      expect(p.accent, const Color(0xFFF9DF4E));
      expect(p.series.length, 8);
      expect(p.series.first, const Color(0xFFC9A800));
      expect(p.other, const Color(0xFFA8A8A8));
      expect(ThemeRegistry.palette('cortex', Brightness.dark).accent, const Color(0xFFFFFFFF), reason: 'no dark tokens: fallback');
      final theme = ThemeRegistry.theme('cortex', Brightness.light);
      expect(theme.extension<ReportPalette>()!.canvas, const Color(0xFFFFFFFF));
    });

    test('invalid tokens fall back instead of breaking the screen', () {
      final bad = FakeApi.cortexProject();
      (bad['theme']['light'] as Map)['accent'] = 'yellow';
      CatalogBrands.instance.update([ProjectSummary.fromJson(bad)]);
      expect(ThemeRegistry.palette('cortex', Brightness.light).accent, const Color(0xFF111111));
    });

    test('series slots never cycle: slot 9 and later use the Other gray', () {
      final p = ReportPalette.fromTokens(FakeApi.cortexProject()['theme']['light'] as Map<String, dynamic>)!;
      expect(p.seriesAt(7), const Color(0xFFe34948));
      expect(p.seriesAt(8), p.other);
      expect(p.seriesAt(20), p.other);
    });
  });

  group('ThemeController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('toggles and persists the mode', () async {
      final c = ThemeController();
      expect(c.isDark, isTrue);
      await c.toggle();
      expect(c.isDark, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'light');
      final restored = ThemeController();
      await restored.load();
      expect(restored.isDark, isFalse);
    });
  });
}
