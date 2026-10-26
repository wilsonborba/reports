import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/widgets/shell/app_shell.dart';
import 'package:reports_ui/services/embed_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('descriptor API preserves selected table and filter state', () async {
    final api = FakeApi();
    api.routes['/projects/cortex/showcase/report_1/cards/d1/embed'] = (query) =>
        {
          'embed_url': 'https://reports.asodya.com/v1/embed/cortex/report_1/d1',
          'view': query['view'],
          'filter': query['f.provider'],
        };
    api.install(withSession: false);
    final descriptor = await itemEmbed(
      '/v1/menu/cortex/report_1/d1?view=table&f.provider=ollama',
      language: 'en',
    );
    expect(descriptor['view'], 'table');
    expect(descriptor['filter'], 'ollama');
  });
  testWidgets('compact route renders one item without the application shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi().withReport('cortex', 'report_1', 1).install(withSession: false);
    await tester.pumpWidget(
      const ReportsApp(
        initialLocation: '/v1/embed/cortex/report_1/d1?view=table',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsNothing);
    expect(find.byKey(const Key('full_view_card')), findsOneWidget);
  });
}
