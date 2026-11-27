// Cache-only focused behavior repro. No screenshots or live services.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/export/artifact_jobs.dart';
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/export/report_artifacts.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/services/auth_service.dart';
import 'package:reports_ui/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/client_telemetry_service.dart';
import 'package:reports_ui/services/report_service.dart';
import 'package:reports_ui/services/session_store.dart';

void main() {
  testWidgets('review mounted full view clears personal rows on session expiry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);
    final previousSession = SessionStore.instance;
    final previousTelemetry = ClientTelemetryService.instance;
    final previousReport = ReportService.instance;
    final previousCatalog = CatalogService.instance;
    final previousAuth = AuthService.instance;
    final catalogFixture = FakeApi();
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'app_theme_mode': 'light',
    });
    final calls = <String>[], unexpected = <String>[];
    final descriptor = <String, Object?>{
      'dataset_id': 'secret',
      'title': 'Private fixture dataset',
      'description': 'Owner-only test sample',
      'equation': null,
      'data_tier': 'real',
      'can_view': true,
      'visibility': 'restricted',
      'fields': [
        {
          'name': 'label',
          'label': 'Label',
          'type': 'string',
          'role': 'dimension',
          'missing_means': 'no_data',
        },
        {
          'name': 'value',
          'label': 'Value',
          'type': 'integer',
          'role': 'measure',
          'unit': 'tokens',
          'missing_means': 'no_data',
        },
      ],
      'filters': <Object?>[],
    };
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method != 'GET') {
        unexpected.add(calls.last);
        throw StateError('Unexpected mutation');
      }
      var path = request.url.path;
      if (path.startsWith(FakeApi.prefix)) {
        path = path.substring(FakeApi.prefix.length);
      }
      if (path == '/user/info/v1/') {
        return http.Response(
          jsonEncode({
            'data': {'full_name': 'Review owner'},
          }),
          200,
        );
      }
      if (const {
        '/catalog',
        '/projects',
        '/stats',
        '/projects/cortex',
        '/projects/cortex/reports',
      }.contains(path)) {
        Object? clean(Object? value) {
          if (value is Map) {
            return {
              for (final e in value.entries)
                if (e.key != 'cover_url') e.key: clean(e.value),
            };
          }
          if (value is List) return value.map(clean).toList();
          return value;
        }

        return http.Response(
          jsonEncode(
            clean(catalogFixture.routes[path]!(request.url.queryParameters)),
          ),
          200,
        );
      }
      if (path == '/me/projects/cortex/reports' &&
          SessionStore.instance.hasSession) {
        return http.Response(
          jsonEncode(
            catalogFixture.routes['/projects/cortex/reports']!(
              request.url.queryParameters,
            ),
          ),
          200,
        );
      }
      if (path == '/me/items/secret') {
        return http.Response(jsonEncode({'code': 'forbidden'}), 403);
      }
      if (path == '/projects/cortex/reports/private' &&
          SessionStore.instance.hasSession) {
        return http.Response(
          jsonEncode({
            'project': 'cortex',
            'report': 'private',
            'title': 'Owner private report',
            'description': '',
            'tags': <String>[],
            'period': null,
            'updated_at': '2026-11-27T00:00:00Z',
            'language': 'en',
            'data_tier': 'real',
            'tiers': ['real'],
            'visibility': 'restricted',
            'access': {
              'total': 1,
              'readable': 1,
              'needs_sign_in': 0,
              'needs_admin': 0,
            },
            'datasets': [descriptor],
          }),
          200,
        );
      }
      if (path == '/projects/cortex/reports/private/datasets/secret' &&
          SessionStore.instance.hasSession) {
        return http.Response(
          jsonEncode({
            ...descriptor,
            'language': 'en',
            'rows': [
              {'label': 'A_PRIVATE_ROW_ONLY', 'value': 10},
            ],
            'offset': 0,
            'limit': 1000,
            'total_rows': 1,
            'applied_filters': <String, Object?>{},
            'lineage': {
              'calculation_id': 'private-fixture',
              'calculation_version': 1,
              'inputs': <Object?>[],
              'source_watermark': <String, Object?>{},
              'filters': <String, Object?>{},
              'calculated_at': '2026-11-27T00:00:00Z',
            },
            'visual': null,
          }),
          200,
        );
      }
      if (path == '/projects/cortex/showcase/private' ||
          path == '/projects/cortex/showcase/private/cards/secret') {
        return http.Response(jsonEncode({'code': 'not_found'}), 404);
      }
      unexpected.add(calls.last);
      throw StateError('Unexpected request ${calls.last}');
    });
    final telemetryClient = MockClient((request) async {
      unexpected.add('telemetry ${request.method} ${request.url.path}');
      throw StateError('No telemetry delivery');
    });
    addTearDown(client.close);
    addTearDown(telemetryClient.close);
    final api = ApiClient(
      baseUrl: FakeApi.base,
      client: client,
      cookieReader: (_) => null,
    );
    final session = SessionStore(api: api, cookieReader: (_) => null);
    SessionStore.instance = session;
    session.setForTest(
      const SessionUser(userId: '11111111-1111-4111-8111-111111111111'),
    );
    ClientTelemetryService.instance = ClientTelemetryService(
      client: telemetryClient,
      autoFlush: false,
      environment: 'isolated-review',
    );
    await http.runWithClient(() async {
      try {
        ReportService.instance = ReportService(api);
        CatalogService.instance = CatalogService(api);
        AuthService.instance = AuthService(
          client: client,
          cookieReader: (_) => null,
          launcher: (_) async => throw StateError('No external auth'),
        );
        await tester.pumpWidget(
          const ReportsApp(
            initialLocation: '/v1/menu/cortex/private/secret?view=table',
          ),
        );
        await tester.pumpAndSettle();
        expect(unexpected, isEmpty);
        expect(find.text('A_PRIVATE_ROW_ONLY'), findsOneWidget);
        expect(
          calls.any((call) => call.endsWith('/me/items/secret')),
          isTrue,
          reason:
              'Actual route default ApiClient must remain inside strict in-process client zone',
        );
        // Actual expiry path: keep the current widget mounted, rather than using
        // the explicit logout helper which clears caches and navigates home.
        session.markExpired();
        await tester.pumpAndSettle();
        expect(session.hasSession, isFalse);
        expect(unexpected, isEmpty);
        expect(
          find.text('A_PRIVATE_ROW_ONLY'),
          findsNothing,
          reason:
              'Personal table rows must disappear when this mounted view becomes a guest. Requests: $calls',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        SessionStore.instance = previousSession;
        ReportService.instance = previousReport;
        CatalogService.instance = previousCatalog;
        AuthService.instance = previousAuth;
        ClientTelemetryService.instance = previousTelemetry;
      }
    }, () => client);
  });

  testWidgets('delayed old-scope response in full view is fenced', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);
    final previousSession = SessionStore.instance;
    final previousTelemetry = ClientTelemetryService.instance;
    final previousReport = ReportService.instance;
    final previousCatalog = CatalogService.instance;
    final previousAuth = AuthService.instance;
    final catalogFixture = FakeApi();
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'app_theme_mode': 'light',
    });
    final descriptor = <String, Object?>{
      'dataset_id': 'secret',
      'title': 'Private fixture dataset',
      'description': 'Owner-only test sample',
      'equation': null,
      'data_tier': 'real',
      'can_view': true,
      'visibility': 'restricted',
      'fields': [
        {
          'name': 'label',
          'label': 'Label',
          'type': 'string',
          'role': 'dimension',
          'missing_means': 'no_data',
        },
        {
          'name': 'value',
          'label': 'Value',
          'type': 'integer',
          'role': 'measure',
          'unit': 'tokens',
          'missing_means': 'no_data',
        },
      ],
      'filters': <Object?>[],
    };
    Completer<http.Response>? guestCompleter;
    final client = MockClient((request) async {
      var path = request.url.path;
      if (path.startsWith(FakeApi.prefix)) {
        path = path.substring(FakeApi.prefix.length);
      }
      if (path == '/user/info/v1/') {
        return http.Response(
          jsonEncode({
            'data': {'full_name': 'Review owner'},
          }),
          200,
        );
      }
      if (const {
        '/catalog',
        '/projects',
        '/stats',
        '/projects/cortex',
        '/projects/cortex/reports',
      }.contains(path)) {
        return http.Response(
          jsonEncode(catalogFixture.routes[path]!(request.url.queryParameters)),
          200,
        );
      }
      if (path == '/me/projects/cortex/reports' &&
          SessionStore.instance.hasSession) {
        return http.Response(
          jsonEncode(
            catalogFixture.routes['/projects/cortex/reports']!(
              request.url.queryParameters,
            ),
          ),
          200,
        );
      }
      if (path == '/me/items/secret') {
        return http.Response(jsonEncode({'code': 'forbidden'}), 403);
      }
      if (path == '/projects/cortex/reports/private') {
        if (!SessionStore.instance.hasSession) {
          if (guestCompleter != null) {
            return await guestCompleter!.future;
          }
          return http.Response(jsonEncode({'code': 'forbidden'}), 403);
        }
        return http.Response(
          jsonEncode({
            'project': 'cortex',
            'report': 'private',
            'title': 'Owner private report',
            'description': '',
            'tags': <String>[],
            'period': null,
            'updated_at': '2026-11-27T00:00:00Z',
            'language': 'en',
            'data_tier': 'real',
            'tiers': ['real'],
            'visibility': 'restricted',
            'access': {
              'total': 1,
              'readable': 1,
              'needs_sign_in': 0,
              'needs_admin': 0,
            },
            'datasets': [descriptor],
          }),
          200,
        );
      }
      if (path == '/projects/cortex/reports/private/datasets/secret') {
        if (!SessionStore.instance.hasSession) {
          return http.Response(jsonEncode({'code': 'forbidden'}), 403);
        }
        return http.Response(
          jsonEncode({
            ...descriptor,
            'language': 'en',
            'rows': [
              {'label': 'A_PRIVATE_ROW_ONLY', 'value': 10},
            ],
            'offset': 0,
            'limit': 1000,
            'total_rows': 1,
            'applied_filters': <String, Object?>{},
            'lineage': {
              'calculation_id': 'private-fixture',
              'calculation_version': 1,
              'inputs': <Object?>[],
              'source_watermark': <String, Object?>{},
              'filters': <String, Object?>{},
              'calculated_at': '2026-11-27T00:00:00Z',
            },
            'visual': null,
          }),
          200,
        );
      }
      if (path == '/projects/cortex/showcase/private' ||
          path == '/projects/cortex/showcase/private/cards/secret') {
        return http.Response(jsonEncode({'code': 'not_found'}), 404);
      }
      return http.Response('{}', 200);
    });
    final telemetryClient = MockClient((request) async {
      return http.Response('{}', 202);
    });
    addTearDown(client.close);
    addTearDown(telemetryClient.close);
    final api = ApiClient(
      baseUrl: FakeApi.base,
      client: client,
      cookieReader: (_) => null,
    );
    final session = SessionStore(api: api, cookieReader: (_) => null);
    SessionStore.instance = session;
    session.setForTest(
      const SessionUser(userId: '11111111-1111-4111-8111-111111111111'),
    );
    ClientTelemetryService.instance = ClientTelemetryService(
      client: telemetryClient,
      autoFlush: false,
      environment: 'isolated-review',
    );
    await http.runWithClient(() async {
      try {
        ReportService.instance = ReportService(api);
        CatalogService.instance = CatalogService(api);
        AuthService.instance = AuthService(
          client: client,
          cookieReader: (_) => null,
          launcher: (_) async => throw StateError('No external auth'),
        );
        await tester.pumpWidget(
          const ReportsApp(
            initialLocation: '/v1/menu/cortex/private/secret?view=table',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A_PRIVATE_ROW_ONLY'), findsOneWidget);
        expect(find.text('Private fixture dataset'), findsWidgets);

        // Prepare held guest response to simulate slow in-flight replacement
        guestCompleter = Completer<http.Response>();
        session.markExpired();

        // Pump single frame to transition state; guest request is now in-flight
        await tester.pump();

        // While replacement guest request is in-flight, private row and title must disappear immediately
        expect(find.text('A_PRIVATE_ROW_ONLY'), findsNothing);
        expect(find.text('Private fixture dataset'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets);

        // Release the held guest response (403 forbidden)
        guestCompleter!.complete(
          http.Response(jsonEncode({'code': 'forbidden'}), 403),
        );
        await tester.pumpAndSettle();

        expect(session.hasSession, isFalse);
        expect(find.text('A_PRIVATE_ROW_ONLY'), findsNothing);
        expect(find.text('Private fixture dataset'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        SessionStore.instance = previousSession;
        ReportService.instance = previousReport;
        CatalogService.instance = previousCatalog;
        AuthService.instance = previousAuth;
        ClientTelemetryService.instance = previousTelemetry;
      }
    }, () => client);
  });

  test('report artifacts abort immediately if session scope changes', () async {
    final api = ApiClient(baseUrl: FakeApi.base, client: MockClient((_) async => http.Response('{}', 200)));
    final session = SessionStore(api: api, cookieReader: (_) => null);
    SessionStore.instance = session;
    session.setForTest(
      const SessionUser(userId: '11111111-1111-4111-8111-111111111111'),
    );
    final artifacts = ReportArtifacts(
      project: 'cortex',
      report: 'private',
      language: () => 'en',
      sectionNames: () => const {},
    );
    session.markExpired();
    expect(
      () => artifacts.run(ArtifactFormat.csv, (_) {}),
      throwsA(isA<Exception>()),
      reason: 'Export must abort when session scope changes or expires',
    );
  });

  test('artifact jobs suppress save callback when scope changes mid-export or job is disposed', () async {
    final api = ApiClient(baseUrl: FakeApi.base, client: MockClient((_) async => http.Response('{}', 200)));
    final session = SessionStore(api: api, cookieReader: (_) => null);
    SessionStore.instance = session;
    session.setForTest(
      const SessionUser(userId: '11111111-1111-4111-8111-111111111111'),
    );

    final exportCompleter = Completer<ExportFile>();
    final savedFiles = <ExportFile>[];
    final jobs = ArtifactJobs(
      runner: (_, _) => exportCompleter.future,
      save: (f) => savedFiles.add(f),
    );

    // Start export
    unawaited(jobs.start(ArtifactFormat.csv, preparing: 'Preparing CSV'));
    expect(jobs.busy, isTrue);

    // Session expires while export is running mid-encode
    session.markExpired();

    // Export completes and returns valid file
    exportCompleter.complete(
      ExportFile('test.csv', Uint8List.fromList([1, 2, 3]), 'text/csv'),
    );
    await Future<void>.delayed(Duration.zero);

    // The save callback must never be invoked
    expect(savedFiles, isEmpty, reason: 'Save callback must never be invoked after scope transition');
    expect(jobs.job(ArtifactFormat.csv).state, isNot(ArtifactState.saved));
  });
}
