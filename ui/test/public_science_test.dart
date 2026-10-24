import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/views/public/science_content.dart';
import 'package:reports_ui/widgets/public/code_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'support/public_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('the science index links five topics and shows every formula as math', (tester) async {
    await openPublic(tester, '/v1/home/science', size: const Size(1440, 5000));
    for (final t in scienceContent) {
      expect(find.byKey(Key('science_topic_${t.id}')), findsOneWidget, reason: t.id);
    }
    final count = scienceContent.fold<int>(0, (a, t) => a + t.formulas.length);
    expect(find.byType(Math), findsNWidgets(count));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('formula_pub_f_kl')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topic_tab_statistics')), findsOneWidget);
  });

  testWidgets('every topic page renders its ideas, formulas, chart and code', (tester) async {
    for (final t in scienceContent) {
      await openPublic(tester, '/v1/home/science/${t.id}', size: const Size(1440, 5000));
      expect(tester.takeException(), isNull, reason: t.id);
      expect(find.byType(Math), findsNWidgets(t.formulas.length), reason: t.id);
      expect(find.byType(CodePanel), findsNWidgets(t.code.length), reason: t.id);
      expect(find.text('Illustration, not real data'), findsOneWidget, reason: t.id);
      expect(find.byKey(const Key('science_next')), findsOneWidget);
      // Every formula parses (no fallback text with the TeX source).
      for (final f in t.formulas) {
        expect(find.text(f.tex), findsNothing, reason: f.tex);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('machine learning shows the YAML configuration and the Python loop', (tester) async {
    await openPublic(tester, '/v1/home/science/machine-learning', size: const Size(1440, 5000));
    expect(find.byKey(const Key('code_panel_yaml')), findsOneWidget);
    expect(find.byKey(const Key('code_panel_python')), findsOneWidget);
    expect(find.byKey(const Key('chart_loss')), findsOneWidget);
  });

  testWidgets('the topic tabs and the next link move between topics', (tester) async {
    await openPublic(tester, '/v1/home/science/data-engineering', size: const Size(1440, 5000));
    await tester.tap(find.byKey(const Key('science_next')));
    await tester.pumpAndSettle();
    expect(find.text('Explore the data, find patterns and measure what matters.'), findsNothing);
    expect(find.byKey(const Key('chart_scatter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('topic_tab_deep-learning')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart_network')), findsOneWidget);
  });

  testWidgets('an unknown topic shows the not found message', (tester) async {
    await openPublic(tester, '/v1/home/science/alchemy');
    expect(find.text('This page does not exist.'), findsOneWidget);
  });

  testWidgets('topic pages fit a phone at 390 px and show code at once there', (tester) async {
    await openPublic(tester, '/v1/home/science/machine-learning', size: const Size(390, 12000));
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.byKey(const Key('code_text')).first);
    final spans = (text.textSpan! as TextSpan).children!;
    expect(spans.whereType<TextSpan>().any((s) => s.style?.color == Colors.transparent), isFalse,
        reason: 'phones do not type the code');
  });

  testWidgets('reduced motion shows every block and chart in its final state at once', (tester) async {
    await openPublic(tester, '/v1/home/science/data-science', reduce: true);
    await tester.tap(find.byKey(const Key('topic_tab_deep-learning')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const Key('chart_network')), findsOneWidget);
    final lead = find.textContaining('Deep learning uses neural networks');
    expect(tester.widget<Opacity>(find.ancestor(of: lead, matching: find.byType(Opacity)).first).opacity, 1);
  });

  testWidgets('without reduced motion the blocks start hidden and fade in', (tester) async {
    await openPublic(tester, '/v1/home/science/data-science');
    await tester.tap(find.byKey(const Key('topic_tab_deep-learning')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final lead = find.textContaining('Deep learning uses neural networks');
    expect(tester.widget<Opacity>(find.ancestor(of: lead, matching: find.byType(Opacity)).first).opacity, lessThan(1));
    await tester.pumpAndSettle();
  });
}
