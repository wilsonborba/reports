import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reports_ui/core/config.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/widgets/charts/data_table_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

/// cortex/report_1 with 3 cards: d1 public, d2 signed_in and d3 restricted placeholders,
/// d1 real and the others sample (a hybrid report), with the engine access counts.
FakeApi _gatedReport(FakeApi api) {
  api.withReport('cortex', 'report_1', 3);
  final showcase = api.routes['/projects/cortex/showcase/report_1']!;
  api.routes['/projects/cortex/showcase/report_1'] = (q) {
    final j = Map<String, dynamic>.from(showcase(q) as Map);
    final cards = [for (final c in j['cards'] as List) Map<String, dynamic>.from(c as Map)];
    cards[0]['data_tier'] = 'real';
    for (final (i, v) in [(1, 'signed_in'), (2, 'restricted')]) {
      cards[i] = {'dataset_id': cards[i]['dataset_id'], 'title': cards[i]['title'], 'visibility': v, 'data_tier': 'sample', 'can_view': false};
    }
    final tier = q['tier'];
    return {
      ...j,
      'data_tier': 'hybrid',
      'tiers': ['real', 'sample'],
      'access': {'total': 3, 'readable': 1, 'needs_sign_in': 1, 'needs_admin': 1},
      'cards': tier == null ? cards : cards.where((c) => c['data_tier'] == tier).toList(),
    };
  };
  return api;
}

Future<void> _open(WidgetTester tester, String path) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ReportsApp(initialLocation: path));
  await tester.pumpAndSettle();
}

String _location(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri.toString();

void main() {
  late FakeApi api;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
  });

  group('guest prompt', () {
    testWidgets('a report says how many charts a sign in opens, from the engine counts', (tester) async {
      _gatedReport(api).install(withSession: false);
      await _open(tester, '/v1/menu/cortex/report_1');
      expect(find.byKey(const Key('guest_prompt')), findsOneWidget);
      expect(find.text('1 charts of this report open with an account'), findsOneWidget);
      // Gated cards show what opens them, without a button of their own.
      expect(find.byKey(const Key('gated_card_d2')), findsOneWidget);
      expect(find.text('Opens after you sign in'), findsOneWidget);
      expect(find.text('Needs access from the project admin'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget, reason: 'one sign in action on the page: the prompt');
    });

    testWidgets('Create account opens the auth_apps sign up with the app context', (tester) async {
      api.install(withSession: false);
      await _open(tester, '/v1/menu');
      await tester.tap(find.byKey(const Key('guest_prompt_sign_up')));
      await tester.pumpAndSettle();
      expect(api.launched.single.path, ReportsConfig.authSignupRoute);
      expect(api.launched.single.queryParameters[ReportsConfig.appContextParam], isNotEmpty);
    });

    testWidgets('closing it keeps it closed for the visit; the public site never shows it', (tester) async {
      api.install(withSession: false);
      await _open(tester, '/v1/home');
      expect(find.byKey(const Key('guest_prompt')), findsNothing, reason: 'the landing has its own CTA');
      expect(find.byKey(const Key('home_sign_in')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav_tab_reports')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest_prompt_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guest_prompt')), findsNothing);
      await tester.tap(find.byKey(const Key('project_tile_cortex')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guest_prompt')), findsNothing);
    });
  });

  group('tier filters', () {
    testWidgets('the report list sends the tier to the engine', (tester) async {
      api.install(withSession: false);
      await _open(tester, '/v1/menu/cortex');
      await tester.tap(find.byKey(const Key('tier_filter_real')));
      await tester.pumpAndSettle();
      final last = api.requests.lastWhere((r) => r.url.path.endsWith('/projects/cortex/reports'));
      expect(last.url.queryParameters['tier'], 'real');
      expect(last.url.queryParameters['page'], '1');
    });

    testWidgets('a hybrid report shows its tiers and the engine filters the cards', (tester) async {
      _gatedReport(api).install(withSession: false);
      await _open(tester, '/v1/menu/cortex/report_1');
      expect(find.byKey(const Key('card_tier_filter')), findsOneWidget);
      expect(find.byKey(const Key('tier_filter_hybrid')), findsNothing, reason: 'only the tiers of this report');
      await tester.tap(find.byKey(const Key('tier_filter_real')));
      await tester.pumpAndSettle();
      expect(api.requests.lastWhere((r) => r.url.path.endsWith('/showcase/report_1')).url.queryParameters['tier'], 'real');
      expect(find.byKey(const Key('gated_card_d2')), findsNothing);
    });
  });

  group('share', () {
    testWidgets('a public chart shares a selectable link of its full view with its state', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      _gatedReport(api).install(withSession: false);
      await _open(tester, '/v1/menu/cortex/report_1');
      await tester.tap(find.byKey(const Key('card_menu')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card_menu_share')));
      await tester.pumpAndSettle();
      final url = tester.widget<SelectableText>(find.byKey(const Key('share_url'))).data!;
      expect(url, 'http://localhost:8110/v1/menu/cortex/report_1/d1');
      await tester.tap(find.byKey(const Key('share_copy')));
      await tester.pumpAndSettle();
      expect(copied, url);
      expect(find.byKey(const Key('share_copied')), findsOneWidget);
    });

    testWidgets('gated charts have no share item', (tester) async {
      _gatedReport(api).install(withSession: false);
      await _open(tester, '/v1/menu/cortex/report_1');
      // Cards come in API order: d1 public, d2 and d3 gated.
      await tester.tap(find.byKey(const Key('card_menu')).at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_menu_info')), findsOneWidget);
      expect(find.byKey(const Key('card_menu_share')), findsNothing, reason: 'a gated link opens nothing for others');
    });

    testWidgets('a shared table link opens the full view as a table with its filters', (tester) async {
      api.withReport('cortex', 'report_1', 2).install(withSession: false);
      await _open(tester, '/v1/menu/cortex/report_1/d1?view=table&f.kind=b');
      expect(find.byKey(const Key('full_view_card')), findsOneWidget);
      expect(find.byType(DataTableView), findsOneWidget);
      expect(api.requests.lastWhere((r) => r.url.path.contains('/cards/d1')).url.queryParameters['f.kind'], 'b');
      await tester.tap(find.byKey(const Key('card_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card_menu_share')));
      await tester.pumpAndSettle();
      final url = tester.widget<SelectableText>(find.byKey(const Key('share_url'))).data!;
      expect(Uri.parse(url).queryParameters, {'view': 'table', 'f.kind': 'b'});
      expect(_location(tester), '/v1/menu/cortex/report_1/d1?view=table&f.kind=b');
    });
  });
}
