import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/services/client_telemetry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void main() {
  test('manifest names all declared Reports identities', () {
    final manifest =
        jsonDecode(File('tracking_manifest.json').readAsStringSync()) as Map;
    final entries = (manifest['elements'] as List).cast<Map<String, dynamic>>();
    expect(entries.length, reportElements.length);
    for (final entry in entries) {
      final element = reportElements[entry['id']]!;
      expect(element.valid, isTrue);
      expect(element.label, entry['label']);
      expect(element.path, entry['path']);
      expect(entry['description'], isNotEmpty);
    }
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final match in RegExp(
        r"track\(\s*'([^']+)'",
      ).allMatches(file.readAsStringSync())) {
        if (match[1]!.contains(r'${')) continue;
        expect(reportElements.containsKey(match[1]), isTrue, reason: file.path);
      }
    }
  });
  testWidgets('unchanged header and report search produce mapped events', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FakeApi().install();
    final requests = <Map<String, dynamic>>[];
    final telemetry = ClientTelemetryService(
      client: MockClient((r) async {
        requests.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response('{}', 202);
      }),
    );
    ClientTelemetryService.instance = telemetry;
    await tester.pumpWidget(
      const ReportsApp(
        initialLocation: '/v1/menu/cortex?auth_exchange_token=private-artifact',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top_bar_theme')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('report_search')), 'RAG');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lang_pt-BR')));
    await tester.pumpAndSettle();
    await telemetry.tracker.flush();
    final batches = requests.where((v) => v.containsKey('events')).toList();
    final events = batches
        .expand((v) => (v['events'] as List).cast<Map<String, dynamic>>())
        .toList();
    expect(
      events.any(
        (v) =>
            v['event_type'] == 'click' &&
            v['element_id'] == 'shell.theme.toggle',
      ),
      isTrue,
    );
    expect(
      events.any(
        (v) =>
            v['event_type'] == 'input' &&
            v['element_id'] == 'catalog.report.search' &&
            v['value'] == 'RAG',
      ),
      isTrue,
    );
    expect(
      events.any(
        (v) =>
            v['event_type'] == 'click' &&
            v['element_id'] == 'shell.language.portuguese',
      ),
      isTrue,
    );
    expect(batches.last['locale'], 'pt-BR');
    expect(jsonEncode(requests), isNot(contains('private-artifact')));
    await tester.pumpWidget(const SizedBox());
  });
}
