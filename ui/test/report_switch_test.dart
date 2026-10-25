import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/widgets/report/dataset_slot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

/// Opening one report after another (the sidebar links) must draw the cards of the new
/// report without passing through another page first.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> switchReports(WidgetTester tester, FakeApi api, {required bool session, required String prefix}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api
      ..withReport('cortex', 'report_1', 3, prefix: 'a')
      ..withReport('cortex', 'report_2', 2, prefix: prefix)
      ..install(withSession: session);
    await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/menu/cortex/report_1'));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is DatasetSlot && w.report == 'report_1'), findsNWidgets(3));
    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/v1/menu/cortex/report_2');
    await tester.pumpAndSettle();
    final slots = tester.widgetList<DatasetSlot>(find.byType(DatasetSlot)).toList();
    expect(slots.map((s) => '${s.report}/${s.slot.datasetId}'), ['report_2/${prefix}1', 'report_2/${prefix}2']);
    if (session) {
      for (final id in ['${prefix}1', '${prefix}2']) {
        expect(api.requests.where((r) => r.url.path.endsWith('/reports/report_2/datasets/$id')), isNotEmpty, reason: id);
      }
    }
  }

  for (final session in [false, true]) {
    final who = session ? 'signed in' : 'guest';
    testWidgets('$who: the next report draws its own cards', (tester) async {
      await switchReports(tester, FakeApi(), session: session, prefix: 'b');
    });
    testWidgets('$who: cards with the same IDs in both reports load the new report', (tester) async {
      await switchReports(tester, FakeApi(), session: session, prefix: 'a');
    });
  }
}
