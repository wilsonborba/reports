import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/shell/app_shell.dart';
import 'package:reports_ui/widgets/shell/breadcrumbs.dart';
import 'package:reports_ui/widgets/shell/top_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Widget _app(Widget child, {ThemeController? theme, LanguageController? language, String path = '/v1/menu'}) {
  final t = theme ?? ThemeController();
  final l = language ?? LanguageController();
  final router = GoRouter(initialLocation: path, routes: [
    ShellRoute(
      builder: (context, state, c) => AppShell(project: state.pathParameters['project'], child: c),
      routes: [
        GoRoute(path: '/v1/home', builder: (_, _) => const Text('public home')),
        GoRoute(path: '/v1/menu', builder: (_, _) => child, routes: [
          GoRoute(path: ':project', builder: (_, s) => Text('project ${s.pathParameters['project']}')),
        ]),
      ],
    ),
  ]);
  return ListenableBuilder(
    listenable: Listenable.merge([t, l]),
    builder: (context, _) => MaterialApp.router(
      theme: ThemeRegistry.theme(null, t.brightness),
      routerConfig: router,
      builder: (context, c) => ThemeScope(controller: t, child: LanguageScope(controller: l, child: c!)),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
  });

  group('Top bar', () {
    testWidgets('shows the Reports name and Asodya mark, the language switch, the theme switch and no sidebar burger', (tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpAndSettle();
      final bar = find.byType(TopBar);
      expect(find.descendant(of: bar, matching: find.text('Reports')), findsOneWidget);
      expect(find.byKey(const Key('lang_en')), findsOneWidget);
      expect(find.byKey(const Key('lang_th')), findsOneWidget);
      expect(find.byKey(const Key('top_bar_theme')), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.textContaining('Public'), findsNothing);
      expect(find.descendant(of: bar, matching: find.byType(Image)), findsOneWidget);
    });

    testWidgets('the language and theme switches change the whole app', (tester) async {
      final theme = ThemeController();
      final language = LanguageController();
      await tester.pumpWidget(_app(Builder(builder: (c) => Text(c.tr('menu'))), theme: theme, language: language));
      await tester.pumpAndSettle();
      expect(find.text('Menu'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lang_th')));
      await tester.pumpAndSettle();
      expect(find.text('เมนู'), findsOneWidget);
      expect(language.code, 'th');
      await tester.tap(find.byKey(const Key('top_bar_theme')));
      await tester.pumpAndSettle();
      expect(theme.isDark, isFalse);
    });

    testWidgets('the name opens the public site', (tester) async {
      await tester.pumpWidget(_app(const Text('hub'), path: '/v1/menu/cortex'));
      await tester.pumpAndSettle();
      expect(find.text('project cortex'), findsOneWidget);
      await tester.tap(find.byKey(const Key('top_bar_home')));
      await tester.pumpAndSettle();
      expect(find.text('public home'), findsOneWidget);
    });
  });

  group('Breadcrumbs', () {
    Widget crumbs(double width) => MaterialApp(
          theme: ThemeRegistry.theme('cortex', Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: const Breadcrumbs(crumbs: [
                Crumb('Menu', '/v1/menu'),
                Crumb('Cortex', '/v1/menu/cortex'),
                Crumb('Token Usage', '/v1/menu/cortex/model_usage'),
                Crumb('Provider Tokens'),
              ]),
            ),
          ),
        );

    testWidgets('shows the full trail with the current page last and not a link', (tester) async {
      await tester.pumpWidget(crumbs(900));
      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Provider Tokens'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));
      final last = find.byKey(const Key('crumb_3'));
      expect(tester.widget(last), isA<Text>());
      expect(find.ancestor(of: find.text('Menu'), matching: find.byType(InkWell)), findsOneWidget);
    });

    testWidgets('keeps the last two levels on narrow screens', (tester) async {
      await tester.pumpWidget(crumbs(400));
      expect(find.text('Menu'), findsNothing);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('Token Usage'), findsOneWidget);
      expect(find.text('Provider Tokens'), findsOneWidget);
    });
  });
}
