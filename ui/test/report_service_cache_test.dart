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

  test('derived preview entry carries source timestamp and expires at original TTL', () async {
    final api = FakeApi()..withReport('cortex', 'report_1', 1, prefix: 'a');
    api.install(withSession: false);

    // TTL of 40 milliseconds
    final service = ReportService(ApiClient(client: api.client), ttl: const Duration(milliseconds: 40));

    // Warm up showcase inline dataset with showcaseRows (500)
    await service.dataset('cortex', 'report_1', 'a1', lang: 'en', limit: 500);
    final initialCalls = api.calls['/projects/cortex/showcase/report_1/cards/a1'] ?? 0;

    // Access at t=25ms with smaller limit (10) -> uses inline, caches derived entry with original timestamp
    await Future.delayed(const Duration(milliseconds: 25));
    final previewPage = await service.dataset('cortex', 'report_1', 'a1', lang: 'en', limit: 10);
    expect(previewPage.rows.length, lessThanOrEqualTo(10));
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], equals(initialCalls));

    // Wait 25ms more (total 50ms > original 40ms TTL)
    await Future.delayed(const Duration(milliseconds: 25));

    // Accessing smaller limit now must be expired and refetch from network (not extended to 2*TTL)
    await service.dataset('cortex', 'report_1', 'a1', lang: 'en', limit: 10);
    expect(api.calls['/projects/cortex/showcase/report_1/cards/a1'], greaterThan(initialCalls));
  });

  testWidgets('consumer reload lifecycle demonstrates two different snapshots on dataset update', (tester) async {
    final api = FakeApi();
    // Snapshot 1 has 3 rows per dataset
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 3, prefix: 'd');
    api.install(withSession: false);

    final service = ReportService(ApiClient(client: api.client));

    // First snapshot access: returns 3 rows
    final page1 = await service.dataset('cortex', 'report_1', 'd1', lang: 'en');
    expect(page1.rows.length, equals(3));

    // Producer data changes on server (Snapshot 2 with 5 rows)
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 5, prefix: 'd');

    // Before reload/invalidation: cached service still returns Snapshot 1
    final cachedPage = await service.dataset('cortex', 'report_1', 'd1', lang: 'en');
    expect(cachedPage.rows.length, equals(3));

    // Invalidate / forceRefresh reload lifecycle invoked
    service.invalidateDataset('cortex', 'report_1', 'd1');

    // Next consumer access receives fresh Snapshot 2 with 5 rows
    final page2 = await service.dataset('cortex', 'report_1', 'd1', lang: 'en');
    expect(page2.rows.length, equals(5));
    expect(page2.rows.length, isNot(equals(page1.rows.length)));
  });
}
