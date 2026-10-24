import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/services/section_name_store.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/report_page_view.dart';
import 'package:reports_ui/widgets/shell/page_header.dart';
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

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  FakeApi().withReport('certifications', 'courses', 9).install();
  await tester.pumpWidget(_app('/v1/menu/certifications/courses'));
  await tester.pumpAndSettle();
}

Future<void> _rename(WidgetTester tester, int pill, String name) async {
  await tester.tap(find.byKey(Key('section_pill_$pill')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('section_rename_$pill')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('section_name_field')), name);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('names cannot repeat in one report, ignoring upper and lower case', () {
    expect(sectionNameError('Tokens', ['Section One', 'Section Three']), isNull);
    expect(sectionNameError('tokens', ['Tokens']), 'section_name_taken');
    expect(sectionNameError('  TOKENS  ', ['Tokens']), 'section_name_taken', reason: 'spaces at both ends are removed');
    expect(sectionNameError('section one', ['Section One']), 'section_name_taken', reason: 'default names count too');
    expect(sectionNameError('x' * 33, []), 'section_name_too_long');
    expect(sectionNameError('   ', ['Section One']), isNull, reason: 'empty returns to the default');
  });

  testWidgets('rename with the pencil, persist, and show the name in the breadcrumb', (tester) async {
    await _open(tester);
    await _rename(tester, 1, '  Tokens ');
    expect(find.text('Tokens'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(SectionNameStore.key('certifications', 'courses'))!), {'1': 'Tokens'});
    // Section two is open now; its name is the last breadcrumb.
    expect(find.descendant(of: find.byType(PageHeader), matching: find.text('Tokens')), findsOneWidget);
  });

  testWidgets('a name in another case is refused; Esc cancels; empty returns to the default', (tester) async {
    await _open(tester);
    await _rename(tester, 1, 'Tokens');
    await _rename(tester, 2, 'TOKENS');
    expect(find.byKey(const Key('section_name_error')), findsOneWidget);
    expect(find.byKey(const Key('section_name_editor')), findsOneWidget, reason: 'the editor stays open with the error');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('section_name_editor')), findsNothing);
    expect(find.text('Section Three'), findsWidgets);

    await _rename(tester, 1, '');
    expect(find.text('Section Two'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(SectionNameStore.key('certifications', 'courses'))!), isEmpty);
  });

  testWidgets('double-click a pill to rename it; saved names come back on the next visit', (tester) async {
    SharedPreferences.setMockInitialValues({SectionNameStore.key('certifications', 'courses'): jsonEncode({'0': 'Overview'})});
    await _open(tester);
    expect(find.text('Overview'), findsWidgets);
    await tester.tap(find.byKey(const Key('section_pill_2')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('section_pill_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('section_name_editor')), findsOneWidget);
  });
}
