import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/views/public/contact_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'support/public_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('the contact page shows the Asodya community groups', (tester) async {
    await openPublic(tester, '/v1/home/contact');
    expect(find.byKey(const Key('contact_company_name')), findsOneWidget);
    expect(find.text('Asodya'), findsWidgets);
    for (final group in ['discord', 'slack', 'telegram', 'line']) {
      expect(find.byKey(Key('contact_group_$group')), findsOneWidget, reason: group);
    }
    expect(find.byKey(const Key('contact_row_website')), findsOneWidget);
    expect(find.byKey(const Key('contact_row_social')), findsOneWidget);
    for (final row in ['address', 'phone', 'email']) {
      expect(find.byKey(Key('contact_row_$row')), findsNothing, reason: 'no $row value: no row');
    }
  });

  testWidgets('every project shows its website and repository from the catalog API', (tester) async {
    await openPublic(tester, '/v1/home/contact');
    for (final slug in ['cortex', 'certifications', 'fsm']) {
      expect(find.byKey(Key('contact_project_$slug')), findsOneWidget, reason: slug);
    }
    final cortex = find.byKey(const Key('contact_project_cortex'));
    expect(find.descendant(of: cortex, matching: find.text('cortex.asodya.com')), findsOneWidget);
    expect(find.descendant(of: cortex, matching: find.text('github.com')), findsOneWidget);
    final certifications = find.byKey(const Key('contact_project_certifications'));
    expect(find.descendant(of: certifications, matching: find.text('Not yet')), findsNWidgets(2));
  });

  testWidgets('the contact page fits a phone at 390 px in Thai', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'th'});
    await openPublic(tester, '/v1/home/contact', size: const Size(390, 5000));
    expect(tester.takeException(), isNull);
    expect(find.text('ลิงก์ของโปรเจกต์'), findsOneWidget);
    expect(find.byKey(const Key('contact_group_line')), findsOneWidget);
  });

  test('phone links keep digits and the plus sign', () {
    expect(ContactView.telLink('+66 (0)2 000-0000'), 'tel:+66020000000');
  });
}
