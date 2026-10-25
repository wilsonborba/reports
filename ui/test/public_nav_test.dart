import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Future<void> _open(WidgetTester tester, String path, {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ReportsApp(initialLocation: path));
  await tester.pumpAndSettle();
}

BorderSide _underline(WidgetTester tester, String id) {
  final box = tester.widget<AnimatedContainer>(
      find.descendant(of: find.byKey(Key('nav_tab_$id')), matching: find.byType(AnimatedContainer)));
  return ((box.decoration! as BoxDecoration).border! as Border).bottom;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('the root and /v1 open the public overview', (tester) async {
    await _open(tester, '/');
    expect(_underline(tester, 'overview').width, 3);
    await _open(tester, '/v1');
    expect(_underline(tester, 'overview').color, ThemeRegistry.palette(null, Brightness.dark).accent);
  });

  testWidgets('desktop tabs open their pages and mark the current tab', (tester) async {
    await _open(tester, '/v1/home');
    final accent = ThemeRegistry.palette(null, Brightness.dark).accent;
    for (final id in ['projects', 'science', 'architecture', 'contact', 'overview']) {
      await tester.tap(find.byKey(Key('nav_tab_$id')));
      await tester.pumpAndSettle();
      expect(_underline(tester, id).color, accent, reason: id);
      for (final other in ['overview', 'projects', 'science', 'architecture', 'contact'].where((o) => o != id)) {
        expect(_underline(tester, other).color, Colors.transparent, reason: '$other is not current');
      }
    }
    expect(find.byKey(const Key('top_bar_menu')), findsNothing, reason: 'wide screens show the tabs');
  });

  testWidgets('a science topic keeps the Science tab marked', (tester) async {
    await _open(tester, '/v1/home/science/statistics');
    expect(_underline(tester, 'science').width, 3);
    expect(_underline(tester, 'overview').color, Colors.transparent);
  });

  testWidgets('Reports is a tab like the others and opens the report hub', (tester) async {
    await _open(tester, '/v1/home');
    await tester.tap(find.byKey(const Key('nav_tab_reports')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_tile_cortex')), findsOneWidget);
    expect(_underline(tester, 'reports').width, 3, reason: 'the report area marks the Reports tab');
    expect(_underline(tester, 'overview').color, Colors.transparent);
  });

  testWidgets('phones use a menu button with the same links and no horizontal overflow', (tester) async {
    await _open(tester, '/v1/home', size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('nav_tab_projects')), findsNothing);
    await tester.tap(find.byKey(const Key('top_bar_menu')));
    await tester.pumpAndSettle();
    for (final id in ['overview', 'projects', 'science', 'architecture', 'contact', 'reports']) {
      expect(find.byKey(Key('nav_menu_$id')), findsOneWidget, reason: id);
    }
    await tester.tap(find.byKey(const Key('nav_menu_contact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_menu_contact')), findsNothing, reason: 'the panel closes');
    await tester.tap(find.byKey(const Key('top_bar_menu')));
    await tester.pumpAndSettle();
    final panel = tester.widget<Container>(find.descendant(of: find.byKey(const Key('nav_menu_contact')), matching: find.byType(Container)).first);
    expect(((panel.decoration! as BoxDecoration).border! as Border).left.width, 3, reason: 'the current page is marked');
    await tester.tap(find.byKey(const Key('nav_menu_reports')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project_tile_cortex')), findsOneWidget);
  });

  testWidgets('the tabs use the flat Carbon style', (tester) async {
    await _open(tester, '/v1/home');
    final box = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byKey(const Key('nav_tab_overview')), matching: find.byType(AnimatedContainer)));
    expect((box.decoration! as BoxDecoration).borderRadius, isNull);
    expect(ReportPalette.controlRadius, 2);
  });

  testWidgets('the report area keeps the same header: tabs, no session buttons', (tester) async {
    await _open(tester, '/v1/menu/cortex');
    for (final id in ['overview', 'projects', 'reports', 'science', 'architecture', 'contact']) {
      expect(find.byKey(Key('nav_tab_$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const Key('top_bar_sign_in')), findsNothing);
    expect(find.byKey(const Key('top_bar_log_out')), findsNothing, reason: 'log out lives in the sidebar');
    // Narrow screen in the report area: the menu button with the same links.
    await _open(tester, '/v1/menu', size: const Size(390, 844));
    expect(find.byKey(const Key('nav_tab_reports')), findsNothing);
    await tester.tap(find.byKey(const Key('top_bar_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_menu_reports')), findsOneWidget);
  });
}
