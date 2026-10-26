import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/export/pdf_export.dart';
import 'package:reports_ui/export/thai_text.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/catalog.dart';
import 'package:reports_ui/models/report.dart';
import 'package:reports_ui/themes/reports_theme.dart';

final png1x1 = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// Test renderer: a 1 x 1 image with the size of the text.
Future<TextImage> fakeRenderer(String text, {required double fontSize, required bool bold, required double maxWidth, required int color}) async {
  final w = (text.length * fontSize * 0.55).clamp(4.0, maxWidth);
  final lines = (text.length * fontSize * 0.55 / maxWidth).ceil().clamp(1, 20);
  return TextImage(png1x1, w, fontSize * 1.3 * lines);
}

FieldInfo f(String name, String label, String type, {String? unit, int? decimals, bool dim = false}) =>
    FieldInfo(name: name, label: label, type: type, role: dim ? 'dimension' : 'measure', unit: unit, decimals: decimals);

DatasetDescriptor desc(String id, List<FieldInfo> fields, {String? equation}) =>
    DatasetDescriptor(datasetId: id, title: 'Chart $id', description: 'What $id shows.', equation: equation, fields: fields, filters: const []);

DatasetPage page(DatasetDescriptor d, List<Map<String, dynamic>> rows, {int? total}) =>
    DatasetPage(descriptor: d, rows: rows, offset: 0, limit: rows.length, totalRows: total ?? rows.length);

const longName = 'OpenRouter, the fallback provider for every model of the Cortex pool';
const thaiName = 'ผู้ให้บริการสำรองของ Cortex 1 ที่นี่';

