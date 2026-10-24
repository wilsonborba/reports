import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/report.dart';
import 'export_plan.dart';

/// CSV data of a report: one ZIP with one CSV per chart (the rows of the chart dataset,
/// never raw collections) and `index.csv`. UTF-8 with a byte order mark so Excel shows
/// Thai; plain numbers without thousand separators; header "Label (unit)".
class CsvExport {
  /// Largest number of rows in one chart file.
  static const int maxRows = 5000;

  static const List<int> bom = [0xEF, 0xBB, 0xBF];

  /// RFC 4180 field: quotes around text with a comma, quote or line break; quotes doubled.
  static String escape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String header(FieldInfo f) => f.unit == null || f.unit!.isEmpty ? f.label : '${f.label} (${f.unit})';

  /// Plain value: numbers without separators (decimals from the field), text as it is.
  static String cell(dynamic v, FieldInfo f) {
    if (v == null) return '';
    if (v is int) return '$v';
    if (v is num) {
      final d = v.toDouble();
      if (f.type == 'integer' || f.type == 'hour') return '${d.round()}';
      return _plain(d, f.decimals);
    }
    return '$v';
  }

  static String _plain(double v, int? decimals) {
    if (decimals != null) return v.toStringAsFixed(decimals);
    // Up to 6 decimals, without exponent and without trailing zeros.
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s == '-0' ? '0' : s;
  }

  static String line(Iterable<String> fields) => fields.map(escape).join(',');

  /// The CSV text of a dataset page (lines end with CRLF).
  static String table(DatasetPage page) {
    final fields = page.descriptor.fields;
    final b = StringBuffer()..write(line(fields.map(header)))..write('\r\n');
    for (final r in page.rows) {
      b
        ..write(line([for (final f in fields) cell(r[f.name], f)]))
        ..write('\r\n');
    }
    return b.toString();
  }

  static Uint8List encode(String text) => Uint8List.fromList([...bom, ...utf8.encode(text)]);

  /// File name of card [index] in the ZIP: order number and slot key.
  static String fileName(int index, ExportCard card) =>
      '${(index + 1).toString().padLeft(2, '0')}_${card.slot.key.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}.csv';

  static const List<String> indexColumns = ['file', 'section', 'chart', 'description', 'equation', 'filters', 'rows', 'total_rows', 'data_tier'];

  /// Builds the ZIP. [load] returns all rows of a card (at most [maxRows]) with its filters.
  static Future<ExportFile> build(
    ExportPlan plan, {
    required Future<DatasetPage> Function(ExportCard card) load,
    required ProgressSink progress,
    required Translate t,
  }) async {
    final cards = plan.cards;
    final archive = Archive();
    final index = StringBuffer()..write(line(indexColumns))..write('\r\n');
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      progress(ExportProgress(t('export_loading', {'i': i + 1, 'n': cards.length}), done: i, total: cards.length));
      final page = await load(card);
      final rows = page.rows.length > maxRows ? page.rows.sublist(0, maxRows) : page.rows;
      final limited = DatasetPage(descriptor: page.descriptor, rows: rows, offset: 0, limit: rows.length, totalRows: page.totalRows);
      final name = fileName(i, card);
      archive.addFile(ArchiveFile.bytes(name, encode(table(limited))));
      index
        ..write(line([
          name,
          plan.sections[card.section].name,
          card.descriptor.title,
          card.descriptor.description,
          card.descriptor.equation ?? '',
          describeFilters(card.descriptor, card.filters, t).join('; '),
          '${rows.length}',
          '${page.totalRows > rows.length ? page.totalRows : rows.length}',
          page.descriptor.dataTier,
        ]))
        ..write('\r\n');
    }
    progress(ExportProgress(t('export_building'), done: cards.length, total: cards.length));
    final metadata = jsonEncode({
      'project': plan.project,
      'report': plan.report,
      'language': plan.lang,
      'data_tier': plan.view.dataTier,
      'created_at': plan.createdAt.toIso8601String(),
    });
    archive.addFile(ArchiveFile.bytes('index.csv', encode(index.toString())));
    archive.addFile(ArchiveFile.bytes('metadata.json', encode('$metadata\r\n')));
    return ExportFile('${plan.fileBase}.zip', ZipEncoder().encodeBytes(archive), 'application/zip');
  }
}
