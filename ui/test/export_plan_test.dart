import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/export/card_filter_state.dart';
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/layouts/board_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/services/board_layout_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

DatasetDescriptor d(String id) => DatasetDescriptor(datasetId: id, title: id, description: '', equation: null, fields: const [], filters: const []);

void main() {
  test('plan: board order, section names and active card filters', () async {
    // Six datasets: two automatic sections (4 + 2).
    final view = ReportView(
        project: 'p', report: 'r', title: 'R', description: '', tags: const [], period: null, updatedAt: '', datasets: [for (var i = 1; i <= 6; i++) d('d$i')]);
    // The user swapped d1 and d2 in section 1.
    final swapped = BoardLayout(const [
      BoardItem('d2', 0, 0, 2, 2),
      BoardItem('d1', 2, 0, 2, 2),
      BoardItem('d3', 0, 2, 2, 2),
      BoardItem('d4', 2, 2, 2, 2),
    ]);
    SharedPreferences.setMockInitialValues({BoardLayoutStore.key('p', 'r', 1): jsonEncode(swapped.toJson())});
    CardFilterState.instance.clear();
    CardFilterState.instance.set('p', 'r', 'd5', const {'f.kind': 'a'});
    final plan = await ExportPlan.build(
      project: 'p',
      report: 'r',
      lang: 'en',
      view: view,
      sectionName: (i) => i == 0 ? 'Tokens' : 'Section ${i + 1}',
      now: DateTime(2026, 1, 2),
    );
    expect(plan.sections.map((s) => s.name), ['Tokens', 'Section 2']);
    expect(plan.sections[0].cards.map((c) => c.slot.key), ['d2', 'd1', 'd3', 'd4']);
    expect(plan.sections[1].cards.map((c) => c.slot.key), ['d5', 'd6']);
    expect(plan.sections[1].cards[0].filters, {'f.kind': 'a'});
    expect(plan.sections[1].cards[1].filters, isEmpty);
    expect(plan.fileBase, 'p_r_20260102');
  });
}

