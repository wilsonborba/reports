import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/public/public_blocks.dart';
import 'package:reports_ui/widgets/public/public_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, {Brightness brightness = Brightness.dark, bool reduceMotion = false}) => MaterialApp(
      theme: ThemeRegistry.theme(null, brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

List<Widget> _cards(int n) => [for (var i = 0; i < n; i++) PublicCard(label: 'Label $i', title: 'Card $i', text: 'Text $i', linkLabel: 'More')];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  test('grid columns follow the Carbon breakpoints', () {
    expect(CardGrid.columnsFor(390, 3), 1);
    expect(CardGrid.columnsFor(800, 3), 2);
    expect(CardGrid.columnsFor(1440, 3), 3);
    expect(CardGrid.columnsFor(1440, 4), 4);
  });

  testWidgets('cards use one column on phones and equal heights in a row', (tester) async {
    _size(tester, const Size(390, 900));
    await tester.pumpWidget(_host(CardGrid(children: _cards(3))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_grid_1')), findsOneWidget);
    expect(tester.takeException(), isNull);

    _size(tester, const Size(1440, 900));
    await tester.pumpWidget(_host(CardGrid(columns: 3, children: [
      const PublicCard(title: 'Short'),
      const PublicCard(title: 'Long', text: 'A long text\nwith\nmany\nlines\nof\ncontent.'),
      const PublicCard(title: 'Short too'),
    ])));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_grid_3')), findsOneWidget);
    final a = tester.getSize(find.byType(PublicCard).at(0));
    final b = tester.getSize(find.byType(PublicCard).at(1));
    expect(a.height, b.height);
  });

  testWidgets('reveal blocks show at once with reduced motion', (tester) async {
    await tester.pumpWidget(_host(const Reveal(child: Text('shown')), reduceMotion: true));
    await tester.pump();
    final opacity = tester.widget<Opacity>(find.ancestor(of: find.text('shown'), matching: find.byType(Opacity)));
    expect(opacity.opacity, 1);
  });

  testWidgets('reveal blocks fade in once when they come into view', (tester) async {
    await tester.pumpWidget(_host(const Reveal(child: Text('shown'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final early = tester.widget<Opacity>(find.ancestor(of: find.text('shown'), matching: find.byType(Opacity))).opacity;
    expect(early, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('shown'), matching: find.byType(Opacity))).opacity, 1);
  });

  testWidgets('the footer shows link columns with projects and company data from the API', (tester) async {
    _size(tester, const Size(1440, 2400));
    await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/home/contact'));
    await tester.pumpAndSettle();
    final footer = find.byKey(const Key('public_footer'));
    expect(footer, findsOneWidget);
    for (final col in ['company', 'projects', 'science', 'developers', 'contact']) {
      expect(find.byKey(Key('footer_$col')), findsOneWidget, reason: col);
    }
    for (final text in ['Cortex', 'Certifications', 'FSM', 'Statistics', 'Discord', 'LINE']) {
      expect(find.descendant(of: footer, matching: find.text(text)), findsOneWidget, reason: text);
    }
    expect(find.descendant(of: footer, matching: find.textContaining('Asodya')), findsWidgets);
  });

  testWidgets('the footer works in light mode and in Thai on a phone', (tester) async {
    _size(tester, const Size(390, 3000));
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'light', 'app_language': 'th'});
    final theme = ThemeController();
    await theme.load();
    expect(theme.isDark, isFalse);
    await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/home'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.descendant(of: find.byKey(const Key('public_footer')), matching: find.text('สถิติ')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('public_footer')), matching: find.textContaining('Asodya')), findsWidgets);
    expect(LanguageController().t('pub_footer_company'), 'Company');
  });
}
