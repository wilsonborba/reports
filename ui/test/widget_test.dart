import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void main() {

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('ReportsApp opens the public site first', (WidgetTester tester) async {
    await tester.pumpWidget(const ReportsApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top_bar_home')), findsOneWidget);
    expect(find.byKey(const Key('project_tile_cortex')), findsNothing, reason: 'the hub is not the first page');
  });

  testWidgets('ReportsApp opens the landing page', (WidgetTester tester) async {
    await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/menu'));
    await tester.pumpAndSettle();

    // Top bar name, landing title and the first project tile from the API; no burger icon.
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Project reports'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byKey(const Key('project_tile_cortex')), findsOneWidget);
  });
}
