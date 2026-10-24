import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/views/landing_view.dart';
import 'package:reports_ui/widgets/shell/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Future<void> _open(WidgetTester tester, {double width = 1400, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FakeApi().install();
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/menu'));
  await tester.pumpAndSettle();
}

double _left(WidgetTester tester, String slug) => tester.getTopLeft(find.byKey(Key('project_tile_$slug'))).dx;

void main() {
  testWidgets('landing has no sidebar and shows the totals from the stats API', (tester) async {
    await _open(tester);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.text('Project reports'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('stat_rows')), matching: find.text('519,209')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('stat_stored')), matching: find.text('75.7 MB')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('stat_projects')), matching: find.text('3')), findsOneWidget);
  });

  testWidgets('a tile shows the API texts, link domain and numbers', (tester) async {
    await _open(tester);
    expect(find.text('Cortex'), findsOneWidget);
    expect(find.text('LLM gateway'), findsOneWidget);
    expect(find.byKey(const Key('domain_cortex')), findsOneWidget);
    expect(find.text('cortex.asodya.com'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tile_reports_cortex')), matching: find.text('6')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tile_charts_cortex')), matching: find.text('72')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tile_rows_cortex')), matching: find.text('356k')), findsOneWidget);
  });

  testWidgets('website button is disabled without a link; open reports is disabled without reports', (tester) async {
    await _open(tester, prefs: {LandingViewModeStore.key: 'list'});
    ButtonStyleButton web(String slug) => tester.widget<ButtonStyleButton>(find.byKey(Key('website_$slug')));
    ButtonStyleButton open(String slug) => tester.widget<ButtonStyleButton>(find.byKey(Key('open_reports_$slug')));
    expect(web('cortex').onPressed, isNotNull);
    expect(web('certifications').onPressed, isNull);
    expect(open('certifications').onPressed, isNotNull);
    expect(open('fsm').onPressed, isNull);
    expect(find.descendant(of: find.byKey(const Key('project_tile_fsm')), matching: find.text('No reports yet')), findsOneWidget);
  });

  testWidgets('open reports goes to the project', (tester) async {
    await _open(tester, prefs: {LandingViewModeStore.key: 'list'});
    await tester.tap(find.byKey(const Key('open_reports_cortex')));
    await tester.pumpAndSettle();
    expect(find.byType(LandingView), findsNothing);
    expect(find.byType(Sidebar), findsOneWidget, reason: 'project pages keep the sidebar');
  });

  testWidgets('carousel: 2 tiles and a peek on desktop; arrows and keys move it', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('carousel')), findsOneWidget);
    final carousel = tester.getRect(find.byKey(const Key('carousel')));
    final first = tester.getRect(find.byKey(const Key('project_tile_cortex')));
    expect(first.width, closeTo(carousel.width * 0.47 - 16, 1));
    final prev = tester.widget<IconButton>(find.byKey(const Key('carousel_prev')));
    expect(prev.onPressed, isNull, reason: 'the first tile is at the start');
    final start = _left(tester, 'certifications');
    await tester.ensureVisible(find.byKey(const Key('carousel_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('carousel_next')));
    await tester.pumpAndSettle();
    expect(_left(tester, 'certifications'), lessThan(start - 100));
    expect(tester.widget<IconButton>(find.byKey(const Key('carousel_next'))).onPressed, isNull, reason: '3 projects, 2 visible: one step');
    // Arrow keys move it back.
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('carousel'))) + const Offset(40, 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_left(tester, 'certifications'), closeTo(start, 1));
  });

  testWidgets('carousel swipes on a phone and shows 1 tile', (tester) async {
    await _open(tester, width: 400);
    final carousel = tester.getRect(find.byKey(const Key('carousel')));
    expect(tester.getRect(find.byKey(const Key('project_tile_cortex'))).width, greaterThan(carousel.width * 0.8));
    await tester.drag(find.byKey(const Key('carousel')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('project_tile_certifications'))).left, closeTo(carousel.left, 1));
  });

  testWidgets('list view shows every tile and the choice persists', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('view_list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('landing_list')), findsOneWidget);
    expect(find.byKey(const Key('carousel')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LandingViewModeStore.key), 'list');
    expect(tester.getTopLeft(find.byKey(const Key('project_tile_certifications'))).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('project_tile_cortex'))).dy));
  });

  testWidgets('Thai texts on the landing page', (tester) async {
    await _open(tester, prefs: {'app_language': 'th'});
    expect(find.text('รายงานโครงการ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
