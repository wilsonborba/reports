import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/report_service.dart';
import 'package:reports_ui/themes/reports_theme.dart';
import 'package:reports_ui/views/embed_view.dart';
import 'package:reports_ui/widgets/report/dataset_slot.dart';
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
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 3, prefix: 'd');
    api.install(withSession: false);

    var query = {'view': 'table'};
    late StateSetter updateState;

    await tester.pumpWidget(
      MaterialApp(
        theme: ReportsTheme.palette(Brightness.light).toTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;
            return Scaffold(
              body: EmbedView(
                key: const Key('embed_consumer'),
                project: 'cortex',
                report: 'report_1',
                dataset: 'd1',
                language: 'en',
                query: query,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Snapshot 1 (3 rows): row 12 exists, row 14 does not exist
    expect(find.text('12'), findsOneWidget);
    expect(find.text('14'), findsNothing);

    // Producer data changes on server to Snapshot 2 (5 rows)
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 5, prefix: 'd');

    // Trigger reload lifecycle via consumer update (changed query parameter)
    updateState(() {
      query = {'view': 'table', 'reload': '1'};
    });
    await tester.pumpAndSettle();

    // Snapshot 2 (5 rows): row 14 is now visible without manual test-only cache invalidation!
    expect(find.text('14'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('DatasetSlot didUpdateWidget reloads with forceRefresh when view changes', (tester) async {
    final api = FakeApi();
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 3, prefix: 'd');
    api.install(withSession: false);

    final service = ReportService(ApiClient(client: api.client));
    final viewA = await service.report('cortex', 'report_1', lang: 'en');

    var currentView = viewA;
    late StateSetter updateState;

    await tester.pumpWidget(
      MaterialApp(
        theme: ReportsTheme.palette(Brightness.light).toTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;
            return Scaffold(
              body: DatasetSlot(
                key: const Key('slot_consumer'),
                project: 'cortex',
                report: 'report_1',
                slot: const Slot('d1', visual: Visual.table),
                view: currentView,
                language: 'en',
                initialTable: true,
                service: service,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsOneWidget);
    expect(find.text('14'), findsNothing);

    // Producer updates on server
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 5, prefix: 'd');

    // Force load fresh report view from service
    final viewB = await service.report('cortex', 'report_1', lang: 'en', forceRefresh: true);

    // Pass new view into existing DatasetSlot widget
    updateState(() {
      currentView = viewB;
    });
    await tester.pumpAndSettle();

    // Row 14 is now visible through DatasetSlot reload lifecycle!
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('consumer error retry button refetches dataset and recovers', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 3, prefix: 'd');
    api.routes['/projects/cortex/showcase/report_1/cards/d1'] = (_) => throw StateError('simulated server outage');
    api.install(withSession: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: ReportsTheme.palette(Brightness.light).toTheme(Brightness.light),
        home: const Scaffold(
          body: EmbedView(
            key: Key('embed_error_test'),
            project: 'cortex',
            report: 'report_1',
            dataset: 'd1',
            language: 'en',
            query: {'view': 'table'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Error UI and retry button are visible
    expect(find.byKey(const Key('card_error_retry')), findsOneWidget);

    // Outage resolved on server
    api.withReport('cortex', 'report_1', 1, rowsPerDataset: 3, prefix: 'd');

    // Tap retry button
    await tester.tap(find.byKey(const Key('card_error_retry')));
    await tester.pumpAndSettle();

    // Error is gone, data table with row 12 is visible!
    expect(find.byKey(const Key('card_error_retry')), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });
}
