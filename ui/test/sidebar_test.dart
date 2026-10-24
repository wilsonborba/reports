import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/services/catalog_service.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/shell/app_shell.dart';
import 'package:reports_ui/widgets/shell/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Widget _app(String path) {
  final theme = ThemeController();
  final lang = LanguageController();
  final router = GoRouter(initialLocation: path, routes: [
    ShellRoute(
      builder: (c, s, child) => AppShell(project: s.pathParameters['project'], report: s.pathParameters['report'], child: child),
      routes: [
        GoRoute(path: '/v1/menu', builder: (_, _) => const Text('page hub'), routes: [
          GoRoute(path: ':project', builder: (_, s) => Text('page ${s.pathParameters['project']}'), routes: [
            GoRoute(path: ':report', builder: (_, s) => Text('page ${s.pathParameters['report']}')),
          ]),
        ]),
      ],
    ),
  ]);
  return MaterialApp.router(
    theme: ThemeRegistry.theme(null, Brightness.dark),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: theme, child: LanguageScope(controller: lang, child: child!)),
  );
}

void main() {
  late FakeApi api;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi().install();
  });

  Future<void> wide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('opens and closes with the arrow and remembers the state', (tester) async {
    await wide(tester);
    await tester.pumpWidget(_app('/v1/menu/cortex'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('sidebar'))).width, Sidebar.openWidth);
    expect(find.byIcon(Icons.menu), findsNothing);
    await tester.tap(find.byKey(const Key('sidebar_toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('sidebar'))).width, Sidebar.closedWidth);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sidebar_open'), isFalse);
    // Closed: icons with tooltips, the content gets the width.
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('reports show at most four items and a See all link', (tester) async {
    await wide(tester);
    await tester.pumpWidget(_app('/v1/menu/cortex'));
    await tester.pumpAndSettle();
    // The top bar has an Overview tab too; this one is the sidebar item.
    expect(find.descendant(of: find.byKey(const Key('sidebar')), matching: find.text('Overview')), findsOneWidget);
    expect(find.text('Report 1'), findsOneWidget);
    expect(find.text('Report 4'), findsOneWidget);
    expect(find.text('Report 5'), findsNothing);
    expect(find.text('See all'), findsOneWidget);
    await tester.tap(find.text('Report 2'));
    await tester.pumpAndSettle();
    expect(find.text('page report_2'), findsOneWidget);
  });

  testWidgets('a project without reports is not clickable', (tester) async {
    await wide(tester);
    await tester.pumpWidget(_app('/v1/menu'));
    await tester.pumpAndSettle();
    expect(find.text('FSM'), findsOneWidget);
    await tester.tap(find.text('FSM'));
    await tester.pumpAndSettle();
    expect(find.text('page hub'), findsOneWidget);
    await tester.tap(find.text('Certifications'));
    await tester.pumpAndSettle();
    expect(find.text('page certifications'), findsOneWidget);
  });

  testWidgets('hidden on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app('/v1/menu/cortex'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar')), findsNothing);
  });

  test('catalog answers stay cached for five minutes', () async {
    final service = CatalogService.instance;
    await service.projects(lang: 'en');
    await service.projects(lang: 'en');
    expect(api.calls['/catalog'], 1);
    await service.projects(lang: 'th');
    expect(api.calls['/catalog'], 2);
  });
}
