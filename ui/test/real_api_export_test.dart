// Builds the PDF, Markdown and CSV files of real reports from a running engine, for a
// visual check. Off by default; run it with:
//   REPORT_API=http://127.0.0.1:8109 REPORTS=cortex/model-usage,... flutter test test/real_api_export_test.dart
// The files go to build/real_exports. It reads the guest showcase of public reports
// (a VM test has no gateway session).
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reports_ui/export/artifact_jobs.dart';
import 'package:reports_ui/export/report_artifacts.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/catalog_service.dart';
import 'package:reports_ui/services/report_service.dart';
import 'package:reports_ui/themes/report_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final api = Platform.environment['REPORT_API'];
  final reports = (Platform.environment['REPORTS'] ?? 'cortex/model-usage').split(',');

  testWidgets('real reports to files', (tester) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      // The Thai text images need the real fonts.
      for (final (family, files) in [
        (ReportPalette.font, ['UbuntuSans-Variable.ttf']),
        (ReportPalette.thaiFont, ['IBMPlexSansThai-Regular.ttf', 'IBMPlexSansThai-SemiBold.ttf']),
      ]) {
        final loader = FontLoader(family);
        for (final file in files) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
        await loader.load();
      }
      final client = ApiClient(baseUrl: api!, client: http.Client());
      CatalogService.instance = CatalogService(client);
      ReportService.instance = ReportService(client);
      await CatalogService.instance.projects(lang: 'en');
      final out = Directory('build/real_exports')..createSync(recursive: true);
      for (final pr in reports) {
        final [project, report] = pr.split('/');
        for (final (format, lang) in [(ArtifactFormat.pdf, 'en'), (ArtifactFormat.md, 'pt-BR'), (ArtifactFormat.csv, 'th')]) {
          final watch = Stopwatch()..start();
          final file = await ReportArtifacts(project: project, report: report, language: () => lang, sectionNames: () => const {}).run(format, (_) {});
          File('${out.path}/${file.name}').writeAsBytesSync(file.bytes);
          // ignore: avoid_print
          print('${file.name}: ${file.bytes.length} bytes in ${watch.elapsedMilliseconds} ms');
        }
      }
    });
  }, skip: api == null, timeout: const Timeout(Duration(minutes: 10)));
}
