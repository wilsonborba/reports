import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/landing_view.dart';
import 'package:reports_ui/views/report_list_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Widget _app(String path, {LanguageController? lang}) {
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(path: '/v1/menu', builder: (_, _) => const Scaffold(body: LandingView()), routes: [
      GoRoute(path: ':project', builder: (_, s) => Scaffold(body: ReportListView(project: s.pathParameters['project']!)), routes: [
        GoRoute(path: ':report', builder: (_, s) => Text('opened ${s.pathParameters['report']}')),
      ]),
    ]),
  ]);
  return MaterialApp.router(
    theme: ThemeRegistry.theme('cortex', Brightness.dark),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: ThemeController(), child: LanguageScope(controller: lang ?? LanguageController(), child: child!)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  Future<void> wide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('report list shows cards, pages and opens a report', (tester) async {
    await wide(tester);
    await tester.pumpWidget(_app('/v1/menu/cortex'));
    await tester.pumpAndSettle();
    expect(find.text('Report 1'), findsOneWidget);
    expect(find.text('12 datasets'), findsWidgets);
    expect(find.text('2026-09-01 → 2026-10-20'), findsWidgets);
    // 6 reports fit on one page of 12, so no page controls.
    expect(find.byKey(const Key('page_next')), findsNothing);
    await tester.tap(find.byKey(const Key('report_card_report_3')));
    await tester.pumpAndSettle();
    expect(find.text('opened report_3'), findsOneWidget);
  });

  testWidgets('pages appear when there are more reports than the page size', (tester) async {
    await wide(tester);
    final api = FakeApi().install();
    api.setReports('cortex', (q) {
      final page = int.parse(q['page'] ?? '1');
      return {
        'items': [
          for (var i = 0; i < 12; i++)
            {'slug': 'r${page}_$i', 'project': 'cortex', 'title': 'Report $page.$i', 'description': '', 'dataset_count': 12, 'updated_at': '', 'tags': []}
        ],
        'page': page,
        'page_size': 12,
        'total': 30,
      };
    });
    await tester.pumpWidget(_app('/v1/menu/cortex'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('page_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page_next')));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('empty project shows the empty state in Thai', (tester) async {
    await wide(tester);
    final api = FakeApi().install();
    api.setReports('fsm', (q) => {'items': [], 'page': 1, 'page_size': 12, 'total': 0});
    final lang = LanguageController(initial: AppLanguage.th);
    await tester.pumpWidget(_app('/v1/menu/fsm', lang: lang));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีรายงาน'), findsOneWidget);
  });
}
