import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/charts/data_table_view.dart';
import 'package:reports_ui/widgets/charts/sankey_chart.dart';
import 'package:reports_ui/widgets/charts/sankey_layout.dart';
import 'package:reports_ui/widgets/charts/series_colors.dart' show otherKey;
import 'package:reports_ui/widgets/charts/visual_chooser.dart';
import 'charts_test.dart' show f, page, pumpChart;

final fromState = f('from_state', 'string', dim: true);
final toState = f('to_state', 'string', dim: true);
final machine = f('machine', 'string', dim: true);
final transitionCount = f('transitions', 'integer', unit: 'transitions');

final transitions = page([fromState, toState, transitionCount], [
  {'from_state': 'idle', 'to_state': 'running', 'transitions': 70},
  {'from_state': 'idle', 'to_state': 'paused', 'transitions': 30},
  {'from_state': 'running', 'to_state': 'running', 'transitions': 60},
  {'from_state': 'running', 'to_state': 'done', 'transitions': 20},
  {'from_state': 'failed', 'to_state': 'paused', 'transitions': 20},
]);

const transitionSlot = Slot('o', visual: Visual.sankey, dimensions: ['from_state', 'to_state'], measures: ['transitions']);

void main() {
  group('layout', () {
    test('flows keep the totals and nodes size by their flow', () {
      final l = SankeyLayout.build(transitions.rows, [fromState, toState], transitionCount);
      expect(l.total, 200);
      expect(l.columns.length, 2);
      expect(l.columns[0].map((n) => n.key), ['idle', 'running', 'failed'], reason: 'largest first');
      expect(l.columns[1].map((n) => n.key), ['running', 'paused', 'done']);
      expect(l.links.fold<double>(0, (a, x) => a + x.value), 200);
      final black = l.columns[1].first;
      expect(black.inValue, 130);
      l.place(600, 300, left: 100, right: 100, gap: 10);
      // One scale: node height over value is the same everywhere.
      final k = l.columns[0].first.height / l.columns[0].first.value;
      for (final col in l.columns) {
        for (final n in col) {
          expect(n.height / n.value, closeTo(k, 1e-9));
        }
      }
      // Bands stack inside their nodes without overlap.
      for (final n in l.columns[0]) {
        final out = l.links.where((x) => x.source == n).toList()..sort((a, b) => a.sourceY.compareTo(b.sourceY));
        expect(out.first.sourceY, closeTo(n.y, 1e-9));
        expect(out.last.sourceY + out.last.thickness, closeTo(n.y + n.height, 1e-9));
      }
      expect(l.columns[0].first.x, 100);
      expect(l.columns[1].first.x, closeTo(600 - 100 - 12, 1e-9));
    });

    test('three stages: middle nodes pass their whole flow on', () {
      final rows = [
        for (final (u, lo, r, v) in [('A', 'X', 'checkout', 5), ('A', 'Y', 'signup', 3), ('B', 'X', 'signup', 2)]) {'from_state': u, 'to_state': lo, 'machine': r, 'transitions': v},
      ];
      final l = SankeyLayout.build(rows, [fromState, toState, machine], transitionCount);
      expect(l.columns.length, 3);
      for (final n in l.columns[1]) {
        expect(n.inValue, n.outValue);
      }
      expect(l.links.where((x) => x.source.stage == 1).fold<double>(0, (a, x) => a + x.value), 10);
    });

    test('a stage keeps 7 categories and folds the rest into Other, last in its column', () {
      final rows = [for (var i = 0; i < 10; i++) {'from_state': 'C$i', 'to_state': 'L', 'transitions': 100 - i}];
      final l = SankeyLayout.build(rows, [fromState, toState], transitionCount);
      expect(l.columns[0].length, 8);
      expect(l.columns[0].last.key, otherKey);
      expect(l.columns[0].last.value, 93 + 92 + 91);
    });

    test('rows without a positive value are left out', () {
      final l = SankeyLayout.build([
        {'from_state': 'A', 'to_state': 'B', 'transitions': 0},
        {'from_state': 'A', 'to_state': 'B', 'transitions': null},
      ], [fromState, toState], transitionCount);
      expect(l.isEmpty, isTrue);
    });
  });

  group('visual chooser', () {
    test('a Sankey needs 2 category stages; the automatic choice never picks it', () {
      expect(VisualChooser.resolve(transitions, transitionSlot), Visual.sankey);
      expect(VisualChooser.resolve(transitions, const Slot('o', visual: Visual.sankey, dimensions: ['from_state'])), Visual.table);
      expect(VisualChooser.auto(transitions), isNot(Visual.sankey));
      // Without a list the stages are the category dimensions in field order.
      expect(VisualChooser.sankeyStages(transitions.descriptor, const Slot('o')).map((f) => f.name), ['from_state', 'to_state']);
    });

    test('a registered visual keeps its place in the automatic grouping', () {
      LayoutRegistry.visuals['fsm/transitions/transitions'] = const Slot('transitions', visual: Visual.sankey, dimensions: ['from_state', 'to_state']);
      addTearDown(() => LayoutRegistry.visuals.remove('fsm/transitions/transitions'));
      final view = ReportView(project: 'fsm', report: 'transitions', title: '', description: '', tags: const [], period: null, updatedAt: '', datasets: [
        DatasetDescriptor(datasetId: 'transitions', title: 'Transitions', description: '', equation: null, fields: const [], filters: const []),
      ]);
      final slot = LayoutRegistry.sectionsFor(view).first.first;
      expect(slot.visual, Visual.sankey);
      expect(slot.dimensions, ['from_state', 'to_state']);
    });
  });

  group('widget', () {
    testWidgets('renders labels and values on desktop and on a phone', (tester) async {
      for (final width in [1100.0, 390.0]) {
        await pumpChart(tester, VisualChooser.build(transitions, transitionSlot), width: width);
        expect(find.byType(SankeyChart), findsOneWidget);
        expect(find.textContaining('idle'), findsOneWidget);
        expect(find.textContaining('done'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('hover on a link shows source, target, value and share', (tester) async {
      await pumpChart(tester, VisualChooser.build(transitions, transitionSlot));
      final box = tester.getRect(find.byKey(const Key('sankey')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // Walk down the middle of the chart until a band is under the pointer.
      for (var y = box.top + 2; y < box.bottom && find.byKey(const Key('sankey_tooltip')).evaluate().isEmpty; y += 4) {
        await mouse.moveTo(Offset(box.center.dx, y));
        await tester.pump();
      }
      expect(find.byKey(const Key('sankey_tooltip')), findsOneWidget);
      final text = tester.widget<Text>(find.descendant(of: find.byKey(const Key('sankey_tooltip')), matching: find.byType(Text))).textSpan!.toPlainText();
      expect(text, contains('→'));
      expect(text, contains('transitions'));
      expect(text, contains('% of '));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byKey(const Key('sankey_tooltip')), findsNothing);
    });

    testWidgets('a board card gives the chart its height; the card menu table still works', (tester) async {
      await pumpChart(tester, SizedBox(height: 300, child: VisualChooser.build(transitions, transitionSlot, height: 300)));
      expect(tester.getSize(find.byKey(const Key('sankey'))).height, lessThanOrEqualTo(300));
      await pumpChart(tester, DataTableView(page: transitions));
      expect(find.text('idle'), findsNWidgets(2));
    });

    testWidgets('reduced motion shows the final chart at once', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeRegistry.theme(null, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1100, 900), disableAnimations: true),
          child: Scaffold(body: VisualChooser.build(transitions, transitionSlot)),
        ),
      ));
      await tester.pump();
      final label = find.ancestor(of: find.textContaining('idle'), matching: find.byType(AnimatedOpacity)).first;
      expect(tester.widget<AnimatedOpacity>(label).opacity, 1);
    });
  });
}