/// Cards of every visual, with long and Thai values.
List<(ExportCard, DatasetPage)> fixture() {
  final kpi = desc('kpi', [f('total', 'Total volume', 'integer', unit: 'tokens'), f('days', 'Days', 'integer'), f('share', 'Share', 'percent')]);
  final rank = desc('rank', [f('provider', 'Provider', 'string', dim: true), f('volume', 'Volume', 'integer', unit: 'tokens'), f('share', 'Share', 'percent')],
      equation: 'Share = T_provider / T_total * 100%');
  final trend = desc('trend', [f('day', 'Day', 'date', dim: true), f('input', 'Input', 'integer', unit: 'tokens'), f('output', 'Output', 'integer', unit: 'tokens')]);
  final stacked = desc('stack', [f('hour', 'Hour', 'hour', dim: true), f('task', 'Task', 'string', dim: true), f('rpm', 'Requests', 'float', unit: 'req/min')]);
  final wide = desc('wide', [f('model', 'Model', 'string', dim: true), for (var i = 0; i < 8; i++) f('m$i', 'Metric $i', 'float', decimals: 2)]);
  final map = desc('map', [f('provider', 'Provider', 'string', dim: true), f('lat', 'Lat', 'latitude'), f('lon', 'Lon', 'longitude'), f('volume', 'Volume', 'integer')]);
  final combo = desc('combo', [f('day', 'Day', 'date', dim: true), f('volume', 'Volume', 'integer'), f('rain', 'Rain', 'float', unit: 'mm')]);
  ExportCard card(int s, DatasetDescriptor d, {Visual visual = Visual.auto, List<String> measures = const []}) =>
      ExportCard(section: s, slot: Slot(d.datasetId, visual: visual, measures: measures), descriptor: d);
  return [
    (card(0, kpi), page(kpi, [{'total': 4599892, 'days': 16, 'share': 45.7}])),
    (card(0, rank, visual: Visual.hbar), page(rank, [
      {'provider': longName, 'volume': 989536, 'share': 13.66},
      {'provider': thaiName, 'volume': 565514, 'share': 7.8},
      for (var i = 0; i < 38; i++) {'provider': 'Provider $i', 'volume': 500000 - i * 1000, 'share': 1.0},
    ])),
    (card(1, trend, visual: Visual.line), page(trend, [
      for (var i = 0; i < 50; i++) {'day': DateTime(2026, 9, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'input': 1000 + i * 10, 'output': 200 + i}
    ])),
    (card(1, stacked, visual: Visual.stackedBar), page(stacked, [
      for (var h = 0; h < 24; h++)
        for (var c = 0; c < 10; c++) {'hour': h, 'task': c == 3 ? thaiName : 'Task $c', 'rpm': 100.0 - c * 7 + h}
    ])),
    (card(1, wide, visual: Visual.table), page(wide, [
      for (var r = 0; r < 30; r++) {'model': r == 0 ? longName : 'Model $r', for (var i = 0; i < 8; i++) 'm$i': r * 1.5 + i}
    ])),
    (card(2, map, visual: Visual.map), page(map, [
      for (var i = 0; i < 40; i++) {'provider': i == 1 ? thaiName : 'Provider $i', 'lat': 13.7 + i * 0.01, 'lon': 100.5 + (i % 4) * 0.01, 'volume': 5000 - i * 100}
    ])),
    (card(2, combo, visual: Visual.combo, measures: ['volume', 'rain']), page(combo, [
      for (var i = 0; i < 25; i++) {'day': DateTime(2026, 10, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'volume': 9000 + i * 50, 'rain': (i % 5) * 1.2}
    ])),
    // A Sankey of flows between two category stages.
    (card(2, desc('flows', [f('from', 'From', 'string', dim: true), f('to', 'To', 'string', dim: true), f('n', 'Count', 'integer')]),
            visual: Visual.sankey, measures: ['n']),
        page(desc('flows', [f('from', 'From', 'string', dim: true), f('to', 'To', 'string', dim: true), f('n', 'Count', 'integer')]), [
          for (var i = 0; i < 9; i++) {'from': i == 2 ? thaiName : 'Source $i', 'to': 'Target ${i % 3}', 'n': 100 - i * 7},
        ])),
    // More cards so the document has several content pages.
    for (var k = 0; k < 6; k++) (card(2, trend, visual: Visual.bar), page(trend, [for (var i = 0; i < 20; i++) {'day': '2026-10-${(i + 1).toString().padLeft(2, '0')}', 'input': 100 + i, 'output': i}])),
  ];
}

ExportPlan plan(List<ExportCard> cards) => ExportPlan(
      project: 'cortex',
      report: 'model_usage',
      lang: 'en',
      view: ReportView(
          project: 'cortex',
          report: 'model_usage',
          title: 'Token Usage',
          description: 'Tokens of every Cortex provider.',
          tags: const [],
          period: const ReportPeriod('2026-09-26', '2026-10-20'),
          updatedAt: '',
          datasets: const []),
      projectInfo: const ProjectSummary(slug: 'cortex', name: 'Cortex', description: '', reportCount: 1),
      sections: [
        ExportSection('Key figures', cards.where((c) => c.section == 0).toList()),
        ExportSection('ทางหลัก', cards.where((c) => c.section == 1).toList()),
        ExportSection('Section Three', cards.where((c) => c.section == 2).toList()),
      ],
      createdAt: DateTime(2026, 10, 21, 14, 30),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF: blocks never split, long text becomes notes, Thai becomes images', () async {
    final data = fixture();
    final p = plan([for (final d in data) d.$1]);
    final info = PdfLayoutInfo();
    final fonts = await PdfFonts.load(rootBundle.load);
    final bytes = await PdfExport.render(p, [for (final d in data) d.$2],
        t: LanguageController().t, fonts: fonts, palette: ReportsTheme.palette(Brightness.light), renderText: fakeRenderer, info: info);
    // The file stays in build/test_pdf for a visual check (pdftoppm).
    final out = Directory('build/test_pdf')..createSync(recursive: true);
    File('${out.path}/sample.pdf').writeAsBytesSync(bytes);
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(info.pages, greaterThan(3));
    expect(info.cardPages.length, data.length);
    info.cardPages.forEach((card, pages) => expect(pages.$1, pages.$2, reason: 'card $card starts and ends on one page'));
    // Sections start on later pages in order (the cover is page 1).
    expect(info.cardPages[0]!.$1, 2);
    expect(info.cardPages[data.length - 1]!.$1, greaterThan(info.cardPages[2]!.$1));
    // The long provider name of the ranking and the long model name of the table are notes.
    expect(info.notes[1], [longName]);
    expect(info.notes[4], [longName]);
    // Thai values, the Thai section name and the Thai category are images, never PDF text.
    expect(info.imageTexts, containsAll([thaiName, 'ทางหลัก']));
    expect(info.imageTexts.every(ThaiText.has), isTrue);
  });

  test('Thai detection', () {
    expect(ThaiText.has('ถนน'), isTrue);
    expect(ThaiText.has('Provider 1'), isFalse);
    expect(ThaiText.has('Soi ที่ 2'), isTrue);
  });

  test('PDF: Ubuntu Sans has the pt-BR letters and a pt-BR export keeps them as text', () async {
    final font = TtfParser(await rootBundle.load('assets/fonts/UbuntuSans-Variable.ttf'));
    for (final ch in 'çÇãÃõÕáÁàâÂéÉêÊíÍóÓôÔúÚü'.runes) {
      expect(font.charToGlyphIndexMap[ch], isNotNull, reason: 'glyph for ${String.fromCharCode(ch)}');
    }
    final data = fixture().take(2).toList();
    const portuguese = 'Ação, preço e média: São Paulo';
    final base = plan([for (final d in data) d.$1]);
    final p = ExportPlan(
      project: base.project,
      report: base.report,
      lang: 'pt-BR',
      view: base.view,
      projectInfo: base.projectInfo,
      sections: [ExportSection(portuguese, [for (final d in data) d.$1])],
      createdAt: base.createdAt,
    );
    final info = PdfLayoutInfo();
    final fonts = await PdfFonts.load(rootBundle.load);
    final c = LanguageController();
    await c.set(AppLanguage.pt);
    final bytes = await PdfExport.render(p, [for (final d in data) d.$2],
        t: c.t, fonts: fonts, palette: ReportsTheme.palette(Brightness.light), renderText: fakeRenderer, info: info);
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(info.imageTexts, isNot(contains(portuguese)), reason: 'Portuguese is PDF text, not an image');
  });
}
