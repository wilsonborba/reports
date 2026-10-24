import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/charts/chart_parts.dart';
import 'package:reports_ui/widgets/charts/donut_chart.dart';
import 'package:reports_ui/widgets/charts/visual_chooser.dart';
import 'charts_test.dart' show f, page, pumpChart, kpiPage, mapPage, curvePage;

final ninePage = page([f('provider', 'string', dim: true), f('volume', 'integer', unit: 'tokens')], [
  for (var i = 0; i < 9; i++) {'provider': 'Provider $i', 'volume': 900 - i * 100}
]);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  return g;
}

void main() {
  testWidgets('donut: at most 6 segments, the rest fold into Other; the list keeps every row', (tester) async {
    await pumpChart(tester, VisualChooser.build(ninePage, const Slot('d', visual: Visual.donut)));
    final pie = tester.widget<PieChart>(find.byType(PieChart));
    expect(pie.data.sections.length, DonutChart.maxSegments);
    for (var i = 0; i < 9; i++) {
      expect(find.text('Provider $i'), findsOneWidget);
    }
  });

  testWidgets('donut: hovering a list row shows its value and share in the center', (tester) async {
    await pumpChart(tester, VisualChooser.build(ninePage, const Slot('d', visual: Visual.donut)));
    expect(tester.widget<Text>(find.byKey(const Key('donut_center_value'))).data, '4,500');
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('donut_row_1'))));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('donut_center_value'))).data, '800');
    expect(find.text('17.8%'), findsWidgets);
  });

  testWidgets('line: a legend click hides a series and a second click shows it', (tester) async {
    await pumpChart(tester, VisualChooser.build(curvePage, const Slot('d')));
    List<bool> shown() => tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.map((b) => b.show).toList();
    expect(shown(), [true, true]);
    await tester.tap(find.byKey(const Key('legend_underwood')));
    await tester.pumpAndSettle();
    expect(shown(), [true, false]);
    await tester.tap(find.byKey(const Key('legend_underwood')));
    await tester.pumpAndSettle();
    expect(shown(), [true, true]);
    expect(find.byType(Legend), findsOneWidget);
  });

  testWidgets('map: hovering a list row shows the tooltip of its point', (tester) async {
    await pumpChart(tester, VisualChooser.build(mapPage, const Slot('d')));
    expect(find.byKey(const Key('map_tooltip')), findsNothing);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('map_row_2'))));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('map_tooltip')), matching: find.textContaining('Provider 2')), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('map_tooltip')), findsNothing);
  });

  testWidgets('map: a tap on a point shows its tooltip (touch screens)', (tester) async {
    await pumpChart(tester, VisualChooser.build(mapPage, const Slot('d')), width: 360);
    final area = tester.getRect(find.byKey(const Key('map_area')));
    // Scan the map for the first point under a tap.
    for (var y = area.top + 10; y < area.bottom && find.byKey(const Key('map_tooltip')).evaluate().isEmpty; y += 12) {
      for (var x = area.left + 10; x < area.right; x += 12) {
        await tester.tapAt(Offset(x, y));
        await tester.pump();
        if (find.byKey(const Key('map_tooltip')).evaluate().isNotEmpty) break;
      }
    }
    expect(find.byKey(const Key('map_tooltip')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('kpi numbers count up to the exact value', (tester) async {
    await pumpChart(tester, VisualChooser.build(kpiPage, const Slot('d')));
    expect(find.text('12,345'), findsOneWidget);
    expect(find.text('45.7%'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final chart at once', (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeRegistry.theme(null, Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1100, 1600), disableAnimations: true),
        child: Scaffold(body: SingleChildScrollView(child: VisualChooser.build(kpiPage, const Slot('d')))),
      ),
    ));
    await tester.pump();
    expect(find.text('12,345'), findsOneWidget);
  });
}
