import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/views/embed_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

Map<String, dynamic> _descriptorFor(Map<String, String> query) {
  final language = query['lang'] ?? 'en';
  final portuguese = language == 'pt-BR';
  final thai = language == 'th';
  return {
    'dataset_id': 'values',
    'title': portuguese
        ? 'Valores numéricos'
        : thai
        ? 'ค่าตัวเลข'
        : 'Numeric values',
    'description': 'Synthetic locale fixture',
    'equation': null,
    'fields': [
      {
        'name': 'label',
        'label': portuguese
            ? 'Rótulo'
            : thai
            ? 'ป้ายกำกับ'
            : 'Label',
        'type': 'string',
        'role': 'dimension',
      },
      {
        'name': 'amount',
        'label': portuguese
            ? 'Valor'
            : thai
            ? 'จำนวน'
            : 'Amount',
        'type': 'float',
        'role': 'measure',
        'decimals': 1,
      },
    ],
    'filters': [],
  };
}

FakeApi _installNumericReport() {
  final api = FakeApi().withReport('cortex', 'locale', 1, rowsPerDataset: 1);
  for (final path in [
    '/projects/cortex/reports/locale',
    '/projects/cortex/showcase/locale',
  ]) {
    final original = api.routes[path]!;
    api.routes[path] = (query) {
      final body = original(query);
      if (body.containsKey('datasets')) {
        body['datasets'] = [_descriptorFor(query)];
      }
      if (body.containsKey('cards')) {
        body['cards'] = [
          {
            'dataset_id': 'values',
            'title': _descriptorFor(query)['title'],
            'visibility': 'public',
            'data_tier': 'sample',
            'can_view': true,
            'descriptor': _descriptorFor(query),
          },
        ];
      }
      return body;
    };
  }
  Map<String, dynamic> page(Map<String, String> query) => {
    ..._descriptorFor(query),
    'language': query['lang'] ?? 'en',
    'rows': [
      {
        'label': query['lang'] == 'pt-BR'
            ? 'Exemplo'
            : query['lang'] == 'th'
            ? 'ตัวอย่าง'
            : 'Example',
        'amount': 1234.5,
      },
    ],
    'offset': 0,
    'limit': 500,
    'total_rows': 1,
    'applied_filters': <String, Object>{},
  };
  api.routes['/projects/cortex/reports/locale/datasets/values'] = page;
  api.routes['/projects/cortex/showcase/locale/cards/values'] = page;
  api.install(withSession: false);
  LayoutRegistry.visuals['cortex/locale/values'] = const Slot(
    'values',
    visual: Visual.table,
  );
  return api;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => LayoutRegistry.visuals.remove('cortex/locale/values'));

  testWidgets('ReportsApp language reaches chart numbers and updates live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _installNumericReport();

    await tester.pumpWidget(
      const ReportsApp(initialLocation: '/v1/menu/cortex/locale'),
    );
    await tester.pumpAndSettle();
    expect(find.text('1,234.5'), findsOneWidget);

    final context = tester.element(find.text('1,234.5'));
    final language = LanguageScope.of(context);
    await language.set(AppLanguage.pt);
    await tester.pumpAndSettle();

    final ptNumber = find.text('1.234,5');
    expect(ptNumber, findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(ptNumber)),
      const Locale('pt', 'BR'),
    );
    expect(
      api.requests
          .where((request) => request.url.path.contains('/values'))
          .map((request) => request.url.queryParameters['lang']),
      contains('pt-BR'),
    );

    await language.set(AppLanguage.th);
    await tester.pumpAndSettle();
    final thaiNumber = find.text('1,234.5');
    expect(thaiNumber, findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(thaiNumber)),
      const Locale('th'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('embed query locales stay independent in sibling subtrees', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _installNumericReport();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        supportedLocales: reportsSupportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeRegistry.theme('cortex', Brightness.light),
        home: const Scaffold(
          body: Row(
            children: [
              Expanded(
                child: EmbedView(
                  key: ValueKey('pt-embed'),
                  project: 'cortex',
                  report: 'locale',
                  dataset: 'values',
                  language: 'pt-BR',
                  query: {'view': 'table'},
                ),
              ),
              Expanded(
                child: EmbedView(
                  key: ValueKey('en-embed'),
                  project: 'cortex',
                  report: 'locale',
                  dataset: 'values',
                  language: 'en',
                  query: {'view': 'table'},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ptHeading = find.text('Valores numéricos');
    final enHeading = find.text('Numeric values');
    expect(ptHeading, findsOneWidget);
    expect(enHeading, findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(ptHeading)),
      const Locale('pt', 'BR'),
    );
    expect(
      Localizations.localeOf(tester.element(enHeading)),
      const Locale('en'),
    );
    final valueRequests = api.requests.where(
      (request) => request.url.path.contains('/values'),
    );
    expect(
      valueRequests.map((request) => request.url.queryParameters['lang']),
      containsAll(['pt-BR', 'en']),
    );
    expect(tester.takeException(), isNull);
  });
}
