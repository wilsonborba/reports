import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/widgets/public/code_panel.dart';
import 'package:reports_ui/widgets/public/flow_diagram.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'support/public_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  testWidgets('the overview shows every project from the API, the topics and the next steps', (tester) async {
    await openPublic(tester, '/v1/home');
    expect(find.text('One analytics layer for every project'), findsOneWidget);
    for (final slug in ['cortex', 'certifications', 'fsm']) {
      expect(find.byKey(Key('home_project_$slug')), findsOneWidget, reason: slug);
    }
    expect(find.text('LLM gateway'), findsOneWidget, reason: 'the tagline comes from the API');
    for (final topic in ['data-engineering', 'data-science', 'machine-learning', 'deep-learning', 'statistics']) {
      expect(find.byKey(Key('home_topic_$topic')), findsOneWidget, reason: topic);
    }
    expect(find.byType(FlowDiagram), findsOneWidget);
    expect(find.byType(CodePanel), findsNWidgets(2), reason: 'the envelope and the API request');
    expect(find.byKey(const Key('cta_reports')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the contact step opens the contact page', (tester) async {
    await openPublic(tester, '/v1/home');
    await tester.tap(find.byKey(const Key('cta_contact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_project_cortex')), findsNothing);
    expect(find.text('Contact us'), findsWidgets);
  });

  testWidgets('the overview fits a phone at 390 px in Thai', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'th'});
    await openPublic(tester, '/v1/home', size: const Size(390, 9000));
    expect(tester.takeException(), isNull);
    expect(find.text('โครงการของเรา'), findsOneWidget);
    expect(find.byKey(const Key('card_grid_1')), findsWidgets);
  });

  testWidgets('reduced motion shows the whole code at once', (tester) async {
    await openPublic(tester, '/v1/home', reduce: true);
    for (final text in tester.widgetList<Text>(find.byKey(const Key('code_text')))) {
      final spans = (text.textSpan! as TextSpan).children!;
      expect(spans.whereType<TextSpan>().any((s) => s.style?.color == Colors.transparent), isFalse);
    }
  });

  test('the JSON highlighter marks keys, strings and numbers', () {
    const code = '{"a": "b", "n": 1.5, "ok": true}';
    final tokens = CodeHighlighter.tokens(code, CodeLanguage.json);
    String kindOf(String text) => tokens.firstWhere((t) => t.text == text).kind;
    expect(kindOf('"a"'), 'key');
    expect(kindOf('"b"'), 'string');
    expect(kindOf('1.5'), 'number');
    expect(kindOf('true'), 'keyword');
    expect(tokens.map((t) => t.text).join(), code);
  });

  test('the YAML and Python highlighters mark keys, comments and keywords', () {
    final yaml = CodeHighlighter.tokens('model:\n  name: demo # note\n  layers: 3', CodeLanguage.yaml);
    expect(yaml.where((t) => t.kind == 'key').map((t) => t.text), containsAll(['model', 'name', 'layers']));
    expect(yaml.any((t) => t.kind == 'comment' && t.text == '# note'), isTrue);
    final py = CodeHighlighter.tokens('for x in range(3):\n    print("hi")', CodeLanguage.python);
    expect(py.where((t) => t.kind == 'keyword').map((t) => t.text), containsAll(['for', 'in']));
    expect(py.any((t) => t.kind == 'string' && t.text == '"hi"'), isTrue);
  });
}
