import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../l10n/strings.dart';
import '../models/catalog.dart';
import '../services/catalog_service.dart';
import '../services/report_service.dart';
import '../themes/theme_registry.dart';
import '../widgets/report/section_pills.dart';
import 'artifact_jobs.dart';
import 'csv_export.dart';
import 'export_plan.dart';
import 'markdown_export.dart';
import 'pdf_export.dart';
import 'thai_text.dart';

/// Builds the export files of one report from the dataset API. CSV and Markdown use the
/// language of the page; the PDF is English (Thai text as images, owner decision 1).
class ReportArtifacts {
  final String project;
  final String report;
  final String Function() language;
  final Map<int, String> Function() sectionNames;

  ReportArtifacts({required this.project, required this.report, required this.language, required this.sectionNames});

  static PdfFonts? _fonts;

  /// Rows of a card in Markdown and PDF: the same request as the card on the dashboard.
  static const int cardRows = 500;

  Future<ExportFile> run(ArtifactFormat format, ProgressSink progress) async {
    final service = ReportService.instance;
    final lang = format == ArtifactFormat.pdf ? 'en' : language();
    final t = LanguageController(initial: lang == 'th' ? AppLanguage.th : lang == 'pt-BR' ? AppLanguage.pt : AppLanguage.en).t;
    final view = await service.report(project, report, lang: lang);
    ProjectSummary? info;
    try {
      info = await CatalogService.instance.project(project, lang: lang);
    } catch (_) {}
    final names = sectionNames();
    final plan = await ExportPlan.build(
      project: project,
      report: report,
      lang: lang,
      view: view,
      projectInfo: info,
      sectionName: (i) => names[i] ?? SectionPills.labelWith(t, i),
    );
    switch (format) {
      case ArtifactFormat.csv:
        return CsvExport.build(plan,
            load: (c) => service.allRows(project, report, c.slot.datasetId, lang: lang, filters: c.filters, maxRows: CsvExport.maxRows),
            progress: progress,
            t: t);
      case ArtifactFormat.md:
        return MarkdownExport.build(plan,
            load: (c) => service.dataset(project, report, c.slot.datasetId, lang: lang, filters: c.filters, limit: cardRows), progress: progress, t: t);
      case ArtifactFormat.pdf:
        _fonts ??= await PdfFonts.load(rootBundle.load);
        return PdfExport.build(
          plan,
          load: (c) => service.dataset(project, report, c.slot.datasetId, lang: lang, filters: c.filters, limit: cardRows),
          progress: progress,
          t: t,
          fonts: _fonts!,
          palette: ThemeRegistry.palette(project, Brightness.light),
          renderText: renderTextImage,
          logo: await _logo(info),
        );
    }
  }

  /// Light logo (or icon) of the project from the asset API; null when it does not load.
  static Future<Uint8List?> _logo(ProjectSummary? info) async {
    final asset = info?.assets['logo'] ?? info?.assets['icon'];
    if (asset == null) return null;
    try {
      final res = await http.get(Uri.parse(CatalogService.instance.assetUrl(asset.url)));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}
