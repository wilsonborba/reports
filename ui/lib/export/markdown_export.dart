import 'dart:convert';
import 'dart:typed_data';
import '../models/report.dart';
import '../widgets/charts/format.dart';
import 'export_plan.dart';
import 'export_rows.dart';

/// Markdown of a report: a head block, then the sections with the user names in board
/// order. Each card: title, description, short table, equation in a code span and the
/// active filters. Long cell text moves to a GitHub footnote; nothing is cut.
class MarkdownExport {
  /// Cells longer than this become a footnote.
  static const int maxCell = 48;

  /// Table cell text: pipes escaped, line breaks as spaces.
  static String cellText(String s) => s.replaceAll('\\', '\\\\').replaceAll('|', '\\|').replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

  static String header(FieldInfo f) => f.unit == null || f.unit!.isEmpty || f.unit == '%' ? f.label : '${f.label} (${f.unit})';

  static String value(dynamic v, FieldInfo f) => valueText(v, f) + (f.unit == '%' && v is num && !valueText(v, f).endsWith('%') ? '%' : '');

  /// The document for loaded [pages] (one per card, in plan order), with the number
  /// separators of the plan language.
  static String render(ExportPlan plan, List<DatasetPage> pages, Translate t) => withNumberLanguage(plan.lang, () => _render(plan, pages, t));

  static String _render(ExportPlan plan, List<DatasetPage> pages, Translate t) {
    final out = StringBuffer();
    final notes = <String>[];
    String cell(String raw) {
      final text = cellText(raw);
      if (text.length <= maxCell) return text;
      notes.add(text);
      return '[^${notes.length}]';
    }

    final view = plan.view;
    out.writeln('# ${view.title}');
    out.writeln();
    if (view.description.isNotEmpty) {
      out.writeln(view.description);
      out.writeln();
    }
    out.writeln('- ${t('md_project')}: ${plan.projectName}');
    if (view.period != null) out.writeln('- ${t('period')}: ${t('date_range', {'start': view.period!.start, 'end': view.period!.end})}');
    out.writeln('- ${t('md_created')}: ${plan.createdText}');
    out.writeln('- ${t('md_language')}: ${t('language_name')}');
    out.writeln('- ${t('md_data_tier')}: ${t('data_tier_${view.dataTier}')}');
    var i = 0;
    for (final section in plan.sections) {
      out.writeln();
      out.writeln('## ${section.name}');
      for (final card in section.cards) {
        final page = pages[i++];
        final d = card.descriptor;
        out.writeln();
        out.writeln('### ${d.title}');
        out.writeln();
        if (d.description.isNotEmpty) {
          out.writeln(d.description);
          out.writeln();
        }
        final filters = describeFilters(d, card.filters, t);
        if (filters.isNotEmpty) {
          out.writeln('${t('md_filters')}:');
          out.writeln();
          for (final f in filters) {
            out.writeln('- $f');
          }
          out.writeln();
        }
        final fields = page.descriptor.fields;
        if (page.rows.isEmpty || fields.isEmpty) {
          out.writeln('_${t('no_data')}_');
          out.writeln();
        } else if (ExportRows.isKpi(page, card.slot)) {
          final row = page.rows.first;
          out.writeln('| ${t('md_measure')} | ${t('md_value')} |');
          out.writeln('| --- | ---: |');
          for (final f in fields) {
            out.writeln('| ${cell(f.label)} | ${cell(valueWithUnit(row[f.name], f))} |');
          }
          out.writeln();
        } else {
          final rows = ExportRows.preview(page, card.slot);
          out.writeln('| ${fields.map((f) => cell(header(f))).join(' | ')} |');
          out.writeln('| ${fields.map((f) => f.isNumeric && !f.isDimension ? '---:' : '---').join(' | ')} |');
          for (final r in rows) {
            out.writeln('| ${fields.map((f) => cell(value(r[f.name], f))).join(' | ')} |');
          }
          out.writeln();
          final total = ExportRows.total(page);
          if (total > rows.length) {
            out.writeln('_${t('md_rows_note', {'shown': numberText(rows.length, 0), 'total': numberText(total, 0)})}_');
            out.writeln();
          }
        }
        if (d.equation != null && d.equation!.isNotEmpty) {
          // A code span: backticks inside the equation get a longer fence.
          final fence = d.equation!.contains('`') ? '`` ' : '`';
          final close = d.equation!.contains('`') ? ' ``' : '`';
          out.writeln('${t('equation')}: $fence${d.equation}$close');
          out.writeln();
        }
      }
    }
    if (notes.isNotEmpty) {
      out.writeln('---');
      out.writeln();
      for (var n = 0; n < notes.length; n++) {
        out.writeln('[^${n + 1}]: ${notes[n]}');
      }
    }
    return out.toString();
  }

  static Future<ExportFile> build(
    ExportPlan plan, {
    required Future<DatasetPage> Function(ExportCard card) load,
    required ProgressSink progress,
    required Translate t,
  }) async {
    final cards = plan.cards;
    final pages = <DatasetPage>[];
    for (var i = 0; i < cards.length; i++) {
      progress(ExportProgress(t('export_loading', {'i': i + 1, 'n': cards.length}), done: i, total: cards.length));
      pages.add(await load(cards[i]));
    }
    progress(ExportProgress(t('export_building'), done: cards.length, total: cards.length));
    return ExportFile('${plan.fileBase}.md', Uint8List.fromList(utf8.encode(render(plan, pages, t))), 'text/markdown');
  }
}
