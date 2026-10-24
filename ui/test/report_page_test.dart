import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/report_page_view.dart';
import 'package:reports_ui/widgets/report/section_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Widget _app(String path) {
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(
      path: '/v1/menu/:project/:report',
      builder: (_, s) => Scaffold(
        body: ReportPageView(
          project: s.pathParameters['project']!,
          report: s.pathParameters['report']!,
          section: int.tryParse(s.uri.queryParameters['section'] ?? '') ?? 1,
        ),
      ),
    ),
  ]);
  return MaterialApp.router(
    theme: ThemeRegistry.theme('certifications', Brightness.dark),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: ThemeController(), child: LanguageScope(controller: LanguageController(), child: child!)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('section grouping', () {
    List<int> sizes(int n) => LayoutRegistry.group(List.generate(n, (i) => i)).map((s) => s.length).toList();

    test('sections hold 2 to 4 items in API order', () {
      expect(sizes(2), [2]);
      expect(sizes(4), [4]);
      expect(sizes(5), [3, 2]);
      expect(sizes(6), [4, 2]);
      expect(sizes(9), [4, 3, 2]);
      expect(sizes(12), [4, 4, 4]);
      expect(sizes(13), [4, 4, 3, 2]);
      expect(LayoutRegistry.group([1, 2, 3, 4, 5, 6, 7]).first, [1, 2, 3, 4]);
      for (var n = 2; n <= 40; n++) {
        for (final s in sizes(n)) {
          expect(s, inInclusiveRange(2, 4), reason: 'n=$n');
        }
      }
    });

    test('a registered layout keeps its order and adds unknown datasets at the end', () {
      LayoutRegistry.layouts['cortex/model_usage'] = const ReportLayout([
        [Slot('tokens_per_day'), Slot('tokens_by_provider')],
        [Slot('latency_by_model', visual: Visual.combo, companions: ['latency_points'])],
      ]);
      addTearDown(() => LayoutRegistry.layouts.remove('cortex/model_usage'));
      DatasetDescriptor d(String id) => DatasetDescriptor(datasetId: id, title: id, description: '', equation: null, fields: const [], filters: const []);
      final view = ReportView(project: 'cortex', report: 'model_usage', title: '', description: '', tags: const [], period: null, updatedAt: '',
          datasets: [d('tokens_per_day'), d('tokens_by_provider'), d('latency_by_model'), d('latency_points'), d('extra_a'), d('extra_b')]);
      final sections = LayoutRegistry.sectionsFor(view);
      expect(sections.first.map((s) => s.datasetId), ['tokens_per_day', 'tokens_by_provider']);
      expect(sections.expand((s) => s).map((s) => s.datasetId), isNot(contains('latency_points')));
      expect(sections.last.map((s) => s.datasetId), ['extra_a', 'extra_b']);
    });
  });

  testWidgets('report page shows one section at a time and switches with the pills', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    FakeApi().withReport('certifications', 'courses', 9).install();
    await tester.pumpWidget(_app('/v1/menu/certifications/courses'));
    await tester.pumpAndSettle();
    expect(find.text('Test Report'), findsWidgets);
    expect(find.descendant(of: find.byKey(const Key('section_pill_0')), matching: find.text('Section One')), findsOneWidget);
    expect(find.text('Section Three'), findsOneWidget);
    expect(find.byKey(const Key('crumb_3')), findsOneWidget, reason: 'the open section is the last breadcrumb');
    expect(find.text('Dataset 1'), findsOneWidget);
    expect(find.text('Dataset 4'), findsOneWidget);
    expect(find.text('Dataset 5'), findsNothing);
    expect(find.text('T_total = sum(tokens_i)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('section_pill_2')));
    await tester.pumpAndSettle();
    expect(find.text('Dataset 8'), findsOneWidget);
    expect(find.text('Dataset 1'), findsNothing);
  });

  testWidgets('cards use the full width: two columns on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    FakeApi().withReport('certifications', 'courses', 4).install();
    await tester.pumpWidget(_app('/v1/menu/certifications/courses'));
    await tester.pumpAndSettle();
    final grid = tester.getSize(find.byType(SectionBoard)).width;
    expect(grid, greaterThan(1500));
    final card = tester.getSize(find.byKey(const ValueKey('card_d1'))).width;
    expect(card, closeTo((grid - 16) / 2, 1));
  });
}
