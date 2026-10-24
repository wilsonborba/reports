import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/widgets/charts/bar_charts.dart';
import 'package:reports_ui/widgets/charts/data_table_view.dart';
import 'package:reports_ui/widgets/charts/visual_chooser.dart';
import 'charts_test.dart' show f, page, pumpChart;

const frame = 500.0;

Widget full(dynamic pg, Slot slot) => VisualChooser.build(pg, slot, full: true, frame: frame);

DatasetPage ranking(int n) => page([f('provider', 'string', dim: true), f('volume', 'integer'), f('share', 'percent')], [
      for (var i = 0; i < n; i++) {'provider': 'Provider $i', 'volume': 10000 - i * 10, 'share': 1.0}
    ]);
DatasetPage days(int n) => page([f('day', 'date', dim: true), f('volume', 'integer')], [
      for (var i = 0; i < n; i++) {'day': DateTime(2026, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'volume': 100 + i}
    ]);
DatasetPage stacked(int cats) => page([f('hour', 'hour', dim: true), f('task', 'string', dim: true), f('rpm', 'float')], [
      for (var h = 0; h < 6; h++)
        for (var c = 0; c < cats; c++) {'hour': h, 'task': 'C$c', 'rpm': 100.0 - c * 5 + h}
    ]);
final table = page([f('model', 'string', dim: true), for (var i = 0; i < 3; i++) f('metric_$i', 'float')], [
  for (var r = 0; r < 120; r++) {'model': 'Model ${r.toString().padLeft(3, '0')}', for (var i = 0; i < 3; i++) 'metric_$i': r + i * 1.0}
]);
final places = page([f('provider', 'string', dim: true), f('lat', 'latitude'), f('lon', 'longitude'), f('volume', 'integer')], [
  for (var i = 0; i < 40; i++) {'provider': 'Provider $i', 'lat': 13.7 + i * 0.01, 'lon': 100.5 + (i % 4) * 0.01, 'volume': 5000 - i * 100}
]);

void main() {
  group('ranking', () {
    testWidgets('up to 25 rows use one column', (tester) async {
      await pumpChart(tester, full(ranking(25), const Slot('d', visual: Visual.hbar)), width: 1300);
      expect(find.byKey(const Key('rank_column_0')), findsOneWidget);
      expect(find.byKey(const Key('rank_column_1')), findsNothing);
    });

    testWidgets('more rows use 2 then 3 columns side by side, with one bar scale', (tester) async {
      await pumpChart(tester, full(ranking(40), const Slot('d', visual: Visual.hbar)), width: 1300);
      expect(find.byKey(const Key('rank_column_1')), findsOneWidget);
      expect(find.byKey(const Key('rank_column_2')), findsNothing);
      await pumpChart(tester, full(ranking(70), const Slot('d', visual: Visual.hbar)), width: 1300);
      expect(find.byKey(const Key('rank_column_2')), findsOneWidget);
      expect(find.text('70'), findsOneWidget, reason: 'the rank continues in the next columns');
      final scales = tester.widgetList<RankingBars>(find.byType(RankingBars)).map((r) => r.maxValue).toSet();
      expect(scales, {10000});
    });

    testWidgets('past 3 columns the frame scrolls and never passes the frame height', (tester) async {
      await pumpChart(tester, full(ranking(150), const Slot('d', visual: Visual.hbar)), width: 1300);
      expect(tester.getSize(find.byKey(const Key('rank_frame'))).height, lessThanOrEqualTo(frame));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow screen keeps one column', (tester) async {
      await pumpChart(tester, full(ranking(70), const Slot('d', visual: Visual.hbar)), width: 360);
      expect(find.byKey(const Key('rank_column_1')), findsNothing);
      expect(tester.getSize(find.byKey(const Key('rank_frame'))).height, lessThanOrEqualTo(frame));
    });
  });

  group('table', () {
    testWidgets('pages of 50 rows inside the frame; sorting covers all rows', (tester) async {
      await pumpChart(tester, full(table, const Slot('d', visual: Visual.table)), width: 1100);
      expect(find.text('Rows 1 to 50 of 120'), findsOneWidget);
      expect(tester.getSize(find.byType(DataTableView)).height, lessThanOrEqualTo(frame));
      await tester.tap(find.byKey(const Key('table_next')));
      await tester.pumpAndSettle();
      expect(find.text('Rows 51 to 100 of 120'), findsOneWidget);
      expect(find.text('Model 050'), findsOneWidget);
      await tester.tap(find.byKey(const Key('table_next')));
      await tester.pumpAndSettle();
      expect(find.text('Rows 101 to 120 of 120'), findsOneWidget);
      // A sort goes back to page 1 and sorts all 120 rows.
      await tester.tap(find.text('MODEL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MODEL'));
      await tester.pumpAndSettle();
      expect(find.text('Rows 1 to 50 of 120'), findsOneWidget);
      expect(find.text('Model 119'), findsOneWidget);
    });
  });

  group('lines and bars over time', () {
    testWidgets('many points scroll with a fixed y axis', (tester) async {
      await pumpChart(tester, full(days(200), const Slot('d', visual: Visual.line)), width: 1100);
      expect(find.byKey(const Key('chart_x_scroll')), findsOneWidget);
      expect(find.byKey(const Key('fixed_y_axis')), findsOneWidget);
      final plot = tester.getSize(find.descendant(of: find.byKey(const Key('chart_x_scroll')), matching: find.byType(SizedBox)).first);
      expect(plot.width, greaterThanOrEqualTo(200 * VisualChooser.fullPointWidth));
      await pumpChart(tester, full(days(200), const Slot('d', visual: Visual.bar)), width: 1100);
      expect(find.byKey(const Key('chart_x_scroll')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('points that fit do not scroll', (tester) async {
      await pumpChart(tester, full(days(60), const Slot('d', visual: Visual.line)), width: 1100);
      expect(find.byKey(const Key('chart_x_scroll')), findsNothing);
    });
  });

  group('stacked bars', () {
    testWidgets('more than 8 categories become small multiples on one scale', (tester) async {
      await pumpChart(tester, full(stacked(10), const Slot('d')), width: 1300);
      expect(find.byKey(const Key('small_multiples')), findsOneWidget);
      expect(find.byType(VerticalBarChart), findsNWidgets(10));
      final ranges = tester.widgetList<VerticalBarChart>(find.byType(VerticalBarChart)).map((c) => (c.range!.min, c.range!.max)).toSet();
      expect(ranges.length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8 or fewer stay one stacked chart', (tester) async {
      await pumpChart(tester, full(stacked(5), const Slot('d')), width: 1300);
      expect(find.byType(StackedBarChart), findsOneWidget);
    });
  });

  testWidgets('donut list scrolls inside the frame', (tester) async {
    await pumpChart(tester, full(ranking(60), const Slot('d', visual: Visual.donut)), width: 1300);
    expect(tester.getSize(find.byKey(const Key('donut_list_frame'))).height, lessThanOrEqualTo(frame));
  });

  testWidgets('map is at most the frame height and the full list scrolls next to it', (tester) async {
    await pumpChart(tester, full(places, const Slot('d', visual: Visual.map)), width: 1600);
    final map = tester.getSize(find.byKey(const Key('map_area')));
    expect(map.height, lessThanOrEqualTo(frame));
    expect(find.text('Provider 39'), findsOneWidget, reason: 'the full view lists every place');
    expect(tester.takeException(), isNull);
  });
}
