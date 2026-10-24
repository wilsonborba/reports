import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/board_layout.dart';
import 'package:reports_ui/services/board_layout_store.dart';
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
      builder: (_, s) => Scaffold(body: ReportPageView(project: s.pathParameters['project']!, report: s.pathParameters['report']!)),
    ),
  ]);
  return MaterialApp.router(
    theme: ThemeRegistry.theme(null, Brightness.light),
    routerConfig: router,
    builder: (c, child) => ThemeScope(controller: ThemeController(), child: LanguageScope(controller: LanguageController(), child: child!)),
  );
}

/// Opens the report with [datasets] cards and starts the edit mode.
Future<void> _edit(WidgetTester tester, {int datasets = 2, double width = 1400}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  FakeApi().withReport('certifications', 'courses', datasets).install();
  await tester.pumpWidget(_app('/v1/menu/certifications/courses'));
  await tester.pumpAndSettle();
  if (width >= SectionBoard.editWidth) {
    await tester.tap(find.byKey(const Key('edit_layout')));
    await tester.pumpAndSettle();
  }
}

BoardLayout _draft(WidgetTester tester) => tester.state<SectionBoardState>(find.byType(SectionBoard)).draft!;
BoardLayout _layout(WidgetTester tester) => tester.state<SectionBoardState>(find.byType(SectionBoard)).layout;

/// One cell step of the editor: the board shows usedCols + 1 columns (max 4).
Offset _step(WidgetTester tester) {
  final a = tester.getRect(find.byKey(const Key('cell_0_0')));
  final b = tester.getRect(find.byKey(const Key('cell_1_1')));
  return b.topLeft - a.topLeft;
}

Future<void> _dragGrip(WidgetTester tester, String key, Offset by) async {
  await tester.drag(find.byKey(Key(key)), by, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('edit mode shows the cells, one free column and row, and simple cards', (tester) async {
    await _edit(tester);
    expect(find.byKey(const Key('board_editor')), findsOneWidget);
    expect(find.byKey(const Key('edit_bar')), findsOneWidget);
    // Two 2 x 2 cards use 4 columns x 2 rows; one free row appears (columns are already 4).
    expect(find.byKey(const Key('cell_3_2')), findsOneWidget);
    expect(find.byKey(const Key('cell_0_3')), findsNothing);
    expect(find.byKey(const Key('size_d1')), findsOneWidget);
    expect(find.text('2 × 2'), findsNWidgets(2));
  });

  testWidgets('Move in the card menu starts the edit mode', (tester) async {
    await _edit(tester, width: 1400);
    await tester.tap(find.byKey(const Key('edit_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('card_d1')), matching: find.byKey(const Key('card_menu'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card_menu_move')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('board_editor')), findsOneWidget);
  });

  testWidgets('drag a card to free cells; Done saves the layout', (tester) async {
    await _edit(tester);
    final s = _step(tester);
    await _dragGrip(tester, 'edit_card_d1', Offset(0, s.dy * 2));
    expect(_draft(tester).item('d1'), const BoardItem('d1', 0, 2, 2, 2));
    await tester.tap(find.byKey(const Key('edit_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('board_editor')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final saved = BoardLayout.fromJson(jsonDecode(prefs.getString(BoardLayoutStore.key('certifications', 'courses', 1))!))!;
    expect(saved.item('d1'), const BoardItem('d1', 0, 2, 2, 2));
  });

  testWidgets('a drop on another card swaps them; an overlap shows red and changes nothing', (tester) async {
    await _edit(tester);
    final s = _step(tester);
    await _dragGrip(tester, 'edit_card_d1', Offset(s.dx * 2, 0));
    expect(_draft(tester).item('d1')!.col, 2);
    expect(_draft(tester).item('d2')!.col, 0, reason: 'swap');

    final before = _draft(tester).items;
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('edit_card_d1'))));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(Offset(-s.dx / 4, 0));
      await tester.pump();
    }
    expect(find.byKey(const Key('ghost_blocked')), findsOneWidget, reason: 'half on the other card');
    await g.up();
    await tester.pumpAndSettle();
    expect(_draft(tester).items, before);
  });

  testWidgets('left, right, bottom and corner handles resize with snapping and limits', (tester) async {
    await _edit(tester);
    final s = _step(tester);
    await _dragGrip(tester, 'grip_bottom_d1', Offset(0, s.dy));
    expect(_draft(tester).item('d1')!.rowSpan, 3);
    await _dragGrip(tester, 'grip_left_d2', Offset(-s.dx, 0));
    expect(_draft(tester).item('d2')!.col, 2, reason: 'would overlap d1: no change');
    await _dragGrip(tester, 'grip_left_d1', Offset(s.dx * 3, 0));
    expect(_draft(tester).item('d1'), const BoardItem('d1', 1, 0, 1, 3), reason: 'never below 1 column');
    await _dragGrip(tester, 'grip_corner_d2', Offset(0, s.dy * 2));
    expect(_draft(tester).item('d2')!.rowSpan, 4);
    await _dragGrip(tester, 'grip_right_d1', Offset(-s.dx, 0));
    expect(_draft(tester).item('d1')!.colSpan, 1, reason: 'the minimum stays');
  });

  testWidgets('Cancel restores; Reset layout returns to the default and clears the browser copy', (tester) async {
    await _edit(tester);
    final s = _step(tester);
    final start = _layout(tester).items;
    await _dragGrip(tester, 'edit_card_d1', Offset(0, s.dy * 2));
    await tester.tap(find.byKey(const Key('edit_cancel')));
    await tester.pumpAndSettle();
    expect(_layout(tester).items, start);

    await tester.tap(find.byKey(const Key('edit_layout')));
    await tester.pumpAndSettle();
    await _dragGrip(tester, 'edit_card_d1', Offset(0, s.dy * 2));
    await tester.tap(find.byKey(const Key('edit_done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset_layout')));
    await tester.pumpAndSettle();
    expect(_layout(tester).items, start);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoardLayoutStore.key('certifications', 'courses', 1)), isNull);
  });

  testWidgets('keyboard: arrows move the focused card, Shift + arrows resize it', (tester) async {
    await _edit(tester);
    await tester.tap(find.byKey(const Key('edit_card_d1')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_draft(tester).item('d1')!.row, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_draft(tester).item('d1')!.rowSpan, 3);
  });

  testWidgets('no edit mode below 768 px', (tester) async {
    await _edit(tester, width: 700);
    expect(find.byKey(const Key('edit_layout')), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('card_d1')), matching: find.byKey(const Key('card_menu'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_menu_move')), findsNothing);
  });
}
