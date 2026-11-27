import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/report_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dataset cache respects TTL and refetches on next access after expiration', () async {
    final api = FakeApi()..withReport('cortex', 'report_1', 1, prefix: 'a');
    api.install(withSession: false);

    // ReportService with a very short TTL (20 milliseconds)
    final service = ReportService(ApiClient(client: api.client), ttl: const Duration(milliseconds: 20));

    // Initial access: fetches from server (via showcase or direct card endpoint)
    final page1 = await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    expect(page1.rows, isNotEmpty);
    final initialCalls = api.calls['/projects/cortex/showcase/report_1/cards/a1'] ?? 0;
    expect(initialCalls, greaterThanOrEqualTo(1));

    // Access within TTL: returns cached page without hitting network
    final page2 = await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    expect(page2.rows, equals(page1.rows));
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], equals(initialCalls));

    // Wait for TTL to expire
    await Future.delayed(const Duration(milliseconds: 30));

    // Next supported access after TTL: re-fetches fresh data from server
    final page3 = await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    expect(page3.rows, equals(page1.rows));
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], greaterThan(initialCalls));
  });

  test('forceRefresh bypasses cache and re-fetches immediately', () async {
    final api = FakeApi()..withReport('cortex', 'report_1', 1, prefix: 'a');
    api.install(withSession: false);

    final service = ReportService(ApiClient(client: api.client), ttl: const Duration(minutes: 5));

    await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    final callsBefore = api.calls['/projects/cortex/showcase/report_1/cards/a1'] ?? 0;

    // Normal access uses cache
    await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], equals(callsBefore));

    // forceRefresh: true fetches new data
    await service.dataset('cortex', 'report_1', 'a1', lang: 'en', forceRefresh: true);
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], greaterThan(callsBefore));
  });

  test('invalidate removes cached dataset so next access re-fetches', () async {
    final api = FakeApi()..withReport('cortex', 'report_1', 1, prefix: 'a');
    api.install(withSession: false);

    final service = ReportService(ApiClient(client: api.client), ttl: const Duration(minutes: 5));

    await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    final callsBefore = api.calls['/projects/cortex/showcase/report_1/cards/a1'] ?? 0;

    service.invalidateDataset('cortex', 'report_1', 'a1');

    await service.dataset('cortex', 'report_1', 'a1', lang: 'en');
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], greaterThan(callsBefore));
  });
}
