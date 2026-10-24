import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/export/export_plan.dart';
import 'package:reports_ui/export/markdown_export.dart';
import 'package:reports_ui/l10n/strings.dart';
import 'package:reports_ui/layouts/report_layout.dart';
import 'package:reports_ui/models/catalog.dart';
import 'package:reports_ui/models/report.dart';

FieldInfo f(String name, String label, String type, {String? unit, int? decimals, bool dim = false}) =>
    FieldInfo(name: name, label: label, type: type, role: dim ? 'dimension' : 'measure', unit: unit, decimals: decimals);

final ranking = DatasetDescriptor(
  datasetId: 'provider_tokens',
  title: 'Provider Tokens',
  description: 'Tokens of every provider.',
  equation: 'Share = T_provider / T_total * 100%',
  fields: [f('provider', 'Provider', 'string', dim: true), f('volume', 'Volume', 'integer', unit: 'tokens'), f('share', 'Share', 'percent', decimals: 2)],
  filters: const [FilterInfo(field: 'task', label: 'Task', type: 'category', options: [FilterOption('chat', 'Chat')])],
);
final kpi = DatasetDescriptor(
  datasetId: 'overview',
  title: 'Overview',
  description: '',
  equation: null,
  fields: [f('total', 'Total volume', 'integer', unit: 'tokens'), f('days', 'Days', 'integer')],
  filters: const [],
);

DatasetPage page(DatasetDescriptor d, List<Map<String, dynamic>> rows, {int? total}) =>
    DatasetPage(descriptor: d, rows: rows, offset: 0, limit: rows.length, totalRows: total ?? rows.length);

void main() {
  final t = LanguageController().t;
  final view = ReportView(
      project: 'cortex',
      report: 'model_usage',
      title: 'Token Usage',
      description: 'Tokens per provider.',
      tags: const [],
      period: const ReportPeriod('2026-09-26', '2026-10-20'),
      updatedAt: '',
      datasets: [ranking, kpi]);
  final plan = ExportPlan(
    project: 'cortex',
    report: 'model_usage',
    lang: 'en',
    view: view,
    projectInfo: const ProjectSummary(slug: 'cortex', name: 'Cortex', description: '', reportCount: 1),
    sections: [
      ExportSection('Key figures', [ExportCard(section: 0, slot: const Slot('overview'), descriptor: kpi)]),
      ExportSection('Tokens', [
        ExportCard(section: 1, slot: const Slot('provider_tokens', visual: Visual.hbar), descriptor: ranking, filters: const {'f.task': 'chat'}),
      ]),
    ],
    createdAt: DateTime(2026, 10, 21, 14, 30),
  );
  final longName = 'OpenRouter, the fallback provider for every model of the pool';
  final md = MarkdownExport.render(plan, [
    page(kpi, [
      {'total': 4599892, 'days': 16}
    ]),
    page(ranking, [
      {'provider': longName, 'volume': 989536, 'share': 13.661},
      for (var i = 1; i < 30; i++) {'provider': 'Provider | $i', 'volume': 1000 - i, 'share': 1.0},
    ], total: 40),
  ], t);

  test('head block: title, project, period, creation time, language and provenance', () {
    expect(md, startsWith('# Token Usage\n\nTokens per provider.\n\n- Project: Cortex\n- Period: 2026-09-26 to 2026-10-20\n- Created: 2026-10-21 14:30\n- Language: English\n- Data provenance: Sample / simulation\n'));
  });

  test('sections keep the user names and the board order', () {
    expect(md.indexOf('## Key figures'), lessThan(md.indexOf('## Tokens')));
    expect(md.indexOf('### Overview'), lessThan(md.indexOf('### Provider Tokens')));
  });

  test('numbers are formatted with units; KPI cards list one field per line', () {
    expect(md, contains('| Total volume | 4,599,892 tokens |'));
    expect(md, contains('| Provider | Volume (tokens) | Share |'));
    expect(md, contains('| --- | ---: | ---: |'));
    expect(md, contains('| 989,536 | 13.66% |'));
  });

  test('long cell text moves to a footnote and is never cut', () {
    expect(md, contains('| [^1] | 989,536 | 13.66% |'));
    expect(md, contains('[^1]: $longName'));
    expect(md, isNot(contains('...')));
    expect(md, isNot(contains('…')));
  });

  test('preview rows of the card, the row note and escaped pipes', () {
    final rows = md.split('\n').where((l) => l.startsWith('| ') && l.contains('Provider \\| ')).length;
    expect(rows, 9, reason: 'a ranking card shows 10 rows: the long name and 9 more');
    expect(md, contains('_10 of 40 rows. The CSV data has all rows._'));
  });

  test('active filters and the equation in a code span', () {
    expect(md, contains('Active filters:\n\n- Task: Chat\n'));
    expect(md, contains('Equation: `Share = T_provider / T_total * 100%`'));
  });

  test('Thai text in Thai exports', () {
    final th = MarkdownExport.render(plan, [
      page(kpi, [
        {'total': 1, 'days': 1}
      ]),
      page(ranking, [
        {'provider': 'ผู้ให้บริการหลัก', 'volume': 1, 'share': 1.0}
      ]),
    ], LanguageController(initial: AppLanguage.th).t);
    expect(th, contains('- โครงการ: Cortex'));
    expect(th, contains('ผู้ให้บริการหลัก'));
  });

  test('pt-BR exports use Portuguese text and pt-BR number separators, also from an English screen', () {
    final ptPlan = ExportPlan(
      project: plan.project,
      report: plan.report,
      lang: 'pt-BR',
      view: plan.view,
      projectInfo: plan.projectInfo,
      sections: plan.sections,
      createdAt: plan.createdAt,
    );
    final pt = MarkdownExport.render(ptPlan, [
      page(kpi, [
        {'total': 4599892, 'days': 16}
      ]),
      page(ranking, [
        {'provider': 'ollama', 'volume': 1200, 'share': 12.345}
      ]),
    ], LanguageController(initial: AppLanguage.pt).t);
    expect(pt, contains('- Projeto: Cortex'));
    expect(pt, contains('4.599.892 tokens'));
    expect(pt, contains('12,35%'));
    LanguageController();
    expect(MarkdownExport.render(plan, [
      page(kpi, [
        {'total': 4599892, 'days': 16}
      ]),
      page(ranking, const []),
    ], t), contains('4,599,892 tokens'), reason: 'the English export keeps English separators');
  });
}
