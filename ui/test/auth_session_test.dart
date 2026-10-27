import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:reports_ui/core/config.dart';
import 'package:reports_ui/export/card_filter_state.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/auth_service.dart';
import 'package:reports_ui/services/session_store.dart';
import 'package:reports_ui/themes/theme_controller.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/shell/sidebar_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _location(WidgetTester tester) {
  final context = tester.element(find.byType(Navigator).first);
  return GoRouter.of(context).state.uri.toString();
}

/// SidebarFooter alone in a small router with the public home page.
Widget _footerApp({required bool open, String stamp = ''}) {
  final router = GoRouter(
    initialLocation: '/v1/menu',
    routes: [
      GoRoute(
        path: '/v1/menu',
        builder: (_, _) => Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: open ? 240 : 64,
              child: SidebarFooter(open: open, stamp: stamp),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AuthRoutes.home,
        builder: (_, _) => const Text('public home page'),
      ),
    ],
  );
  return MaterialApp.router(
    theme: ThemeRegistry.theme(null, Brightness.light),
    routerConfig: router,
    builder: (c, child) => ThemeScope(
      controller: ThemeController(),
      child: LanguageScope(controller: LanguageController(), child: child!),
    ),
  );
}

void main() {
  late FakeApi api;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
  });

  group('session check', () {
    testWidgets(
      'a browser without the csrf cookie is a guest without any call',
      (tester) async {
        api.install(withSession: false, checkSession: true);
        await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/menu'));
        await tester.pumpAndSettle();
        expect(SessionStore.instance.state, SessionState.guest);
        expect(api.calls['/me'], isNull);
        expect(api.calls['/user/info/v1/'], isNull);
        expect(
          find.byKey(const Key('guest_prompt_sign_in')),
          findsOneWidget,
          reason: 'the report area offers the login once',
        );
        expect(
          find.byKey(const Key('top_bar_sign_in')),
          findsNothing,
          reason: 'no session buttons in the header',
        );
      },
    );

    testWidgets(
      'the csrf cookie and GET /me open the session once, then the user info loads',
      (tester) async {
        api.install(checkSession: true);
        await tester.pumpWidget(const ReportsApp(initialLocation: '/v1/menu'));
        await tester.pumpAndSettle();
        expect(SessionStore.instance.hasSession, isTrue);
        expect(api.calls['/me'], 1);
        expect(api.calls['/user/info/v1/'], 1);
        expect(SessionStore.instance.user!.name, 'Test Viewer');
        expect(SessionStore.instance.user!.email, 'viewer@example.org');
        expect(
          find.byKey(const Key('guest_prompt')),
          findsNothing,
          reason: 'a session gets no login prompt',
        );
        expect(
          find.byKey(const Key('top_bar_log_out')),
          findsNothing,
          reason: 'log out lives in the sidebar',
        );
      },
    );

    testWidgets(
      'a refused session becomes a guest once, with a message and no redirect',
      (tester) async {
        api.overrides['/me'] = (req) =>
            _json({'code': 'session_required', 'message': 'no session'}, 401);
        api.withReport('cortex', 'report_1', 2);
        api.install(checkSession: true);
        await tester.pumpWidget(
          const ReportsApp(initialLocation: '/v1/menu/cortex/report_1'),
        );
        await tester.pumpAndSettle();
        expect(SessionStore.instance.state, SessionState.guest);
        expect(
          _location(tester),
          '/v1/menu/cortex/report_1',
          reason: 'the page stays',
        );
        expect(find.byKey(const Key('session_ended')), findsOneWidget);
        expect(api.calls['/me'], 1, reason: 'no retry loop');
        expect(api.launched, isEmpty, reason: 'no automatic login');
        expect(
          api.calls['/projects/cortex/showcase/report_1'],
          1,
          reason: 'the guest view loads',
        );
        expect(
          api.telemetry,
          isEmpty,
          reason: '401 is an expected state, not an error',
        );
      },
    );
  });

  group('sign in', () {
    testWidgets(
      'the Sign in button opens auth_apps with an encrypted app_context',
      (tester) async {
        api.install(withSession: false);
        await tester.pumpWidget(
          const ReportsApp(initialLocation: '/v1/menu/cortex'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('guest_prompt_sign_in')));
        await tester.pumpAndSettle();
        expect(api.launched, hasLength(1));
        final uri = api.launched.single;
        expect('${uri.scheme}://${uri.authority}', ReportsConfig.authBaseUrl);
        expect(uri.path, ReportsConfig.authLoginRoute);
        final key = encrypt.Key.fromBase64(ReportsConfig.appContextFernetKey);
        final context =
            jsonDecode(
                  encrypt.Encrypter(
                    encrypt.Fernet(key),
                  ).decrypt64(uri.queryParameters['app_context']!),
                )
                as Map<String, dynamic>;
        expect(context['name'], 'Reports');
        expect(context['url_app'], 'http://localhost:8110');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('reports_after_login'), '/v1/menu/cortex');
      },
    );

    test('safeNext keeps only internal /v1 paths', () {
      expect(
        AuthRoutes.safeNext('/v1/menu/cortex/model_usage'),
        '/v1/menu/cortex/model_usage',
      );
      for (final bad in [
        null,
        '',
        'https://evil.example',
        '//evil.example',
        '/v1/../x',
        '/sync',
        'javascript:alert(1)',
        '/other',
      ]) {
        expect(AuthRoutes.safeNext(bad), AuthRoutes.menu, reason: '$bad');
      }
    });

    testWidgets('/sync redeems the token once, then opens the stored page', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'reports_after_login': '/v1/menu/cortex',
      });
      api.install(checkSession: true);
      await tester.pumpWidget(
        const ReportsApp(
          initialLocation: '/sync?auth_exchange_token=one-time-1',
        ),
      );
      await tester.pumpAndSettle();
      final exchanges = api.requests
          .where((r) => r.url.path == '/apps/api/v1/exchange')
          .toList();
      expect(exchanges, hasLength(1));
      expect(exchanges.single.method, 'POST');
      expect(jsonDecode(exchanges.single.body), {
        'auth_exchange_token': 'one-time-1',
        'app': 'reports',
      });
      expect(SessionStore.instance.hasSession, isTrue);
      expect(_location(tester), '/v1/menu/cortex');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('reports_after_login'),
        isNull,
        reason: 'the next page is read once',
      );
    });

    testWidgets(
      'a refused token shows a message with a manual button, never a loop',
      (tester) async {
        api.overrides['/apps/api/v1/exchange'] = (req) =>
            _json({'detail': 'expired'}, 400);
        api.install(withSession: false, checkSession: true);
        await tester.pumpWidget(
          const ReportsApp(
            initialLocation: '/sync?auth_exchange_token=one-time-2',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sync_error')), findsOneWidget);
        expect(
          api.launched,
          isEmpty,
          reason: 'nothing opens the login by itself',
        );
        expect(api.calls['/apps/api/v1/exchange'], 1);
        expect(api.telemetry.single['error_type'], 'GATEWAY_400');
        expect(
          api.telemetry.single['message'],
          contains('/apps/api/v1/exchange'),
        );
        expect(
          jsonEncode(api.telemetry),
          isNot(contains('one-time-2')),
          reason: 'no token in telemetry',
        );
        await tester.tap(find.byKey(const Key('auth_action')));
        await tester.pumpAndSettle();
        expect(api.launched, hasLength(1));
      },
    );

    testWidgets('/sync without a token shows the message and calls nothing', (
      tester,
    ) async {
      api.install(withSession: false, checkSession: true);
      await tester.pumpWidget(const ReportsApp(initialLocation: '/sync'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync_error')), findsOneWidget);
      expect(api.calls['/apps/api/v1/exchange'], isNull);
    });

    testWidgets('old login links open the public home', (tester) async {
      api.install(withSession: false);
      await tester.pumpWidget(
        const ReportsApp(initialLocation: '/v1/login-required'),
      );
      await tester.pumpAndSettle();
      expect(_location(tester), AuthRoutes.home);
    });
  });

  group('expired session', () {
    testWidgets('a 401 on a session route shows the guest view once', (
      tester,
    ) async {
      api.withReport('cortex', 'report_1', 2);
      api.overrides['/projects/cortex/reports/report_1'] = (req) =>
          _json({'code': 'session_required'}, 401);
      api.install();
      await tester.pumpWidget(
        const ReportsApp(initialLocation: '/v1/menu/cortex/report_1'),
      );
      await tester.pumpAndSettle();
      expect(SessionStore.instance.hasSession, isFalse);
      expect(api.calls['/projects/cortex/reports/report_1'], 1);
      expect(api.calls['/projects/cortex/showcase/report_1'], 1);
      expect(find.byKey(const Key('session_ended')), findsOneWidget);
      expect(_location(tester), '/v1/menu/cortex/report_1');
      expect(api.launched, isEmpty);
    });
  });

  group('gateway refusal', () {
    testWidgets(
      'a 403 of the gateway without an engine code ends the session like a 401',
      (tester) async {
        api.withReport('cortex', 'report_1', 2);
        api.overrides['/projects/cortex/reports/report_1'] = (req) => _json({
          'message': 'Missing Authentications Parameters...',
          'data': null,
        }, 403);
        api.install();
        await tester.pumpWidget(
          const ReportsApp(initialLocation: '/v1/menu/cortex/report_1'),
        );
        await tester.pumpAndSettle();
        expect(SessionStore.instance.hasSession, isFalse);
        expect(
          api.calls['/projects/cortex/showcase/report_1'],
          1,
          reason: 'the guest view loads',
        );
        expect(find.byKey(const Key('session_ended')), findsOneWidget);
        expect(api.launched, isEmpty);
      },
    );

    test('a 403 of the engine with a code stays an access limit', () {
      const engine = ApiException(
        403,
        '{"code":"forbidden","message":"no access"}',
      );
      const gateway = ApiException(
        403,
        '{"message":"Missing Authentications Parameters...","data":null}',
      );
      expect(engine.accessLimited, isTrue);
      expect(engine.needsLogin, isFalse);
      expect(gateway.needsLogin, isTrue);
      expect(gateway.accessLimited, isFalse);
    });
  });

  group('telemetry', () {
    testWidgets('an engine failure is reported without the query', (
      tester,
    ) async {
      api.overrides['/projects/cortex/reports'] = (req) =>
          _json({'code': 'internal'}, 500);
      api.overrides['/me/projects/cortex/reports'] = (req) =>
          _json({'code': 'internal'}, 500);
      api.install(withSession: false);
      await tester.pumpWidget(
        const ReportsApp(initialLocation: '/v1/menu/cortex'),
      );
      await tester.pumpAndSettle();
      final report = api.telemetry.firstWhere(
        (t) => (t['error_type'] as String).startsWith('REPORTS_'),
      );
      expect(report['app_id'], 'reports');
      expect(report['error_type'], 'REPORTS_500');
      expect(report['message'], contains('/projects/cortex/reports'));
      expect(jsonEncode(report), isNot(contains('page_size')));
    });
  });

  group('sidebar identity and deploy stamp', () {
    testWidgets('shows the name, the email and the role', (tester) async {
      api.install();
      SessionStore.instance.updateInfo(
        name: 'Test Viewer',
        email: 'viewer@example.org',
      );
      await tester.pumpWidget(
        _footerApp(open: true, stamp: '2026-10-22 02:13 ICT'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Viewer'), findsOneWidget);
      expect(find.text('viewer@example.org'), findsOneWidget);
      expect(find.text('Viewer · Asodya'), findsOneWidget);
      expect(find.text('T'), findsOneWidget, reason: 'avatar letter');
      // Only the value: no label next to the stamp.
      final stamp = tester.widget<Text>(find.byKey(const Key('deploy_stamp')));
      expect(stamp.data, '2026-10-22 02:13 ICT');
      expect(find.textContaining('Deploy'), findsNothing);
    });

    testWidgets(
      'without user info the user id shows, and an empty stamp hides',
      (tester) async {
        api.me = {...api.me, 'role': 'super_admin', 'is_super_admin': true};
        api.install();
        await tester.pumpWidget(_footerApp(open: true));
        await tester.pumpAndSettle();
        expect(find.text('u-test'), findsOneWidget);
        expect(find.text('Super admin · Asodya'), findsOneWidget);
        expect(find.byKey(const Key('deploy_stamp')), findsNothing);
      },
    );

    testWidgets(
      'collapsed: only the avatar; no session: no block, the stamp stays',
      (tester) async {
        api.install();
        await tester.pumpWidget(
          _footerApp(open: false, stamp: '2026-10-22 02:13 ICT'),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('identity_avatar')), findsOneWidget);
        expect(find.byKey(const Key('identity_name')), findsNothing);
        expect(find.byKey(const Key('deploy_stamp')), findsNothing);

        SessionStore.instance.setForTest(null);
        await tester.pumpWidget(
          _footerApp(open: true, stamp: '2026-10-22 02:13 ICT'),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('identity_block')), findsNothing);
        expect(find.text('2026-10-22 02:13 ICT'), findsOneWidget);
      },
    );

    testWidgets(
      'Log out revokes the gateway session with the CSRF header, clears the data and opens home',
      (tester) async {
        api.install();
        SharedPreferences.setMockInitialValues({
          'catalog_cache:projects': '{}',
          'other_setting': 'kept',
        });
        CardFilterState.instance.set('cortex', 'r1', 'c1', {'k': 'v'});
        await tester.pumpWidget(_footerApp(open: true));
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('identity_log_out'));
        expect(
          button,
          findsOneWidget,
          reason: 'a visible Log out button, not a hidden menu',
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        final logout = api.requests.singleWhere(
          (r) => r.url.path == '/user/sync/v1/log-out',
        );
        expect(logout.method, 'POST');
        expect(logout.headers['X-CSRF-Token'], 'csrf-test');
        expect(SessionStore.instance.hasSession, isFalse);
        expect(SessionStore.instance.user, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('catalog_cache:projects'), isNull);
        expect(prefs.getString('other_setting'), 'kept');
        expect(CardFilterState.instance.get('cortex', 'r1', 'c1'), isEmpty);
        expect(find.text('public home page'), findsOneWidget);
      },
    );

    testWidgets(
      'Log out still clears the local session when the gateway fails, and reports it',
      (tester) async {
        api.overrides['/user/sync/v1/log-out'] = (req) =>
            http.Response('{"detail":"down"}', 502);
        api.install();
        await tester.pumpWidget(_footerApp(open: false));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('identity_log_out')));
        await tester.pumpAndSettle();
        expect(SessionStore.instance.hasSession, isFalse);
        expect(find.text('public home page'), findsOneWidget);
        expect(api.telemetry.single['error_type'], 'GATEWAY_502');
      },
    );
  });
}
