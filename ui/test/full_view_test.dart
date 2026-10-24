import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/widgets/charts/visual_chooser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

final requests = <Map<String, String>>[];

/// Report "big" with a ranking dataset of [rows] providers and a small trend dataset.
FakeApi _api(int rows) {
  final api = FakeApi();
  final ranking = {
    'dataset_id': 'providers',
    'title': 'Provider Ranking',
    'description': 'Tokens per provider',
    'equation': null,
    'fields': [
      {'name': 'provider', 'label': 'Provider', 'type': 'string', 'role': 'dimension'},
      {'name': 'volume', 'label': 'Volume', 'type': 'integer', 'role': 'measure'},
    ],
    'filters': [
      {'field': 'kind', 'label': 'Kind', 'type': 'category', 'options': [
        {'value': 'a', 'label': 'Kind A'}, {'value': 'b', 'label': 'Kind B'}]},
    ],
  };
  api.routes['/projects/cortex/reports/big'] = (q) => {
        'project': 'cortex', 'report': 'big', 'title': 'Big Report', 'description': '', 'tags': [],
        'period': null, 'updated_at': '', 'datasets': [ranking],
      };
  api.routes['/projects/cortex/reports/big/datasets/providers'] = (q) {
    requests.add(Map.of(q));
    final all = [for (var i = 0; i < rows; i++) {'provider': 'Provider ${i + 1}', 'volume': 10000 - i}];
    final offset = int.parse(q['offset'] ?? '0');
    final limit = int.parse(q['limit'] ?? '500');
    return {
      ...ranking,
      'rows': all.skip(offset).take(limit).toList(),
      'offset': offset, 'limit': limit, 'total_rows': all.length, 'applied_filters': {},
    };
  };
  return api;
}

Future<void> _pump(WidgetTester tester, String path, int rows) async {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  requests.clear();
  _api(rows).install();
  await tester.pumpWidget(ReportsApp(initialLocation: path));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the See all rule follows the preview limit of the visual', () {
    DatasetPage page(int n, {int? total}) => DatasetPage(
          descriptor: const DatasetDescriptor(datasetId: 'd', title: 'D', description: '', equation: null, filters: [], fields: [
            FieldInfo(name: 'provider', label: 'Provider', type: 'string', role: 'dimension'),
            FieldInfo(name: 'v', label: 'V', type: 'integer', role: 'measure'),
          ]),
          rows: [for (var i = 0; i < n; i++) {'provider': 'R$i', 'v': i}],
          offset: 0,
          limit: 500,
          totalRows: total ?? n,
        );
    expect(VisualChooser.needsFullView(page(10), const Slot('d')), isFalse);
    expect(VisualChooser.needsFullView(page(11), const Slot('d')), isTrue);
    expect(VisualChooser.needsFullView(page(8), const Slot('d', visual: Visual.table)), isFalse);
    expect(VisualChooser.needsFullView(page(9), const Slot('d', visual: Visual.table)), isTrue);
    expect(VisualChooser.needsFullView(page(5, total: 900), const Slot('d', visual: Visual.table)), isTrue);
    expect(VisualChooser.needsFullView(page(40), const Slot('d', visual: Visual.line)), isFalse);
  });

  testWidgets('a short dataset has no See all button', (tester) async {
    await _pump(tester, '/v1/menu/cortex/big', 6);
    expect(find.text('Provider Ranking'), findsWidgets);
    expect(find.byKey(const Key('card_see_all')), findsNothing);
  });

  testWidgets('See all opens the full view with every row, the filters and the breadcrumb', (tester) async {
    await _pump(tester, '/v1/menu/cortex/big', 1200);
    expect(find.text('Provider 10'), findsOneWidget);
    expect(find.text('Provider 11'), findsNothing);
    expect(find.text('10 of 1,200 rows'), findsOneWidget);

    // A card filter stays active in the full view.
    await tester.tap(find.byKey(const Key('card_filters_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter_kind_a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card_see_all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('full_view_card')), findsOneWidget);
    expect(find.text('1,200 of 1,200 rows'), findsOneWidget);
    // Pages through limit and offset.
    expect(requests.map((q) => q['offset']).toSet(), containsAll(['0', '1000']));
    expect(requests.last['f.kind'], 'a');
    // The breadcrumb ends with the chart title; the report crumb is a link.
    expect(find.text('Big Report'), findsWidgets);
    expect(find.text('Provider Ranking'), findsWidgets);
    final selected = tester.widget<FilterChip>(find.byKey(const Key('filter_kind_a')));
    expect(selected.selected, isTrue);
    // Every row is in the chart.
    await tester.scrollUntilVisible(find.text('Provider 1200'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('Provider 1200'), findsOneWidget);
  });
}
