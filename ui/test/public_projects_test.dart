import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'support/public_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('every project of the API gets a block with its links, Domain details and facts', (tester) async {
    await openPublic(tester, '/v1/home/projects', size: const Size(1440, 6000));
    for (final slug in ['cortex', 'certifications', 'fsm']) {
      expect(find.byKey(Key('project_block_$slug')), findsOneWidget, reason: slug);
      expect(find.byKey(Key('proj_reports_$slug')), findsOneWidget);
    }
    expect(find.text('LLM gateway'), findsOneWidget);
    // Cortex has a website, a repository and Domain details; Certifications has none.
    expect(find.byKey(const Key('proj_repository_cortex')), findsOneWidget);
    expect(find.byKey(const Key('proj_categories_cortex')), findsOneWidget);
    final facts = find.byKey(const Key('project_facts_cortex'));
    expect(find.descendant(of: facts, matching: find.text('cortex.asodya.com')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('github.com')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('active')), findsOneWidget, reason: 'Domain status, not translated');
    expect(find.descendant(of: facts, matching: find.text('Providers')), findsOneWidget, reason: 'Domain statistic');
    expect(find.descendant(of: facts, matching: find.text('wilsonborba')), findsOneWidget, reason: 'collaborators');
    final certifications = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const Key('proj_website_certifications')), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(certifications.onPressed, isNull, reason: 'no website gives a disabled button');
    expect(find.descendant(of: find.byKey(const Key('project_facts_certifications')), matching: find.text('No website yet')), findsOneWidget);
    for (final m in ['schemas', 'calculations', 'access', 'exports']) {
      expect(find.byKey(Key('method_$m')), findsOneWidget);
    }
  });

  testWidgets('a stale Domain copy says when it was fetched', (tester) async {
    final api = FakeApi();
    api.routes['/catalog'] = (q) => {
          'items': [
            {...FakeApi.cortexProject(), 'domain_status': 'stale'},
          ],
          'page': 1,
          'page_size': 100,
          'total': 1,
        };
    api.install();
    await openPublic(tester, '/v1/home/projects', size: const Size(1440, 4000));
    expect(find.byKey(const Key('domain_stale_cortex')), findsOneWidget);
    expect(find.textContaining('2026-10-22'), findsOneWidget);
  });

  testWidgets('the reports button opens the project in the report area', (tester) async {
    await openPublic(tester, '/v1/home/projects', size: const Size(1440, 6000));
    await tester.ensureVisible(find.byKey(const Key('proj_reports_cortex')));
    await tester.tap(find.byKey(const Key('proj_reports_cortex')));
    await tester.pumpAndSettle();
    expect(find.text('Report 1'), findsWidgets);
  });

  testWidgets('an empty catalog shows the empty state', (tester) async {
    final api = FakeApi();
    api.routes['/catalog'] = (q) => {'items': [], 'page': 1, 'page_size': 100, 'total': 0, 'language': 'en'};
    api.install();
    await openPublic(tester, '/v1/home/projects');
    expect(find.text('No projects yet'), findsOneWidget);
  });

  testWidgets('a failed catalog call shows the error state', (tester) async {
    final broken = FakeApi();
    broken.routes.remove('/catalog');
    broken.install();
    CatalogService.instance = CatalogService(broken.apiClient);
    await openPublic(tester, '/v1/home/projects');
    expect(find.text('The data could not be loaded.'), findsOneWidget);
    expect(broken.telemetry.where((t) => t['details']['path'] == '/catalog'), isNotEmpty, reason: 'the failure is reported');
  });

  testWidgets('the projects page fits a phone at 390 px', (tester) async {
    await openPublic(tester, '/v1/home/projects', size: const Size(390, 12000));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('project_block_cortex')), findsOneWidget);
  });
}
