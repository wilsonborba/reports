import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/export/artifact_jobs.dart';
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/themes/theme_registry.dart';
import 'package:reports_ui/widgets/report/artifacts_menu.dart';

void main() {
  late List<ExportFile> saved;
  late Map<ArtifactFormat, Completer<ExportFile>> pending;
  late Map<ArtifactFormat, ProgressSink> sinks;
  late ArtifactJobs jobs;

  setUp(() {
    saved = [];
    pending = {};
    sinks = {};
    jobs = ArtifactJobs(
      runner: (f, progress) {
        sinks[f] = progress;
        return (pending[f] = Completer<ExportFile>()).future;
      },
      save: saved.add,
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeRegistry.theme(null, Brightness.light),
      home: Scaffold(body: Align(alignment: Alignment.topRight, child: ArtifactsMenu(jobs: jobs))),
    ));
    await tester.tap(find.byKey(const Key('artifacts_button')));
    await tester.pumpAndSettle();
  }

  // A menu item runs its action after the frame of the tap.
  Future<void> tapItem(WidgetTester tester, ArtifactFormat f) async {
    await tester.tap(find.byKey(Key('artifact_${f.name}')));
    await tester.pump();
    await tester.pump();
  }

  String status(WidgetTester tester, ArtifactFormat f) => tester.widget<Text>(find.byKey(Key('artifact_status_${f.name}'))).data!;

  testWidgets('one button opens PDF, Markdown and CSV items', (tester) async {
    await open(tester);
    expect(find.text('PDF report'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('CSV data (ZIP)'), findsOneWidget);
    expect(status(tester, ArtifactFormat.csv), 'All chart data, one file per chart');
  });

  testWidgets('progress, then saved with the file name; the menu stays open', (tester) async {
    await open(tester);
    await tapItem(tester, ArtifactFormat.csv);
    expect(status(tester, ArtifactFormat.csv), 'Preparing');
    sinks[ArtifactFormat.csv]!(const ExportProgress('Loading chart data 12 of 28', done: 11, total: 28));
    await tester.pump();
    expect(status(tester, ArtifactFormat.csv), 'Loading chart data 12 of 28');
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(11 / 28, 1e-9));
    // A second tap while it runs does not start it twice.
    await tapItem(tester, ArtifactFormat.csv);
    pending[ArtifactFormat.csv]!.complete(ExportFile('cortex_model_usage_20261021.zip', Uint8List(3), 'application/zip'));
    await tester.pumpAndSettle();
    expect(status(tester, ArtifactFormat.csv), 'Saved: cortex_model_usage_20261021.zip');
    expect(saved.map((f) => f.name), ['cortex_model_usage_20261021.zip']);
    expect(find.text('PDF report'), findsOneWidget, reason: 'the menu stays open');
  });

  testWidgets('an error shows a retry; the retry runs the export again', (tester) async {
    await open(tester);
    await tapItem(tester, ArtifactFormat.pdf);
    pending[ArtifactFormat.pdf]!.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(status(tester, ArtifactFormat.pdf), 'Failed. Select to try again.');
    expect(saved, isEmpty);
    await tapItem(tester, ArtifactFormat.pdf);
    expect(status(tester, ArtifactFormat.pdf), 'Preparing');
    pending[ArtifactFormat.pdf]!.complete(ExportFile('cortex_model_usage_20261021.pdf', Uint8List(3), 'application/pdf'));
    await tester.pumpAndSettle();
    expect(status(tester, ArtifactFormat.pdf), 'Saved: cortex_model_usage_20261021.pdf');
  });

  testWidgets('two formats run side by side with their own progress', (tester) async {
    await open(tester);
    await tapItem(tester, ArtifactFormat.md);
    await tapItem(tester, ArtifactFormat.csv);
    sinks[ArtifactFormat.md]!(const ExportProgress('Loading chart data 3 of 9', done: 2, total: 9));
    await tester.pump();
    expect(status(tester, ArtifactFormat.md), 'Loading chart data 3 of 9');
    expect(status(tester, ArtifactFormat.csv), 'Preparing');
    expect(jobs.busy, isTrue);
    pending[ArtifactFormat.md]!.complete(ExportFile('a.md', Uint8List(1), 'text/markdown'));
    pending[ArtifactFormat.csv]!.complete(ExportFile('a.zip', Uint8List(1), 'application/zip'));
    await tester.pumpAndSettle();
    expect(jobs.busy, isFalse);
  });
}
