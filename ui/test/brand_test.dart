import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/models/catalog.dart';
import 'package:reports_ui/themes/catalog_brands.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/brand/brand_mark.dart';
import 'support/fake_api.dart';

void main() {
  tearDown(() => CatalogBrands.instance.clear());

  test('the app has no bundled brand files', () {
    expect(ThemeRegistry.mark('cortex', Brightness.light), isNull, reason: 'logos come from the API only');
  });

  test('the logo is the Domain cover, the same in both modes', () {
    CatalogBrands.instance.update([ProjectSummary.fromJson(FakeApi.cortexProject())]);
    expect(ThemeRegistry.mark('cortex', Brightness.dark)!.url, 'https://asodya.com/covers/cortex.png');
    expect(ThemeRegistry.mark('cortex', Brightness.light)!.url, 'https://asodya.com/covers/cortex.png');
  });

  testWidgets('BrandMark shows the API image, or the first letter of the name', (tester) async {
    CatalogBrands.instance.update([ProjectSummary.fromJson(FakeApi.cortexProject())]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeRegistry.theme(null, Brightness.dark),
      home: const Row(children: [BrandMark(project: 'cortex'), BrandMark(project: 'certifications')]),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('C'), findsOneWidget, reason: 'certifications has no image: initial letter');
  });
}
