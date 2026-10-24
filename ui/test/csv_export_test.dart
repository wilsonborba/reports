import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/export/csv_export.dart';
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/report.dart';

FieldInfo f(String name, String type, {String? unit, int? decimals, bool dim = false}) =>
    FieldInfo(name: name, label: name.toUpperCase(), type: type, role: dim ? 'dimension' : 'measure', unit: unit, decimals: decimals);

DatasetDescriptor descriptor(String id, {String? equation, List<FilterInfo> filters = const []}) => DatasetDescriptor(
    datasetId: id,
    title: 'Chart $id',
    description: 'About $id, with a comma',
    equation: equation,
    fields: [f('provider', 'string', dim: true), f('volume', 'integer', unit: 'tokens'), f('share', 'percent', unit: '%', decimals: 1)],
    filters: filters);

ExportPlan plan(List<ExportCard> first, List<ExportCard> second) => ExportPlan(
      project: 'cortex',
      report: 'model_usage',
      lang: 'en',
      view: ReportView(project: 'cortex', report: 'model_usage', title: 'Model Usage', description: '', tags: const [], period: null, updatedAt: '', datasets: const []),
      sections: [ExportSection('Tokens', first), ExportSection('Section Two', second)],
      createdAt: DateTime(2026, 10, 21, 9, 5),
    );

void main() {
  final t = LanguageController().t;

  group('escaping', () {
    test('commas, quotes and line breaks are quoted; plain text is not', () {
      expect(CsvExport.escape('Provider 1'), 'Provider 1');
      expect(CsvExport.escape('a,b'), '"a,b"');
      expect(CsvExport.escape('say "hi"'), '"say ""hi"""');
      expect(CsvExport.escape('two\nlines'), '"two\nlines"');
      expect(CsvExport.escape('ผู้ให้บริการหลัก'), 'ผู้ให้บริการหลัก');
    });

    test('numbers are plain, header has the unit', () {
      expect(CsvExport.cell(1234567, f('v', 'integer')), '1234567');
      expect(CsvExport.cell(1234567.0, f('v', 'integer')), '1234567');
      expect(CsvExport.cell(45.678, f('p', 'percent', decimals: 1)), '45.7');
      expect(CsvExport.cell(0.1 + 0.2, f('x', 'float')), '0.3');
      expect(CsvExport.cell(1e-7, f('x', 'float')), '0');
      expect(CsvExport.cell(null, f('x', 'float')), '');
      expect(CsvExport.cell(7, f('h', 'hour')), '7');
      expect(CsvExport.header(f('volume', 'integer', unit: 'tokens')), 'VOLUME (tokens)');
      expect(CsvExport.header(f('provider', 'string')), 'PROVIDER');
    });

    test('UTF-8 with a byte order mark keeps Thai', () {
      final bytes = CsvExport.encode('ถนน\r\n');
      expect(bytes.sublist(0, 3), CsvExport.bom);
      expect(utf8.decode(bytes.sublist(3)), 'ถนน\r\n');
    });

    test('a table has a header line and CRLF line ends', () {
      final page = DatasetPage(descriptor: descriptor('a'), rows: [
        {'provider': 'Anthropic, primary', 'volume': 1200, 'share': 12.345},
      ], offset: 0, limit: 1, totalRows: 1);
      expect(CsvExport.table(page), 'PROVIDER,VOLUME (tokens),SHARE (%)\r\n"Anthropic, primary",1200,12.3\r\n');
    });
  });

  test('ZIP: one CSV per chart in board order plus index.csv with sections and filters', () async {
    final filters = [
      FilterInfo(field: 'task', label: 'Task', type: 'category', options: const [FilterOption('chat', 'Chat'), FilterOption('embed', 'Embedding')]),
      FilterInfo(field: 'date', label: 'Date', type: 'date'),
    ];
    final cards = [
      ExportCard(section: 0, slot: const Slot('volume', visual: Visual.hbar), descriptor: descriptor('volume', equation: 'V = sum(c)', filters: filters),
          filters: const {'f.task': 'chat,embed', 'f.date.from': '2026-10-01', 'f.date.to': '2026-10-05'}),
      ExportCard(section: 1, slot: const Slot('share'), descriptor: descriptor('share')),
    ];
    final steps = <String>[];
    final file = await CsvExport.build(
      plan([cards[0]], [cards[1]]),
      load: (c) async => DatasetPage(
          descriptor: c.descriptor,
          rows: [for (var i = 0; i < (c.slot.datasetId == 'volume' ? 6000 : 3); i++) {'provider': 'R$i', 'volume': i, 'share': 1.0}],
          offset: 0,
          limit: 0,
          totalRows: c.slot.datasetId == 'volume' ? 6000 : 3),
      progress: (p) => steps.add(p.text),
      t: t,
    );
    expect(file.name, 'cortex_model_usage_20261021.zip');
    expect(steps.first, 'Loading chart data 1 of 2');
    final zip = ZipDecoder().decodeBytes(file.bytes);
    expect(zip.files.map((f) => f.name), ['01_volume_hbar.csv', '02_share.csv', 'index.csv', 'metadata.json']);
    String text(String name) => utf8.decode(zip.findFile(name)!.content.sublist(3));
    expect(text('01_volume_hbar.csv').split('\r\n').where((l) => l.isNotEmpty).length, CsvExport.maxRows + 1, reason: 'header plus at most 5,000 rows');
    final index = text('index.csv').split('\r\n');
    expect(index[0], CsvExport.indexColumns.join(','));
    expect(index[1],
        '01_volume_hbar.csv,Tokens,Chart volume,"About volume, with a comma",V = sum(c),"Task: Chat, Embedding; Date: 2026-10-01 to 2026-10-05",5000,6000,sample');
    expect(index[2], startsWith('02_share.csv,Section Two,Chart share,'));
  });
}
