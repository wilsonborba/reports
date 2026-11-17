import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/services/client_telemetry_service.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late http.Client client;

  setUp(() {
    sent = [];
    client = MockClient((req) async {
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 202);
    });
  });

  test('view and error keep the gateway URLs and payload contract', () async {
    final requests = <http.Request>[];
    final telemetry = ClientTelemetryService(
      endpoint: 'https://gateway.example/apps/api/v1/telemetry/errors',
      appVersion: '3.1.1',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 202);
      }),
    );
    final tracker = telemetry.tracker;
    addTearDown(() => telemetry.detach(tracker));
    tracker.view('/v1/home?private=value');
    await telemetry.reportError(
      errorTitle: 'Service failure',
      errorMessage: 'HTTP 500',
      errorCode: 'REPORTS_500',
      route: '/v1/home?private=value',
    );
    expect(requests.map((r) => r.url.toString()), [
      'https://gateway.example/apps/api/v1/telemetry/events',
      'https://gateway.example/apps/api/v1/telemetry/errors',
    ]);
    for (final request in requests) {
      expect(request.method, 'POST');
      expect(request.headers['content-type'], 'application/json');
    }
    final view = jsonDecode(requests.first.body) as Map<String, dynamic>;
    final session = view['session_id'];
    expect(session, isA<String>());
    expect(view, {
      'app_id': 'reports',
      'session_id': session,
      'locale': 'en',
      'theme': 'system',
      'viewport_width': 0,
      'viewport_height': 0,
      'events': [
        {
          'seq': 0,
          'event_type': 'view',
          'screen': 'overview',
          'route': '/v1/home',
          'path': '/v1/home',
          'element_id': 'overview.surface',
          'element_label': 'Reports overview',
          'element_path': 'overview > surface',
          'value': null,
          'sensitive': false,
        },
      ],
    });
    expect(jsonDecode(requests.last.body), {
      'app_id': 'reports',
      'session_id': session,
      'route': '/v1/home',
      'error_type': 'REPORTS_500',
      'message': 'Service failure: HTTP 500',
      'stack': '',
      'build_version': '3.1.1',
    });
  });

  test(
    'a service failure names Reports, version and the current page',
    () async {
      final telemetry = ClientTelemetryService(
        client: client,
        appVersion: '3.1.1',
        environment: 'production',
        currentRoute: () => '/v1/menu/cortex/model-usage',
      );
      await telemetry.reportServiceFailure(
        service: 'reports',
        method: 'GET',
        path: '/projects/cortex/reports?page_size=100',
        status: 500,
      );
      final report = sent.single;
      expect(report['app_id'], 'reports');
      expect(report['build_version'], '3.1.1');
      expect(report.containsKey('environment'), isFalse);
      expect(report['route'], '/v1/menu/cortex/model-usage');
      expect(report['message'], contains('/projects/cortex/reports'));
      expect(
        jsonEncode(report),
        isNot(contains('page_size')),
        reason: 'no query in the report',
      );
    },
  );

  test('an explicit route wins over the current page', () async {
    final telemetry = ClientTelemetryService(
      client: client,
      currentRoute: () => '/v1/home',
    );
    await telemetry.reportError(
      errorTitle: 'boom',
      errorMessage: 'boom',
      route: '/v1/sync',
    );
    expect(sent.single['route'], '/v1/sync');
  });

  test('the same error is sent once inside the throttle window', () async {
    final telemetry = ClientTelemetryService(
      client: client,
      currentRoute: () => '/v1/home',
    );
    await telemetry.reportError(errorTitle: 'boom', errorMessage: 'boom');
    await telemetry.reportError(errorTitle: 'boom', errorMessage: 'boom');
    expect(sent, hasLength(1));
  });

  test('a failing telemetry endpoint never throws', () async {
    final telemetry = ClientTelemetryService(
      client: MockClient((req) async => throw Exception('offline')),
      currentRoute: () => null,
    );
    await expectLater(
      telemetry.reportError(errorTitle: 'boom', errorMessage: 'boom'),
      completes,
    );
  });
}
