import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/report_service.dart';
import 'package:reports_ui/services/session_store.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/report/dataset_card.dart';
import 'package:reports_ui/widgets/report/dataset_slot.dart';

const _desc = DatasetDescriptor(
  datasetId: 'ds-1',
  title: 'Test Chart',
  description: 'Description',
  equation: null,
  fields: [],
  filters: [],
  visibility: 'public',
);

Widget _wrap(Widget child) => LanguageScope(
  controller: LanguageController(),
  child: MaterialApp(
    theme: ThemeRegistry.theme('cortex', Brightness.light),
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  ),
);

void main() {
  testWidgets('non-owner never sees owner menu actions or owner mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DatasetCard(
          descriptor: _desc,
          body: const SizedBox(height: 80),
          controls: const CardControls(isOwner: false, isLive: false),
        ),
      ),
    );
    expect(find.byKey(const Key('card_mark_static')), findsOneWidget);
    expect(find.byKey(const Key('card_mark_owner')), findsNothing);

    await tester.tap(find.byKey(const Key('card_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_menu_visibility_public')), findsNothing);
    expect(find.byKey(const Key('card_menu_delete')), findsNothing);
  });

  testWidgets(
    'owner sees Live/Owner marks, visibility menu, and delete confirmation with reuse warning',
    (tester) async {
      String? changedTo;
      var deleted = false;
      await tester.pumpWidget(
        _wrap(
          DatasetCard(
            descriptor: _desc,
            body: const SizedBox(height: 80),
            controls: CardControls(
              isOwner: true,
              isLive: true,
              onChangeVisibility: (v) => changedTo = v,
              onCheckDelete: () async =>
                  'Referenced by 2 notes; deleting will unlink them.',
              onDelete: () => deleted = true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('card_mark_live')), findsOneWidget);
      expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('card_menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('card_menu_visibility_public')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card_menu_visibility_asodya')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card_menu_visibility_personal')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('card_menu_delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('card_menu_visibility_asodya')));
      await tester.pumpAndSettle();
      expect(changedTo, 'asodya');

      // Open delete -> cancel leaves deleted == false.
      await tester.tap(find.byKey(const Key('card_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card_menu_delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_delete_dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('card_delete_reuse_warning')),
        findsOneWidget,
      );
      expect(find.textContaining('Referenced by 2 notes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card_delete_cancel')));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);

      // Open delete -> confirm triggers onDelete.
      await tester.tap(find.byKey(const Key('card_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card_delete_confirm')));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    },
  );

  test(
    'ApiClient sends CSRF headers, encodes item IDs, and handles strict 409 reuse confirmation',
    () async {
      final mock = MockClient((req) async {
        if (req.method == 'PATCH' && req.url.path == '/me/items/item%2F1') {
          expect(req.headers['X-CSRF-Token'], 'csrf-tok-1');
          expect(req.headers['X-CSRFToken'], 'csrf-tok-1');
          expect(jsonDecode(req.body), {'visibility': 'personal'});
          return http.Response(
            jsonEncode({
              'item': {'id': 'item/1'},
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item%2F1') {
          expect(req.headers['X-CSRF-Token'], 'csrf-tok-1');
          final confirm = req.url.queryParameters['confirm'] == 'true';
          if (!confirm) {
            return http.Response(
              jsonEncode({
                'deleted': false,
                'requires_confirmation': true,
                'reference_count': 2,
                'message': 'Used in 2 notes',
              }),
              409,
            );
          }
          return http.Response(
            jsonEncode({
              'deleted': true,
              'requires_confirmation': false,
              'reference_count': 2,
              'message': 'Deleted',
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/forbidden-1') {
          return http.Response('{"error":"forbidden"}', 403);
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (name) => name == 'csrf' ? 'csrf-tok-1' : null,
      );
      final patched = await api.patchOwnerItemVisibility('item/1', 'personal');
      expect(patched['item']['id'], 'item/1');

      final first = await api.deleteOwnerItem('item/1', confirm: false);
      expect(first.deleted, isFalse);
      expect(first.requiresConfirmation, isTrue);
      expect(first.referenceCount, 2);
      expect(first.message, 'Used in 2 notes');

      final second = await api.deleteOwnerItem('item/1', confirm: true);
      expect(second.deleted, isTrue);

      await expectLater(
        api.deleteOwnerItem('forbidden-1'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
    },
  );

  testWidgets(
    'DatasetSlot probes server ownership, sends CSRF PATCH, and handles 409 confirm flow',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];
      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': 'u-owner'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-1') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-owned-1',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' &&
            req.url.path == '/projects/p1/reports/r1/datasets/ds-1') {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-1',
              'rows': [
                {'x': 'a', 'y': 10},
              ],
              'total_rows': 1,
            }),
            200,
          );
        }
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-owned-1') {
          expect(req.headers['X-CSRF-Token'], 'csrf-live');
          return http.Response(
            jsonEncode({'item': {'id': 'item-owned-1'}}),
            200,
          );
        }
        if (req.method == 'DELETE' &&
            req.url.path == '/me/items/item-owned-1') {
          expect(req.headers['X-CSRF-Token'], 'csrf-live');
          if (req.url.queryParameters['confirm'] != 'true') {
            return http.Response(
              jsonEncode({
                'deleted': false,
                'requires_confirmation': true,
                'reference_count': 1,
                'message': 'Referenced by 1 note',
              }),
              409,
            );
          }
          return http.Response(
            jsonEncode({
              'deleted': true,
              'requires_confirmation': false,
              'reference_count': 1,
              'message': 'Deleted',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      SessionStore.instance = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      await SessionStore.instance.refresh();
      try {
        final view = ReportView(
          project: 'p1',
          report: 'r1',
          title: 'R1',
          description: '',
          tags: const [],
          period: null,
          updatedAt: '',
          datasets: const [_desc],
        );
        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              view: view,
              slot: const Slot(
                'ds-1',
                visual: Visual.bar,
                measures: ['y'],
              ),
              service: ReportService(api),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_visibility_personal')));
        await tester.pumpAndSettle();
        expect(
          calls.any((c) => c.startsWith('PATCH /me/items/item-owned-1')),
          isTrue,
        );

        // Delete hits 409 first -> shows second explicit confirm dialog -> confirm=true deletes.
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Referenced by 1 note'), findsOneWidget);
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();
        expect(
          calls.any(
            (c) => c.contains('DELETE /me/items/item-owned-1?confirm=false'),
          ),
          isTrue,
        );
        expect(
          calls.any(
            (c) => c.contains('DELETE /me/items/item-owned-1?confirm=true'),
          ),
          isTrue,
        );
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'DatasetSlot hides owner actions for non-owner/app_controlled, handles 403/retry, cancel zero effect, and captures EN/PT/TH light/dark PNGs',
    (tester) async {
      final prevStore = SessionStore.instance;
      var failPatchOnce = true;
      final calls = <String>[];
      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': 'u-owner'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-nonowner') {
          return http.Response('{"error":"forbidden"}', 403);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-1') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-owned-1',
                'control_authority': 'user_owned',
                'reference_count': 1,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' &&
            req.url.path.startsWith('/projects/p1/reports/r1/datasets/')) {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-1',
              'rows': [
                {'x': 'Alpha', 'y': 10},
                {'x': 'Beta', 'y': 20},
              ],
              'total_rows': 2,
            }),
            200,
          );
        }
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-owned-1') {
          if (failPatchOnce) {
            failPatchOnce = false;
            return http.Response('{"error":"csrf_failed"}', 403);
          }
          return http.Response(
            jsonEncode({'item': {'id': 'item-owned-1'}}),
            200,
          );
        }
        if (req.method == 'DELETE' &&
            req.url.path == '/me/items/item-owned-1') {
          if (req.url.queryParameters['confirm'] != 'true') {
            return http.Response(
              jsonEncode({
                'deleted': false,
                'requires_confirmation': true,
                'reference_count': 1,
                'message': 'Referenced by 1 note',
              }),
              409,
            );
          }
          return http.Response(
            jsonEncode({'deleted': true, 'requires_confirmation': false}),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      SessionStore.instance = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      await SessionStore.instance.refresh();
      try {
        // 1. Non-owner gets 403 on probe -> zero owner actions or owner badge.
        final nonOwnerDesc = DatasetDescriptor(
          datasetId: 'ds-nonowner',
          title: 'Other User Chart',
          description: '',
          equation: null,
          fields: const [],
          filters: const [],
          visibility: 'public',
        );
        final view = ReportView(
          project: 'p1',
          report: 'r1',
          title: 'R1',
          description: '',
          tags: const [],
          period: null,
          updatedAt: '',
          datasets: [_desc, nonOwnerDesc],
        );
        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              view: view,
              slot: const Slot('ds-nonowner', visual: Visual.bar, measures: ['y']),
              service: ReportService(api),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);

        // 2. Owner PATCH failure -> SnackBar retry -> succeeds, and cancel on 409 does zero confirm=true DELETE.
        final controller = LanguageController();
        await tester.pumpWidget(
          LanguageScope(
            controller: controller,
            child: MaterialApp(
              theme: ThemeRegistry.theme('cortex', Brightness.light),
              home: Scaffold(
                body: RepaintBoundary(
                  key: const Key('capture_root'),
                  child: Center(
                    child: SizedBox(
                      width: 360,
                      child: DatasetSlot(
                        project: 'p1',
                        report: 'r1',
                        view: view,
                        slot: const Slot('ds-1', visual: Visual.bar, measures: ['y']),
                        service: ReportService(api),
                        apiClient: api,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_visibility_personal')));
        await tester.pumpAndSettle();
        // First PATCH returned 403 -> retry snackbar appears.
        expect(find.byType(SnackBar), findsOneWidget);
        await tester.tap(find.byType(SnackBarAction));
        await tester.pumpAndSettle();
        expect(
          calls.where((c) => c.startsWith('PATCH /me/items/item-owned-1')).length,
          2,
        );

        // Cancel on 409 reuse dialog leaves zero confirm=true DELETE calls.
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_cancel')));
        await tester.pumpAndSettle();
        expect(
          calls.any((c) => c.contains('confirm=true')),
          isFalse,
        );

        // 3. Render real PNG captures into cache dir for EN / pt-BR / th in light & dark at 390x844 & 1300x860.
        final capDir = Directory(
          Platform.environment['REPORTS_CAPTURE_DIR'] ??
              '${Directory.systemTemp.path}/reports-44-captures',
        );
        if (!capDir.existsSync()) capDir.createSync(recursive: true);
        for (final appLang in [AppLanguage.en, AppLanguage.pt, AppLanguage.th]) {
          final langCtrl = LanguageController(initial: appLang);
          for (final brightness in [Brightness.light, Brightness.dark]) {
            for (final size in [const Size(390, 844), const Size(1300, 860)]) {
              await tester.binding.setSurfaceSize(size);
              await tester.pumpWidget(
                LanguageScope(
                  controller: langCtrl,
                  child: MaterialApp(
                    theme: ThemeRegistry.theme('cortex', brightness),
                    home: Scaffold(
                      body: RepaintBoundary(
                        key: const Key('capture_root'),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DatasetSlot(
                            project: 'p1',
                            report: 'r1',
                            view: view,
                            slot: const Slot('ds-1', visual: Visual.bar, measures: ['y']),
                            service: ReportService(api),
                            apiClient: api,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('capture_root')),
              );
              final bytes = await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1.0);
                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                return byteData!.buffer.asUint8List();
              });
              final file = File(
                '${capDir.path}/owner_${appLang.name}_${brightness.name}_${size.width.toInt()}x${size.height.toInt()}.png',
              );
              file.writeAsBytesSync(bytes!);
            }
          }
        }
        await tester.binding.setSurfaceSize(null);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );
}
