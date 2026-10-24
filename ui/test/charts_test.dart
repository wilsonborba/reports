import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/models/catalog.dart';
import 'package:reports_ui/themes/catalog_brands.dart';
import 'support/fake_api.dart';
import 'package:reports_ui/widgets/charts/bar_charts.dart';
import 'package:reports_ui/widgets/charts/data_table_view.dart';
import 'package:reports_ui/widgets/charts/donut_chart.dart';
import 'package:reports_ui/widgets/charts/format.dart';
import 'package:reports_ui/widgets/charts/kpi_tiles.dart';
import 'package:reports_ui/widgets/charts/line_charts.dart';
import 'package:reports_ui/widgets/charts/map_chart.dart';
import 'package:reports_ui/widgets/charts/visual_chooser.dart';
import 'package:reports_ui/widgets/charts/series_colors.dart';
import 'package:reports_ui/widgets/charts/chart_parts.dart';

FieldInfo f(String name, String type, {bool dim = false, String? unit, int? decimals}) =>
    FieldInfo(name: name, label: name.toUpperCase(), type: type, role: dim ? 'dimension' : 'measure', unit: unit, decimals: decimals);

DatasetPage page(List<FieldInfo> fields, List<Map<String, dynamic>> rows) => DatasetPage(
      descriptor: DatasetDescriptor(datasetId: 'd', title: 'D', description: '', equation: null, fields: fields, filters: const []),
      rows: rows,
      offset: 0,
      limit: rows.length,
      totalRows: rows.length,
    );

final kpiPage = page([f('total', 'integer'), f('share', 'percent')], [
  {'total': 12345, 'share': 45.7}
]);
final trendPage = page([f('day', 'date', dim: true), f('volume', 'integer'), f('cars', 'integer'), f('pct', 'percent')], [
  for (var i = 1; i <= 9; i++) {'day': '2026-10-0$i', 'volume': 100 * i, 'cars': 40 * i, 'pct': 10.0 + i}
]);
final stackedPage = page([f('hour', 'hour', dim: true), f('task', 'string', dim: true), f('rpm', 'float')], [
  for (var h = 0; h < 6; h++)
    for (final c in ['chat', 'embed']) {'hour': h, 'task': c, 'rpm': h * 10.0 + (c == 'chat' ? 5 : 1)}
]);
final categoryPage = page([f('provider', 'string', dim: true), f('volume', 'integer', unit: 'tokens'), f('share', 'percent')], [
  for (var i = 0; i < 4; i++) {'provider': 'Provider $i', 'volume': 1000 - i * 100, 'share': 25.0}
]);
final rankingPage = page([f('provider', 'string', dim: true), f('volume', 'integer'), f('share', 'percent')], [
  for (var i = 0; i < 20; i++) {'provider': 'Provider $i', 'volume': 2000 - i * 50, 'share': 5.0}
]);
final curvePage = page([f('density', 'float', dim: true), f('greenshields', 'float'), f('underwood', 'float')], [
  for (var i = 0; i < 20; i++) {'density': i * 5.0, 'greenshields': i * 3.0, 'underwood': i * 2.5}
]);
final mapPage = page([f('provider', 'string', dim: true), f('lat', 'latitude'), f('lon', 'longitude'), f('volume', 'integer'), f('share', 'percent')], [
  for (var i = 0; i < 12; i++) {'provider': 'Provider $i', 'lat': 13.7 + i * 0.01, 'lon': 100.5 + (i % 4) * 0.01, 'volume': 5000 - i * 300, 'share': 8.0}
]);
final linksPage = page([f('from_lat', 'latitude'), f('from_lon', 'longitude'), f('to_lat', 'latitude'), f('to_lon', 'longitude')], [
  {'from_lat': 13.7, 'from_lon': 100.5, 'to_lat': 13.71, 'to_lon': 100.51},
]);
final widePage = page([f('model', 'string', dim: true), for (var i = 0; i < 9; i++) f('metric_$i', 'float', unit: 'ms')], [
  for (var r = 0; r < 30; r++) {'model': 'Model $r', for (var i = 0; i < 9; i++) 'metric_$i': r * 1.5 + i}
]);

