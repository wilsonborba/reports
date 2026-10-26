import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/views/public/architecture_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'support/public_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('the Architecture tab opens the Architecture page', (tester) async {
    await openPublic(tester, '/v1/home', size: const Size(1440, 6000));
    await tester.tap(find.byKey(const Key('nav_tab_architecture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arch_title')), findsOneWidget);
    expect(find.byType(ArchitectureView), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('footer_developers')), matching: find.text('OpenAPI file')), findsOneWidget);
  });

  testWidgets('/v1/home/api redirects to /v1/home/architecture', (tester) async {
    await openPublic(tester, '/v1/home/api', size: const Size(1440, 6000));
    expect(find.byKey(const Key('arch_title')), findsOneWidget);
    expect(find.byType(ArchitectureView), findsOneWidget);
  });

  testWidgets('the overview has an Architecture teaser that opens the Architecture page', (tester) async {
    await openPublic(tester, '/v1/home', size: const Size(1440, 6000));
    expect(find.byKey(const Key('home_architecture_teaser')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home_architecture_more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arch_title')), findsOneWidget);
  });

  testWidgets('the Architecture page fits a phone at 390 px', (tester) async {
    await openPublic(tester, '/v1/home/architecture', size: const Size(390, 9000));
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['en', 'pt-BR']) {
    testWidgets('the Architecture page names every service it uses ($lang)', (tester) async {
      SharedPreferences.setMockInitialValues({'app_language': lang});
      await openPublic(tester, '/v1/home/architecture', size: const Size(1440, 9000));
      for (final name in ['api_for_apps', 'domain_api', 'PostgreSQL', 'CouchDB', 'Redis', 'FSM']) {
        expect(find.textContaining(name), findsWidgets, reason: '$name on the $lang page');
      }
    });
  }
}
