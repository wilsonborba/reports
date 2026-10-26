import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';
import 'package:reports_ui/widgets/report/share_dialog.dart';
import 'package:reports_ui/themes/reports_theme.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:reports_ui/widgets/report/dataset_slot.dart';
import 'package:reports_ui/widgets/charts/data_table_view.dart';
import 'package:reports_ui/widgets/shell/app_shell.dart';
import 'package:reports_ui/services/embed_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('descriptor API preserves selected table and filter state', () async {
    final api = FakeApi();
    api.routes['/projects/cortex/showcase/report_1/cards/d1/embed'] = (query) =>
        {
          'embed_url': 'https://reports.asodya.com/v1/embed/cortex/report_1/d1',
          'view': query['view'],
          'filter': query['f.provider'],
        };
    api.install(withSession: false);
    final descriptor = await itemEmbed(
      '/v1/menu/cortex/report_1/d1?view=table&f.provider=ollama',
      language: 'en',
    );
    expect(descriptor['view'], 'table');
    expect(descriptor['filter'], 'ollama');
  });
  testWidgets('compact route renders one item without the application shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi().withReport('cortex', 'report_1', 1).install(withSession: false);
    await tester.pumpWidget(
      const ReportsApp(
        initialLocation: '/v1/embed/cortex/report_1/d1?view=table',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(DatasetSlot), findsOneWidget);
    final original = tester.widget<DatasetSlot>(find.byType(DatasetSlot));
    expect(original.initialTable, isTrue);
    expect(original.interactive, isFalse);
    expect(original.service!.publicOnly, isTrue);
    expect(find.byType(DataTableView), findsOneWidget);
  });
  testWidgets('share modes use the Reports control radius and the live original preview', (tester) async {
    final api=FakeApi();
    const url='https://reports.asodya.com/v1/embed/cortex/report_1/d1?theme=dark';
    api.routes['/projects/cortex/showcase/report_1/cards/d1/embed']=(_)=>{'embed_url':url,'html':'<iframe></iframe>'};
    api.install(withSession:false);
    await tester.pumpWidget(MaterialApp(theme:ReportsTheme.palette(Brightness.dark).toTheme(Brightness.dark),home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showShareDialog(context,'/v1/menu/cortex/report_1/d1'),child:const Text('Open'))))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();
    final control=tester.widget<OutlinedButton>(find.byKey(const Key('share_mode_embed')));
    final shape=control.style!.shape!.resolve({}) as RoundedRectangleBorder;
    expect(shape.borderRadius,BorderRadius.circular(ReportPalette.controlRadius));
    await tester.tap(find.byKey(const Key('share_mode_embed')));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(url)),findsOneWidget);
    expect(find.byKey(const Key('share_embed_html')),findsOneWidget);
  });

}
