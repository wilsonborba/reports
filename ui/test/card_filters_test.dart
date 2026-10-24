import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/report_page_view.dart';
import 'package:reports_ui/widgets/report/card_filters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Widget _app(String path) {
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(
      path: '/v1/menu/:project/:report',
      builder: (_, s) => Scaffold(body: ReportPageView(project: s.pathParameters['project']!, report: s.pathParameters['report']!)),
    ),
  ]);
  return MaterialApp.router(
    theme: ThemeRegistry.theme('cortex', Brightness.light),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: ThemeController(), child: LanguageScope(controller: LanguageController(), child: child!)),
  );
}

/// Report "filters" with two datasets; every dataset request is recorded.
final requests = <String, List<Map<String, String>>>{};

FakeApi _api() {
  final api = FakeApi();
  final filters = [
    {'field': 'kind', 'label': 'Kind', 'type': 'category', 'options': [
      {'value': 'a', 'label': 'Kind A'}, {'value': 'b', 'label': 'Kind B'}]},
    {'field': 'provider', 'label': 'Provider', 'type': 'category', 'options': [
      for (var i = 1; i <= 12; i++) {'value': 'r$i', 'label': 'Provider $i'}]},
    {'field': 'day', 'label': 'Day', 'type': 'date', 'min': '2026-10-01', 'max': '2026-10-10'},
    {'field': 'hour', 'label': 'Hour', 'type': 'hour', 'min': 0, 'max': 23},
    {'field': 'speed', 'label': 'Speed', 'type': 'number', 'min': 0, 'max': 100},
  ];
  final datasets = [
    for (final id in ['d1', 'd2'])
      {
        'dataset_id': id,
        'title': 'Dataset $id',
        'description': '',
        'equation': null,
        'fields': [
          {'name': 'provider', 'label': 'Provider', 'type': 'string', 'role': 'dimension'},
          {'name': 'value', 'label': 'Value', 'type': 'integer', 'role': 'measure'},
        ],
        'filters': filters,
      }
  ];
  api.routes['/projects/cortex/reports/filters'] = (q) => {
        'project': 'cortex', 'report': 'filters', 'title': 'Filters', 'description': '', 'tags': [],
        'period': null, 'updated_at': '', 'datasets': datasets,
      };
  for (final d in datasets) {
    final path = '/projects/cortex/reports/filters/datasets/${d['dataset_id']}';
    api.routes[path] = (q) {
      requests.putIfAbsent(d['dataset_id'] as String, () => []).add(Map.of(q));
      final n = q.keys.where((k) => k.startsWith('f.')).length;
      return {
        ...d,
        'rows': [for (var i = 0; i < 3; i++) {'provider': 'Provider ${i + 1}', 'value': 100 * (n + 1) + i}],
        'offset': 0, 'limit': 500, 'total_rows': 3, 'applied_filters': {},
      };
    };
  }
  return api;
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  requests.clear();
  _api().install();
  await tester.pumpWidget(_app('/v1/menu/cortex/filters'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('card_filters_toggle')).first);
  await tester.pumpAndSettle();
}

Map<String, String> _last(String id) => requests[id]!.last;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('query helpers', () {
    var q = CardFilterQuery.withCategory(const {}, 'kind', {'b', 'a'});
    expect(q, {'f.kind': 'a,b'});
    q = CardFilterQuery.withRange(q, 'day', '2026-10-02', '2026-10-04');
    expect(CardFilterQuery.active(q), 2);
    expect(CardFilterQuery.selected(q, 'kind'), {'a', 'b'});
    expect(CardFilterQuery.withCategory(q, 'kind', {}).containsKey('f.kind'), isFalse);
  });

  testWidgets('category chips reload only their card and use the session cache', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('card_filter_bar')), findsOneWidget);
    final d2Before = requests['d2']!.length;
    await tester.tap(find.byKey(const Key('filter_kind_b')));
    await tester.pumpAndSettle();
    expect(_last('d1')['f.kind'], 'b');
    expect(requests['d2']!.length, d2Before, reason: 'the other card does not reload');
    expect(find.textContaining('200  '), findsOneWidget);

    // Back to no filter: the first result comes from the session cache.
    final d1Count = requests['d1']!.length;
    await tester.tap(find.byKey(const Key('filter_kind_b')));
    await tester.pumpAndSettle();
    expect(requests['d1']!.length, d1Count);
  });

  testWidgets('a long category list opens a dialog with search', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('filter_provider_open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter_dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('filter_search')), 'Provider 1');
    await tester.pumpAndSettle();
    // Provider 1, Provider 10, Provider 11 and Provider 12 match.
    expect(find.byType(CheckboxListTile), findsNWidgets(4));
    await tester.tap(find.byKey(const Key('filter_option_r11')));
    await tester.tap(find.byKey(const Key('filter_option_r12')));
    await tester.tap(find.byKey(const Key('filter_apply')));
    await tester.pumpAndSettle();
    expect(_last('d1')['f.provider'], 'r11,r12');
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('date, hour and number ranges stay within min and max', (tester) async {
    await _open(tester);
    RangeSlider slider(String field) => tester.widget<RangeSlider>(find.byKey(Key('filter_${field}_range')));

    expect(slider('day').min, 0);
    expect(slider('day').max, 9);
    slider('day').onChangeEnd!(const RangeValues(1, 3));
    await tester.pumpAndSettle();
    expect(_last('d1')['f.day.from'], '2026-10-02');
    expect(_last('d1')['f.day.to'], '2026-10-04');
    expect(find.textContaining('Day: 2026-10-02 to 2026-10-04'), findsOneWidget);

    slider('hour').onChangeEnd!(const RangeValues(7, 9));
    await tester.pumpAndSettle();
    expect(_last('d1')['f.hour.from'], '7');
    expect(_last('d1')['f.hour.to'], '9');
    expect(find.textContaining('Hour: 07:00 to 09:00'), findsOneWidget);

    slider('speed').onChangeEnd!(const RangeValues(20, 100));
    await tester.pumpAndSettle();
    expect(_last('d1')['f.speed.from'], '20');
    expect(_last('d1')['f.speed.to'], '100');

    // The full range removes the filter.
    slider('hour').onChangeEnd!(const RangeValues(0, 23));
    await tester.pumpAndSettle();
    expect(_last('d1').containsKey('f.hour.from'), isFalse);
  });

  testWidgets('Reset clears the card filters and the badge', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('filter_kind_a')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('card_filters_toggle')).first, matching: find.text('1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_filters_reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_filters_reset')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('card_filters_toggle')).first, matching: find.text('1')), findsNothing);
  });
}