Future<void> pumpChart(WidgetTester tester, Widget child, {double width = 1100, ThemeData? theme}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? ThemeRegistry.theme(null, Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
  ));
  await tester.pumpAndSettle();
}

void main() {

  group('format', () {
    test('numbers, units and hours', () {
      expect(numberText(1234567.891, 2), '1,234,567.89');
      expect(numberText(-1000, 0), '-1,000');
      expect(compactNumber(12500), '13k');
      expect(compactNumber(2300000), '2.3M');
      expect(valueText(7, f('h', 'hour')), '07:00');
      expect(valueText(45.678, f('p', 'percent')), '45.7%');
      expect(valueWithUnit(1200, f('v', 'integer', unit: 'tokens')), '1,200 tokens');
      expect(labelWithUnit(f('v', 'integer', unit: 'tokens')), 'V (tokens)');
    });
  });

  group('automatic visual', () {
    test('picks the chart from field types and roles', () {
      expect(VisualChooser.auto(kpiPage), Visual.kpi);
      expect(VisualChooser.auto(trendPage), Visual.line);
      expect(VisualChooser.auto(stackedPage), Visual.stackedBar);
      expect(VisualChooser.auto(categoryPage), Visual.donut);
      expect(VisualChooser.auto(rankingPage), Visual.hbar);
      expect(VisualChooser.auto(curvePage), Visual.curve);
      expect(VisualChooser.auto(mapPage), Visual.map);
      expect(VisualChooser.auto(widePage), Visual.table);
      expect(VisualChooser.auto(page([f('a', 'string', dim: true)], const [])), Visual.table);
    });

    test('measures of one type and unit share an axis; percent is left out', () {
      final ms = VisualChooser.slotMeasures(trendPage.descriptor, const Slot('d'));
      expect(ms.map((m) => m.name), ['volume', 'cars']);
      final forced = VisualChooser.slotMeasures(trendPage.descriptor, const Slot('d', measures: ['pct', 'missing']));
      expect(forced.map((m) => m.name), ['pct']);
    });
  });

  group('charts render without layout errors', () {
    final cases = <String, (DatasetPage, Slot, Type)>{
      'kpi': (kpiPage, const Slot('d'), KpiTiles),
      'line': (trendPage, const Slot('d'), SeriesLineChart),
      'bar': (trendPage, const Slot('d', visual: Visual.bar), VerticalBarChart),
      'combo': (trendPage, const Slot('d', visual: Visual.combo, measures: ['volume', 'pct']), AlignedCharts),
      'stacked': (stackedPage, const Slot('d'), StackedBarChart),
      'donut': (categoryPage, const Slot('d'), DonutChart),
      'ranking': (rankingPage, const Slot('d'), RankingBars),
      'curve': (curvePage, const Slot('d'), SeriesLineChart),
      'map': (mapPage, const Slot('d', companions: ['links']), SpatialMap),
      'table': (widePage, const Slot('d'), DataTableView),
      'forced visual that does not fit': (kpiPage, const Slot('d', visual: Visual.stackedBar), DataTableView),
    };
    for (final width in [1100.0, 360.0]) {
      cases.forEach((name, c) {
        testWidgets('$name at ${width.toInt()} px', (tester) async {
          await pumpChart(tester, VisualChooser.build(c.$1, c.$2, companions: {'links': linksPage}), width: width);
          expect(find.byType(c.$3), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  testWidgets('donut shows each category with its share', (tester) async {
    await pumpChart(tester, VisualChooser.build(categoryPage, const Slot('d')));
    expect(find.text('Provider 0'), findsOneWidget);
    expect(find.textContaining('25.0%'), findsNWidgets(4));
  });

  testWidgets('map lists the top places next to the map on wide cards', (tester) async {
    await pumpChart(tester, VisualChooser.build(mapPage, const Slot('d')));
    // The preview limit cuts the list, not the points on the map.
    expect(tester.widget<SpatialMap>(find.byType(SpatialMap)).points.rows.length, 12);
    expect(find.text('Provider 0'), findsOneWidget);
    expect(find.text('Provider 7'), findsOneWidget);
    expect(find.text('Provider 8'), findsNothing);
    final map = tester.getTopLeft(find.byType(CustomPaint).first);
    final list = tester.getTopLeft(find.text('Provider 0'));
    expect(list.dx, greaterThan(map.dx + 300));
  });

  testWidgets('table sorts by a column and scrolls horizontally when wide', (tester) async {
    await pumpChart(tester, VisualChooser.build(widePage, const Slot('d')), width: 500);
    expect(find.text('METRIC_0 (ms)'), findsOneWidget);
    expect(find.text('Model 0'), findsOneWidget);
    await tester.tap(find.text('MODEL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MODEL'));
    await tester.pumpAndSettle();
    // Descending text order puts "Model 9" first.
    final first = tester.getTopLeft(find.text('Model 9')).dy;
    expect(first, lessThan(tester.getTopLeft(find.text('Model 8')).dy));
    expect(find.byType(Scrollbar), findsOneWidget);
  });
  testWidgets('a category keeps one color in every chart of a report; a 9th folds into Other', (tester) async {
    // The report view lists the class options; that order fixes the colors.
    final view = ReportView(project: 'p', report: 'r', title: '', description: '', tags: const [], period: null, updatedAt: '', datasets: [
      DatasetDescriptor(datasetId: 'd', title: 'D', description: '', equation: null, fields: const [], filters: [
        FilterInfo(field: 'task', label: 'Task', type: 'category', options: [
          for (final c in ['embed', 'chat', 'vision', 'C0', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8']) FilterOption(c, c),
        ]),
      ]),
    ]);
    final map = SeriesColorMap()..registerReport(view);
    CatalogBrands.instance.update([ProjectSummary.fromJson(FakeApi.cortexProject())]);
    addTearDown(CatalogBrands.instance.clear);
    final reversed = page(stackedA.descriptor.fields, stackedA.rows.reversed.toList());
    await pumpChart(tester, theme: ThemeRegistry.theme('cortex', Brightness.light), SeriesColorScope(map: map, child: Column(children: [
      VisualChooser.build(stackedA, const Slot('a')),
      VisualChooser.build(reversed, const Slot('a2')),
      VisualChooser.build(stackedNine, const Slot('b')),
    ])));
    final legends = tester.widgetList<Legend>(find.byType(Legend)).toList();
    Color colorOf(Legend l, String name) => l.entries!.firstWhere((e) => e.label == name).color;
    for (final c in ['embed', 'chat', 'vision']) {
      expect(colorOf(legends[0], c), colorOf(legends[1], c), reason: '$c keeps its color in another chart and order');
    }
    expect(colorOf(legends[0], 'embed'), const Color(0xFFC9A800), reason: 'first option, first slot');
    expect(legends[2].entries!.last.label, 'Other');
    expect(colorOf(legends[2], 'Other'), const Color(0xFFA8A8A8));
    expect(legends[2].entries!.length, 5, reason: 'C0 to C3 are within the first 7 slots; C4 to C8 fold into Other');
  });

}

final stackedA = page([f('hour', 'hour', dim: true), f('task', 'string', dim: true), f('rpm', 'float')], [
  for (var h = 0; h < 3; h++)
    for (final c in ['chat', 'embed', 'vision']) {'hour': h, 'task': c, 'rpm': (c == 'embed' ? 50 : 10) + h * 1.0}
]);
final stackedNine = page([f('hour', 'hour', dim: true), f('task', 'string', dim: true), f('rpm', 'float')], [
  for (var h = 0; h < 2; h++)
    for (var c = 0; c < 9; c++) {'hour': h, 'task': 'C$c', 'rpm': 100.0 - c * 10}
]);
