import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/report/dataset_card.dart';

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
    'ApiClient patches visibility and handles delete confirmation outcome',
    () async {
      final mock = MockClient((req) async {
        if (req.method == 'PATCH' && req.url.path == '/me/items/item-1') {
          expect(jsonDecode(req.body), {'visibility': 'personal'});
          return http.Response(
            jsonEncode({
              'item': {'id': 'item-1'},
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/me/items/item-1') {
          final confirm = req.url.queryParameters['confirm'] == 'true';
          return http.Response(
            jsonEncode({
              'deleted': confirm,
              'requires_confirmation': !confirm,
              'reference_count': 2,
              'message': confirm ? 'Deleted' : 'Used in 2 notes',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final api = ApiClient(baseUrl: 'https://reports.invalid', client: mock);
      final patched = await api.patchOwnerItemVisibility('item-1', 'personal');
      expect(patched['item']['id'], 'item-1');

      final first = await api.deleteOwnerItem('item-1', confirm: false);
      expect(first.deleted, isFalse);
      expect(first.requiresConfirmation, isTrue);
      expect(first.referenceCount, 2);
      expect(first.message, 'Used in 2 notes');

      final second = await api.deleteOwnerItem('item-1', confirm: true);
      expect(second.deleted, isTrue);
    },
  );
}
