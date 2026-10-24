import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/report/section_pills.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(
        theme: ThemeRegistry.theme(null, Brightness.light),
        home: Scaffold(body: Center(child: child)),
      ));

  testWidgets('sections are flat tabs: a thick project-color line under the selected tab only', (tester) async {
    await pump(tester, SectionPills(count: 3, selected: 1, onSelect: (_) {}));
    BorderSide bottom(int i) =>
        ((tester.widget<AnimatedContainer>(find.byKey(Key('section_tab_$i'))).decoration! as BoxDecoration).border! as Border).bottom;
    final p = ThemeRegistry.palette(null, Brightness.light);
    expect(bottom(1).width, 3);
    expect(bottom(1).color, p.accent);
    expect(bottom(0).width, 1);
    expect(bottom(2).color, p.border);
    final decoration = tester.widget<AnimatedContainer>(find.byKey(const Key('section_tab_1'))).decoration! as BoxDecoration;
    expect(decoration.borderRadius, isNull, reason: 'tabs have square corners');
  });

  testWidgets('buttons and menus use the flat control and surface corners', (tester) async {
    final theme = ThemeRegistry.theme('cortex', Brightness.dark);
    final shape = theme.filledButtonTheme.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(ReportPalette.controlRadius));
    final menu = theme.menuTheme.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(menu.borderRadius, BorderRadius.circular(ReportPalette.surfaceRadius));
  });
}
