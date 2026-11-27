import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:reports_ui/views/dataset_full_view.dart';

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
        expect(find.byKey(const Key('card_delete_reuse_warning')), findsOneWidget);
        expect(
          find.text('This item is referenced by 1 note(s). Deleting it removes the source item and makes it unavailable in those notes.'),
          findsOneWidget,
        );
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

  testWidgets(
    'DatasetSlot reacts to SessionStore dynamic transitions and shows freshnessMode independently',
    (tester) async {
      final prevStore = SessionStore.instance;
      final mock = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': 'u-dynamic'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-dynamic') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-dyn-1',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' &&
            req.url.path == '/projects/p1/reports/r1/datasets/ds-dynamic') {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-dynamic',
              'rows': [{'x': 'a', 'y': 10}],
              'total_rows': 1,
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      String? dynamicCsrf;
      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? dynamicCsrf : null,
      );

      // Start with signedOut (no session)
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? dynamicCsrf : null,
      );
      SessionStore.instance = sessionStore;

      try {
        final desc = DatasetDescriptor(
          datasetId: 'ds-dynamic',
          title: 'Dynamic Chart',
          description: '',
          equation: null,
          fields: const [],
          filters: const [],
          visibility: 'public',
          meta: const DatasetMeta(freshnessMode: 'live'),
        );
        final view = ReportView(
          project: 'p1',
          report: 'r1',
          title: 'Dynamic Report',
          description: '',
          tags: const [],
          period: null,
          updatedAt: '',
          datasets: [desc],
        );

        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              view: view,
              slot: const Slot('ds-dynamic', visual: Visual.bar, measures: ['y']),
              service: ReportService(api),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Freshness mode 'live' badge displays even without owner session
        expect(find.byKey(const Key('card_mark_live')), findsOneWidget);
        // Owner badge must NOT be present
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);

        // 2. Transition session to signed in: refresh sets signedIn state
        dynamicCsrf = 'csrf-live';
        await sessionStore.refresh();
        await tester.pumpAndSettle();

        // Owner badge is now displayed after session sign-in
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 3. Transition session back to signedOut
        dynamicCsrf = null;
        sessionStore.clear();
        await tester.pumpAndSettle();

        // Owner badge is cleared immediately on sign out
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'DatasetSlot clears owner state on User A -> User B identity transition',
    (tester) async {
      final prevStore = SessionStore.instance;
      String currentUserId = 'u-user-a';
      final mock = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': currentUserId}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-dynamic') {
          if (currentUserId == 'u-user-a') {
            return http.Response(
              jsonEncode({
                'item': {
                  'id': 'item-a-1',
                  'control_authority': 'user_owned',
                  'reference_count': 0,
                },
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({
                'item': {
                  'id': 'item-b-1',
                  'control_authority': 'viewer',
                  'reference_count': 0,
                },
              }),
              200,
            );
          }
        }
        if (req.method == 'GET' &&
            req.url.path == '/projects/p1/reports/r1/datasets/ds-dynamic') {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-dynamic',
              'rows': [{'x': 'a', 'y': 10}],
              'total_rows': 1,
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-active' : null,
      );

      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-active' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        final desc = DatasetDescriptor(
          datasetId: 'ds-dynamic',
          title: 'Dynamic Chart',
          description: '',
          equation: null,
          fields: const [],
          filters: const [],
          visibility: 'public',
        );
        final view = ReportView(
          project: 'p1',
          report: 'r1',
          title: 'Dynamic Report',
          description: '',
          tags: const [],
          period: null,
          updatedAt: '',
          datasets: [desc],
        );

        // 1. Initial load under User A (owner)
        await sessionStore.refresh();
        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              view: view,
              slot: const Slot('ds-dynamic', visual: Visual.bar, measures: ['y']),
              service: ReportService(api),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 2. Identity transition to User B (viewer)
        currentUserId = 'u-user-b';
        await sessionStore.refresh();
        await tester.pumpAndSettle();

        // Owner mark is immediately cleared and does not return
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'Canonical snapshot freshness displays Static mark on slot and full view, and unknown meta is null',
    (tester) async {
      final mock = MockClient((req) async {
        if (req.method == 'GET' &&
            (req.url.path.contains('/datasets/ds-snapshot') ||
                req.url.path.contains('/cards/ds-snapshot'))) {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-snapshot',
              'rows': [{'x': 'a', 'y': 10}],
              'total_rows': 1,
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/projects/p1/showcase/r1') {
          return http.Response(
            jsonEncode({
              'project': 'p1',
              'report': 'r1',
              'title': 'R1',
              'cards': [
                {
                  'dataset_id': 'ds-snapshot',
                  'title': 'Snapshot Chart',
                  'visibility': 'public',
                  'descriptor': {
                    'dataset_id': 'ds-snapshot',
                    'title': 'Snapshot Chart',
                    'meta': {'freshness_mode': 'snapshot'},
                  },
                },
              ],
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/projects/p1/reports/r1') {
          return http.Response(
            jsonEncode({
              'project': 'p1',
              'report': 'r1',
              'title': 'R1',
              'datasets': [
                {
                  'dataset_id': 'ds-snapshot',
                  'title': 'Snapshot Chart',
                  'visibility': 'public',
                  'meta': {'freshness_mode': 'snapshot'},
                },
              ],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
      );
      final service = ReportService(api);

      final desc = DatasetDescriptor(
        datasetId: 'ds-snapshot',
        title: 'Snapshot Chart',
        description: '',
        equation: null,
        fields: const [],
        filters: const [],
        visibility: 'public',
        meta: const DatasetMeta(freshnessMode: 'snapshot'),
      );
      final view = ReportView(
        project: 'p1',
        report: 'r1',
        title: 'Report',
        description: '',
        tags: const [],
        period: null,
        updatedAt: '',
        datasets: [desc],
      );

      // 1. Check slot displays mark_static and 'Static'
      await tester.pumpWidget(
        _wrap(
          DatasetSlot(
            project: 'p1',
            report: 'r1',
            view: view,
            slot: const Slot('ds-snapshot', visual: Visual.bar, measures: ['y']),
            service: service,
            apiClient: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_mark_static')), findsOneWidget);
      expect(find.text('Static'), findsOneWidget);

      // 2. Check full view displays mark_static
      await tester.pumpWidget(
        _wrap(
          DatasetFullView(
            project: 'p1',
            report: 'r1',
            datasetId: 'ds-snapshot',
            visual: Visual.bar,
            compact: true,
            service: service,
            apiClient: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_mark_static')), findsOneWidget);
    },
  );

  testWidgets(
    'DatasetFullView provides owner controls, visibility changes and delete flow',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];
      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': 'u-owner-full'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-full') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-full-1',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-full-1') {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item-full-1') {
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/projects/p1/reports/r1') {
          return http.Response(
            jsonEncode({
              'project': 'p1',
              'report': 'r1',
              'title': 'R1',
              'description': '',
              'tags': [],
              'period': null,
              'updated_at': '',
              'datasets': [
                {
                  'dataset_id': 'ds-full',
                  'title': 'Full Chart',
                  'description': '',
                  'equation': null,
                  'fields': [],
                  'filters': [],
                  'visibility': 'personal',
                },
              ],
            }),
            200,
          );
        }
        if (req.method == 'GET' &&
            req.url.path.contains('/datasets/ds-full')) {
          return http.Response(
            jsonEncode({
              'dataset_id': 'ds-full',
              'rows': [{'x': 'a', 'y': 10}],
              'total_rows': 1,
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        await sessionStore.refresh();
        await tester.pumpWidget(
          _wrap(
            DatasetFullView(
              project: 'p1',
              report: 'r1',
              datasetId: 'ds-full',
              visual: Visual.bar,
              compact: true,
              service: ReportService(api),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Owner mark displayed in full view
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 2. Open options menu and verify owner actions
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('card_menu_visibility_public')), findsOneWidget);
        expect(find.byKey(const Key('card_menu_delete')), findsOneWidget);

        // 3. Change visibility to public
        await tester.tap(find.byKey(const Key('card_menu_visibility_public')));
        await tester.pumpAndSettle();
        expect(
          calls.any((c) => c.contains('PATCH /me/items/item-full-1')),
          isTrue,
        );

        // 4. Delete item
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('card_delete_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();
        expect(
          calls.any((c) => c.contains('DELETE /me/items/item-full-1')),
          isTrue,
        );
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'parameterized route navigation in DatasetFullView re-probes and mutates only target card',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];

      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(
            jsonEncode({'user_id': 'user-1'}),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-chart-a') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-a',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-chart-b') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-b',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-b') {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/projects/p1/reports/r1') {
          return http.Response(
            jsonEncode({
              'project': 'p1',
              'report': 'r1',
              'title': 'R1',
              'description': '',
              'tags': [],
              'period': null,
              'updated_at': '',
              'datasets': [
                {
                  'dataset_id': 'ds-chart-a',
                  'title': 'Chart A',
                  'description': '',
                  'equation': null,
                  'fields': [],
                  'filters': [],
                  'visibility': 'personal',
                },
                {
                  'dataset_id': 'ds-chart-b',
                  'title': 'Chart B',
                  'description': '',
                  'equation': null,
                  'fields': [],
                  'filters': [],
                  'visibility': 'personal',
                },
              ],
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path.contains('/datasets/')) {
          final id = req.url.path.split('/').last;
          return http.Response(
            jsonEncode({
              'dataset_id': id,
              'rows': [{'x': 'a', 'y': 10}],
              'total_rows': 1,
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        await sessionStore.refresh();
        final router = GoRouter(
          initialLocation: '/v1/menu/p1/r1/cards/ds-chart-a',
          routes: [
            GoRoute(
              path: '/v1/menu/:project/:report/cards/:dataset',
              builder: (_, s) => Scaffold(
                body: DatasetFullView(
                  project: s.pathParameters['project']!,
                  report: s.pathParameters['report']!,
                  datasetId: s.pathParameters['dataset']!,
                  visual: Visual.bar,
                  compact: true,
                  service: ReportService(api),
                  apiClient: api,
                ),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          LanguageScope(
            controller: LanguageController(),
            child: MaterialApp.router(
              theme: ThemeRegistry.theme('cortex', Brightness.light),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial chart A probed and owner mark visible
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);
        expect(calls.contains('GET /me/items/ds-chart-a'), isTrue);

        // 2. Navigate to chart B using GoRouter context.go
        router.go('/v1/menu/p1/r1/cards/ds-chart-b');
        await tester.pumpAndSettle();

        // Verify chart B probed
        expect(calls.contains('GET /me/items/ds-chart-b'), isTrue);

        // 3. Mutate visibility on chart B
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_visibility_public')));
        await tester.pumpAndSettle();

        // 4. Assert only item-b was mutated, item-a was NEVER mutated
        expect(calls.contains('PATCH /me/items/item-b'), isTrue);
        expect(calls.any((c) => c.contains('PATCH /me/items/item-a')), isFalse);
        expect(calls.any((c) => c.contains('DELETE /me/items/item-a')), isFalse);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'pending mutation during session invalidation clears busy state and fences old completion',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];
      final patchCompleter = Completer<http.Response>();
      var currentUserId = 'user-1';

      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/me') {
          if (currentUserId.isEmpty) {
            return http.Response('unauthorized', 401);
          }
          return http.Response(
            jsonEncode({'user_id': currentUserId}),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-slot') {
          if (currentUserId.isEmpty) {
            return http.Response(jsonEncode({}), 403);
          }
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-slot-1',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-slot-1') {
          return await patchCompleter.future;
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        await sessionStore.refresh();

        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              slot: const Slot('ds-slot'),
              view: ReportView.fromJson({
                'project': 'p1',
                'report': 'r1',
                'title': 'R1',
                'datasets': [
                  {
                    'dataset_id': 'ds-slot',
                    'title': 'Slot Chart',
                    'visibility': 'personal',
                  },
                ],
              }),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Owner mark visible on initial probe
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 2. Start visibility mutation which hangs on patchCompleter
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_visibility_public')));
        await tester.pump();
        expect(calls.contains('PATCH /me/items/item-slot-1'), isTrue);

        // 3. Invalidate session by logging out while mutation is pending
        currentUserId = '';
        await sessionStore.refresh();
        await tester.pumpAndSettle();

        // Owner mark gone, options menu has no owner actions
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);

        // 4. Log back in as user-1
        currentUserId = 'user-1';
        await sessionStore.refresh();
        await tester.pumpAndSettle();

        // Re-probed and owner mark restored
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 5. Release the old stalled response
        patchCompleter.complete(http.Response(jsonEncode({'success': true}), 200));
        await tester.pumpAndSettle();

        // 6. Action button is NOT disabled by stale _mutating state: can open menu and mutate again
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('card_menu_visibility_public')), findsOneWidget);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'stale retry on SnackBar does not issue mutation after navigation to another card',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];

      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(
            jsonEncode({'user_id': 'user-1'}),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-chart-a') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-a',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-chart-b') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-b',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/projects/p1/reports/r1') {
          return http.Response(
            jsonEncode({
              'project': 'p1',
              'report': 'r1',
              'title': 'R1',
              'description': '',
              'tags': [],
              'period': null,
              'updated_at': '',
              'datasets': [
                {
                  'dataset_id': 'ds-chart-a',
                  'title': 'Chart A',
                  'description': '',
                  'equation': null,
                  'fields': [],
                  'filters': [],
                  'visibility': 'personal',
                },
                {
                  'dataset_id': 'ds-chart-b',
                  'title': 'Chart B',
                  'description': '',
                  'equation': null,
                  'fields': [],
                  'filters': [],
                  'visibility': 'personal',
                },
              ],
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path.contains('/datasets/')) {
          final id = req.url.path.split('/').last;
          return http.Response(
            jsonEncode({
              'dataset_id': id,
              'rows': [
                {'x': 'a', 'y': 10}
              ],
              'total_rows': 1,
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item-a') {
          return http.Response('server error', 500);
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item-b') {
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        await sessionStore.refresh();
        final router = GoRouter(
          initialLocation: '/v1/menu/p1/r1/cards/ds-chart-a',
          routes: [
            GoRoute(
              path: '/v1/menu/:project/:report/cards/:dataset',
              builder: (_, s) => Scaffold(
                body: DatasetFullView(
                  project: s.pathParameters['project']!,
                  report: s.pathParameters['report']!,
                  datasetId: s.pathParameters['dataset']!,
                  visual: Visual.bar,
                  compact: true,
                  service: ReportService(api),
                  apiClient: api,
                ),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          LanguageScope(
            controller: LanguageController(),
            child: MaterialApp.router(
              theme: ThemeRegistry.theme('cortex', Brightness.light),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial chart A probed
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 2. Trigger delete on chart A which fails (500)
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();

        // Error SnackBar with Retry button appears
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
        expect(calls.contains('DELETE /me/items/item-a'), isTrue);
        final initialDeleteCalls =
            calls.where((c) => c.startsWith('DELETE')).length;

        // 3. Navigate to chart B while SnackBar is still visible
        router.go('/v1/menu/p1/r1/cards/ds-chart-b');
        await tester.pumpAndSettle();

        // Verify chart B is loaded and SnackBar Retry is still displayed
        expect(calls.contains('GET /me/items/ds-chart-b'), isTrue);
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

        // 4. Tap the stale Retry action from chart A
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await tester.pump();

        // 5. Assert ZERO destructive request against item-b or item-a
        final postRetryDeleteCalls =
            calls.where((c) => c.startsWith('DELETE')).length;
        expect(postRetryDeleteCalls, equals(initialDeleteCalls));
        expect(calls.any((c) => c.contains('DELETE /me/items/item-b')), isFalse);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'valid same-card retry on SnackBar re-issues mutation when target remains unchanged',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];
      var failDelete = true;

      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(
            jsonEncode({'user_id': 'user-1'}),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path == '/me/items/ds-slot') {
          return http.Response(
            jsonEncode({
              'item': {
                'id': 'item-slot-1',
                'control_authority': 'user_owned',
                'reference_count': 0,
              },
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item-slot-1') {
          if (failDelete) {
            failDelete = false;
            return http.Response('server error', 500);
          }
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-owner' : null,
      );
      SessionStore.instance = sessionStore;

      try {
        await sessionStore.refresh();

        await tester.pumpWidget(
          _wrap(
            DatasetSlot(
              project: 'p1',
              report: 'r1',
              slot: const Slot('ds-slot'),
              view: ReportView.fromJson({
                'project': 'p1',
                'report': 'r1',
                'title': 'R1',
                'datasets': [
                  {
                    'dataset_id': 'ds-slot',
                    'title': 'Slot Chart',
                    'visibility': 'personal',
                  },
                ],
              }),
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial slot probed
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 2. Trigger delete which fails initially
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
        expect(
          calls.where((c) => c == 'DELETE /me/items/item-slot-1').length,
          equals(1),
        );

        // 3. Tap Retry on valid same card
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await tester.pumpAndSettle();

        // 4. Assert re-issued delete succeeded on same card
        expect(
          calls.where((c) => c == 'DELETE /me/items/item-slot-1').length,
          equals(2),
        );
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );

  testWidgets(
    'real producer collision: two reports both have primary dataset; foreign-owner in report 1, caller in report 2; each resolves and mutates strictly its own item',
    (tester) async {
      final prevStore = SessionStore.instance;
      final calls = <String>[];
      final mock = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.method == 'GET' && req.url.path == '/me') {
          return http.Response(jsonEncode({'user_id': 'user-caller'}), 200);
        }
        if (req.method == 'GET' && req.url.path.endsWith('/me/items/primary')) {
          final proj = req.url.queryParameters['project'];
          final rep = req.url.queryParameters['report'];
          if (proj == 'proj-1' && rep == 'rep-foreign') {
            // First item in producer DB belongs to another owner -> 403 or foreign control
            return http.Response('{"error":"forbidden: not owner"}', 403);
          }
          if (proj == 'proj-1' && rep == 'rep-caller') {
            // Second item belongs to caller
            return http.Response(
              jsonEncode({
                'item': {
                  'id': 'item-caller-uuid-222',
                  'control_authority': 'user_owned',
                  'reference_count': 0,
                },
              }),
              200,
            );
          }
        }
        if (req.method == 'GET' &&
            req.url.path.contains('/datasets/primary')) {
          return http.Response(
            jsonEncode({
              'dataset_id': 'primary',
              'rows': [
                {'metric': 'val', 'count': 42},
              ],
              'total_rows': 1,
            }),
            200,
          );
        }
        if (req.method == 'PATCH' &&
            req.url.path.endsWith('/me/items/item-caller-uuid-222')) {
          return http.Response(
            jsonEncode({'item': {'id': 'item-caller-uuid-222'}}),
            200,
          );
        }
        if (req.method == 'DELETE' &&
            req.url.path.endsWith('/me/items/item-caller-uuid-222')) {
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        if (req.url.path.contains('foreign')) {
          throw StateError('Destructive or mutation request targeted foreign item: ${req.url}');
        }
        return http.Response('not found', 404);
      });

      final api = ApiClient(
        baseUrl: 'https://reports.invalid',
        client: mock,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      final sessionStore = SessionStore(
        api: api,
        cookieReader: (k) => k == 'csrf' ? 'csrf-live' : null,
      );
      SessionStore.instance = sessionStore;
      await sessionStore.refresh();

      try {
        const descPrimary = DatasetDescriptor(
          datasetId: 'primary',
          title: 'Primary Chart',
          description: 'Standard producer primary dataset',
          equation: null,
          fields: [],
          filters: [],
          visibility: 'public',
        );

        // 1. Render card in foreign report (rep-foreign)
        final foreignSlot = DatasetSlot(
          project: 'proj-1',
          report: 'rep-foreign',
          view: const ReportView(
            project: 'proj-1',
            report: 'rep-foreign',
            title: 'Foreign Report',
            description: '',
            tags: [],
            period: null,
            updatedAt: '',
            datasets: [descPrimary],
          ),
          slot: const Slot('primary', visual: Visual.bar, measures: ['count']),
          controls: const CardControls(isOwner: false, isLive: false),
          fill: false,
          apiClient: api,
          service: ReportService(api),
        );

        await tester.pumpWidget(_wrap(foreignSlot));
        await tester.pumpAndSettle();

        // Foreign card probes with project=proj-1&report=rep-foreign
        expect(
          calls.any((c) =>
              c.contains('/me/items/primary') &&
              c.contains('project=proj-1') &&
              c.contains('report=rep-foreign')),
          isTrue,
        );
        // Foreign card must NOT have owner controls
        expect(find.byKey(const Key('card_mark_owner')), findsNothing);

        // 2. Render card in caller report (rep-caller)
        final callerSlot = DatasetSlot(
          project: 'proj-1',
          report: 'rep-caller',
          view: const ReportView(
            project: 'proj-1',
            report: 'rep-caller',
            title: 'Caller Report',
            description: '',
            tags: [],
            period: null,
            updatedAt: '',
            datasets: [descPrimary],
          ),
          slot: const Slot('primary', visual: Visual.bar, measures: ['count']),
          controls: const CardControls(isOwner: false, isLive: false),
          fill: false,
          apiClient: api,
          service: ReportService(api),
        );

        await tester.pumpWidget(_wrap(callerSlot));
        await tester.pumpAndSettle();

        // Caller card probes with project=proj-1&report=rep-caller
        expect(
          calls.any((c) =>
              c.contains('/me/items/primary') &&
              c.contains('project=proj-1') &&
              c.contains('report=rep-caller')),
          isTrue,
        );
        // Caller card resolves ownership
        expect(find.byKey(const Key('card_mark_owner')), findsOneWidget);

        // 3. Mutate visibility on caller card
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_visibility_personal')));
        await tester.pumpAndSettle();

        // Assert mutation used EXACT item ID for caller
        expect(
          calls.any((c) => c.contains('PATCH') && c.contains('/me/items/item-caller-uuid-222')),
          isTrue,
        );
        expect(calls.any((c) => c.contains('item-foreign-uuid-111')), isFalse);

        // 4. Delete caller card
        await tester.tap(find.byKey(const Key('card_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_menu_delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('card_delete_confirm')));
        await tester.pumpAndSettle();

        // Assert delete used EXACT item ID for caller
        expect(
          calls.any((c) => c.contains('DELETE') && c.contains('/me/items/item-caller-uuid-222')),
          isTrue,
        );
        expect(calls.any((c) => c.contains('item-foreign-uuid-111')), isFalse);
      } finally {
        SessionStore.instance = prevStore;
      }
    },
  );
}
