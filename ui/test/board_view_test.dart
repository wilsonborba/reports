import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/board_layout.dart';
import 'package:reports_ui/services/board_layout_store.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/report_page_view.dart';
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
    theme: ThemeRegistry.theme(null, Brightness.light),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: ThemeController(), child: LanguageScope(controller: LanguageController(), child: child!)),
  );
}

Future<void> _open(WidgetTester tester, {double width = 1400, int datasets = 4}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  FakeApi().withReport('certifications', 'courses', datasets).install();
  await tester.pumpWidget(_app('/v1/menu/certifications/courses'));
  await tester.pumpAndSettle();
}

Finder _card(String key) => find.byKey(ValueKey('card_$key'));

Future<BoardLayout?> _saved() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(BoardLayoutStore.key('certifications', 'courses', 1));
  return raw == null ? null : BoardLayout.fromJson(jsonDecode(raw));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('default board: 2 x 2 blocks in reading order, cards fill their cells', (tester) async {
    await _open(tester);
    final a = tester.getRect(_card('d1')), b = tester.getRect(_card('d2')), c = tester.getRect(_card('d3'));
    expect(b.left, greaterThan(a.right), reason: 'd2 right of d1');
    expect(c.top, greaterThan(a.bottom), reason: 'd3 below d1');
    expect(a.height, closeTo(2 * 180 + 16, 0.5));
    expect(find.byKey(const Key('board_scroll')), findsNothing, reason: 'four columns fit in 1400 px');
  });

  testWidgets('the board grows with the cards: two cards use two rows', (tester) async {
    await _open(tester, datasets: 2);
    expect(tester.getSize(find.byKey(const Key('board'))).height, closeTo(2 * 180 + 16, 0.5));
  });

  testWidgets('horizontal scroll only when the columns do not fit', (tester) async {
    await _open(tester, width: 900);
    expect(find.byKey(const Key('board_scroll')), findsOneWidget, reason: '4 x 220 px + gaps > 852 px of content');
    expect(tester.getSize(find.byKey(const Key('board'))).width, closeTo(4 * 220 + 3 * 16, 0.5));
  });

  testWidgets('phones show one column in reading order', (tester) async {
    await _open(tester, width: 400);
    expect(find.byKey(const Key('board_phone')), findsOneWidget);
    expect(tester.getRect(_card('d2')).top, greaterThanOrEqualTo(tester.getRect(_card('d1')).bottom));
    expect(tester.getRect(_card('d1')).left, closeTo(tester.getRect(_card('d2')).left, 0.5));
  });

  testWidgets('a saved layout is restored; minimize persists', (tester) async {
    SharedPreferences.setMockInitialValues({
      BoardLayoutStore.key('certifications', 'courses', 1): jsonEncode(const BoardLayout([
        BoardItem('d1', 0, 0, 1, 4), BoardItem('d2', 1, 0, 1, 2), BoardItem('d3', 1, 2, 1, 2), BoardItem('d4', 2, 0, 2, 4),
      ]).toJson()),
    });
    await _open(tester);
    expect(tester.getRect(_card('d1')).height, closeTo(4 * 180 + 3 * 16, 0.5), reason: 'd1 covers 4 rows');
    expect(tester.getRect(_card('d4')).left, greaterThan(tester.getRect(_card('d3')).right));

    await tester.tap(find.descendant(of: _card('d2'), matching: find.byKey(const Key('card_menu'))));
    await tester.pumpAndSettle();
    expect(find.text('Info'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_menu_minimize')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card('d2'), matching: find.text('Minimized')), findsOneWidget);
    expect((await _saved())!.minimized, {'d2'});
    expect((await _saved())!.item('d1'), const BoardItem('d1', 0, 0, 1, 4));
  });

  testWidgets('the card info dialog shows the description and the equation', (tester) async {
    await _open(tester);
    await tester.tap(find.descendant(of: _card('d1'), matching: find.byKey(const Key('card_menu'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('Description 1'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('card_info_dialog')), matching: find.text('T_total = sum(tokens_i)')), findsOneWidget);
  });
}
