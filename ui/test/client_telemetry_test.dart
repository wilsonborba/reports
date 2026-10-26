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
