import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../layouts/report_layout.dart';
import '../models/report.dart';
import '../themes/report_palette.dart';
import '../widgets/charts/chart_parts.dart' show YRange;
import '../widgets/charts/format.dart';
import '../widgets/charts/sankey_layout.dart';
import '../widgets/charts/series_colors.dart' show foldCategories, otherKey;
import '../widgets/charts/visual_chooser.dart';
import 'export_plan.dart';
import 'export_rows.dart';
import 'thai_text.dart';

/// Fonts of the PDF: Ubuntu Sans (regular and semibold) and Ubuntu Sans Mono.
class PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font mono;

  const PdfFonts(this.regular, this.bold, this.mono);

  static Future<PdfFonts> load(Future<ByteData> Function(String asset) asset) async => PdfFonts(
        pw.Font.ttf(await asset('assets/fonts/UbuntuSans-Variable.ttf')),
        pw.Font.ttf(await asset('assets/fonts/UbuntuSans-Variable.ttf')),
        pw.Font.ttf(await asset('assets/fonts/UbuntuSansMono-Variable.ttf')),
      );
}

/// PDF report: A4 portrait. A cover with logo, title, project, period, creation time,
/// language and the contents with page numbers; then one block per card (title, chart,
/// short table, notes, equation) that never splits across pages. Texts are English;
/// Thai text becomes an image (see [ThaiText]). Long cell text becomes a numbered note.
/// Colors: dark text on white; the project color only for bands, bars and table headers.
class PdfExport {
  static final PdfPageFormat format = PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 30, marginBottom: 30);

  static double get contentWidth => format.availableWidth;

  /// Cells longer than this become a note.
  static const int maxCell = 40;

  static Future<ExportFile> build(
    ExportPlan plan, {
    required Future<DatasetPage> Function(ExportCard card) load,
    required ProgressSink progress,
    required Translate t,
    required PdfFonts fonts,
    required ReportPalette palette,
    required TextImageRenderer renderText,
    Uint8List? logo,
  }) async {
    final cards = plan.cards;
    final pages = <DatasetPage>[];
    for (var i = 0; i < cards.length; i++) {
      progress(ExportProgress(t('export_loading', {'i': i + 1, 'n': cards.length}), done: i, total: cards.length));
      pages.add(await load(cards[i]));
    }
    final bytes = await render(plan, pages,
        t: t, fonts: fonts, palette: palette, renderText: renderText, logo: logo, progress: progress);
    return ExportFile('${plan.fileBase}.pdf', bytes, 'application/pdf');
  }

  /// The PDF bytes for loaded [pages] (one per card, in plan order).
  static Future<Uint8List> render(
    ExportPlan plan,
    List<DatasetPage> pages, {
    required Translate t,
    required PdfFonts fonts,
    required ReportPalette palette,
    required TextImageRenderer renderText,
    Uint8List? logo,
    ProgressSink? progress,
    PdfLayoutInfo? info,
  }) =>
      withNumberLanguage(plan.lang,
          () => _render(plan, pages, t: t, fonts: fonts, palette: palette, renderText: renderText, logo: logo, progress: progress, info: info));

  static Future<Uint8List> _render(
    ExportPlan plan,
    List<DatasetPage> pages, {
    required Translate t,
    required PdfFonts fonts,
    required ReportPalette palette,
    required TextImageRenderer renderText,
    Uint8List? logo,
    ProgressSink? progress,
    PdfLayoutInfo? info,
  }) async {
    Object? lastError;
    // A block that does not fit one page gets the compact form (smaller chart, fewer rows).
    for (final compact in [false, true]) {
      final b = _Builder(plan, pages, t, fonts, palette, compact: compact, logo: _imageOrNull(logo));
      // Collect the Thai texts, draw them, then lay out twice: the first pass finds the
      // first page of each section for the contents and the page headers.
      b.collecting = true;
      b.document();
      b.collecting = false;
      var n = 0;
      for (final need in b.needs.values) {
        n++;
        progress?.call(ExportProgress(t('export_drawing', {'i': n, 'n': b.needs.length}), done: n, total: b.needs.length));
        b.images[need.key] = await renderText(need.text, fontSize: need.size, bold: need.bold, maxWidth: need.maxWidth, color: need.color);
      }
      progress?.call(ExportProgress(t('export_building')));
      try {
        await b.document().save();
        b.sectionPages = Map.of(b.marks);
        final doc = b.document();
        final bytes = await doc.save();
        if (info != null) {
          info.cardPages.addAll(b.cardPages);
          info.notes.addAll(b.cardNotes);
          info.imageTexts.addAll(b.needs.values.map((n) => n.text));
          info.pages = doc.document.pdfPageList.pages.length;
        }
        return bytes;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError!;
  }

  static Uint8List? _imageOrNull(Uint8List? b) {
    if (b == null || b.length < 4) return null;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8;
    return png || jpeg ? b : null;
  }
}

/// Layout facts of a generated PDF, for tests: the first and last page of each card
/// block, the notes of each card and the texts drawn as images.
class PdfLayoutInfo {
  final Map<int, (int, int)> cardPages = {};
  final Map<int, List<String>> notes = {};
  final Set<String> imageTexts = {};
  int pages = 0;
}

class _Need {
  final String key;
  final String text;
  final double size;
  final bool bold;
  final double maxWidth;
  final int color;

  const _Need(this.key, this.text, this.size, this.bold, this.maxWidth, this.color);
}

/// Records the page where it is laid out (section starts for the contents).
class _PageMark extends pw.Widget {
  final void Function(int page) onPage;

  _PageMark(this.onPage);

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints, {bool parentUsesSize = false}) {
    box = PdfRect.zero;
    onPage(context.pageNumber);
  }
}

class _Builder {
  final ExportPlan plan;
  final List<DatasetPage> pages;
  final Translate t;
  final PdfFonts fonts;
  final ReportPalette palette;
  final bool compact;
  final Uint8List? logo;

  bool collecting = false;
  final Map<String, _Need> needs = {};
  final Map<String, TextImage> images = {};
  final Map<int, int> marks = {};
  Map<int, int> sectionPages = {};
  final Map<int, (int, int)> cardPages = {};
  final Map<int, List<String>> cardNotes = {};

  _Builder(this.plan, this.pages, this.t, this.fonts, this.palette, {required this.compact, this.logo});

  static final PdfColor ink = PdfColor.fromHex('#161616');
  static final PdfColor muted = PdfColor.fromHex('#525252');
  static final PdfColor line = PdfColor.fromHex('#C6C6C6');
  static final PdfColor grid = PdfColor.fromHex('#E0E0E0');

  static PdfColor pdf(Color c) => PdfColor.fromInt(c.toARGB32());

  PdfColor get accent => pdf(palette.accent);

  /// The project color mixed with white: table headers with dark text.
  PdfColor get headerFill {
    final a = palette.accent;
    double mix(double c) => c * 0.28 + 0.72;
    return PdfColor(mix(a.r), mix(a.g), mix(a.b));
  }

  PdfColor series(int i) => pdf(palette.seriesAt(i));

  double get inner => PdfExport.contentWidth - 20;

  // -- Text ---------------------------------------------------------------------------

  /// Text in the PDF font, or an image of the text when it has Thai letters.
  pw.Widget text(String s, {double size = 9, bool bold = false, PdfColor? color, double? maxWidth, pw.TextAlign align = pw.TextAlign.left, bool mono = false}) {
    final c = color ?? ink;
    final width = maxWidth ?? inner;
    if (ThaiText.has(s)) {
      final key = '$size|$bold|${width.toStringAsFixed(1)}|${c.toInt()}|$s';
      if (collecting) {
        needs.putIfAbsent(key, () => _Need(key, s, size, bold, width, c.toInt()));
        return pw.SizedBox(height: size * 1.3);
      }
      final img = images[key];
      if (img == null) return pw.SizedBox(height: size * 1.3);
      final image = pw.Image(pw.MemoryImage(img.png), width: img.width, height: img.height);
      // The image keeps its own size; the box around it keeps the column width.
      return pw.Align(alignment: align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft, child: image);
    }
    return pw.Text(s,
        textAlign: align,
        style: pw.TextStyle(font: mono ? fonts.mono : (bold ? fonts.bold : fonts.regular), fontSize: size, color: c, lineSpacing: size * 0.15));
  }

  String sectionName(int i) => plan.sections[i].name;

  int sectionAt(int page) {
    var current = 0;
    sectionPages.forEach((section, start) {
      if (start <= page && section > current) current = section;
    });
    return current;
  }

  // -- Document -----------------------------------------------------------------------

  pw.Document document() {
    marks.clear();
    cardPages.clear();
    final view = plan.view;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      title: view.title,
      author: plan.projectName,
      creator: 'Reports',
    );
    if (collecting) {
      // Header and contents texts of every section.
      for (var i = 0; i < plan.sections.length; i++) {
        text(sectionName(i), size: 7.5, color: muted, maxWidth: 240);
        text(sectionName(i), size: 10, maxWidth: inner - 40);
        text(sectionName(i), size: 15, bold: true, maxWidth: inner);
      }
      text(view.title, size: 7.5, color: muted, maxWidth: 260);
      text(footerText(), size: 7.5, color: muted, maxWidth: 300);
      cover();
    }
    doc.addPage(pw.Page(pageFormat: PdfExport.format, build: (_) => cover()));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfExport.format,
      maxPages: 1000,
      header: header,
      footer: footer,
      build: (_) => content(),
    ));
    if (collecting) content();
    return doc;
  }

  pw.Widget cover() {
    final view = plan.view;
    final rows = <(String, String)>[
      (t('md_project'), plan.projectName),
      if (view.period != null) (t('period'), t('date_range', {'start': view.period!.start, 'end': view.period!.end})),
      (t('md_created'), plan.createdText),
      (t('md_language'), t('pdf_language_note')),
      (t('md_data_tier'), t('data_tier_${view.dataTier}')),
    ];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(height: 6, color: accent),
      pw.SizedBox(height: 28),
      if (logo != null) ...[
        pw.SizedBox(height: 56, child: pw.Image(pw.MemoryImage(logo!), fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft)),
        pw.SizedBox(height: 20),
      ],
      text(view.title, size: 26, bold: true),
      if (view.description.isNotEmpty) ...[pw.SizedBox(height: 8), text(view.description, size: 11, color: muted)],
      pw.SizedBox(height: 22),
      for (final (k, v) in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 90, child: text(k, size: 9.5, color: muted, maxWidth: 90)),
            pw.Expanded(child: text(v, size: 9.5, maxWidth: inner - 90)),
          ]),
        ),
      pw.SizedBox(height: 28),
      text(t('pdf_contents'), size: 13, bold: true),
      pw.SizedBox(height: 8),
      for (var i = 0; i < plan.sections.length; i++)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5))),
          child: pw.Row(children: [
            pw.Expanded(child: text(sectionName(i), size: 10, maxWidth: inner - 40)),
            pw.SizedBox(width: 40, child: text('${sectionPages[i] ?? ''}', size: 10, align: pw.TextAlign.right, maxWidth: 40)),
          ]),
        ),
    ]);
  }

  pw.Widget header(pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5))),
        child: pw.Row(children: [
          pw.Expanded(child: text(plan.view.title, size: 7.5, color: muted, maxWidth: 260)),
          text(sectionName(sectionAt(context.pageNumber)), size: 7.5, color: muted, maxWidth: 240),
        ]),
      );

  String footerText() {
    final view = plan.view;
    final period = view.period == null ? '' : '  ·  ${t('date_range', {'start': view.period!.start, 'end': view.period!.end})}';
    return '${plan.projectName}$period';
  }

  pw.Widget footer(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(children: [
        pw.Expanded(child: text(footerText(), size: 7.5, color: muted, maxWidth: 300)),
        text(t('page_of', {'page': context.pageNumber, 'pages': context.pagesCount}), size: 7.5, color: muted, maxWidth: 120),
      ]),
    );
  }

  List<pw.Widget> content() {
    final out = <pw.Widget>[];
    var k = 0;
    for (var s = 0; s < plan.sections.length; s++) {
      final section = plan.sections[s];
      final heading = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _PageMark((page) => marks[s] = page),
        pw.Row(children: [
          pw.Container(width: 4, height: 18, color: accent),
          pw.SizedBox(width: 8),
          pw.Expanded(child: text(section.name, size: 15, bold: true, maxWidth: inner)),
        ]),
        pw.SizedBox(height: 10),
      ]);
      if (section.cards.isEmpty) {
        out.add(pw.Inseparable(child: heading));
        continue;
      }
      for (var c = 0; c < section.cards.length; c++) {
        final block = card(section.cards[c], pages[k], k);
        k++;
        // The heading stays with the first card of its section; a block never splits
        // (a column can span pages unless it is inseparable).
        out.add(pw.Inseparable(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: c == 0 ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [heading, block]) : block,
          ),
        ));
      }
    }
    return out;
  }

  // -- Card block ---------------------------------------------------------------------

  pw.Widget card(ExportCard card, DatasetPage page, int index) {
    final d = card.descriptor;
    final notes = cardNotes[index] = <String>[];
    final visual = page.rows.isEmpty ? Visual.table : VisualChooser.resolve(page, card.slot);
    final filters = describeFilters(d, card.filters, t);
    final body = <pw.Widget>[
      text(d.title, size: 11.5, bold: true),
      if (d.description.isNotEmpty) ...[pw.SizedBox(height: 2), text(d.description, size: 8, color: muted)],
      if (filters.isNotEmpty) ...[pw.SizedBox(height: 3), text('${t('md_filters')}: ${filters.join('; ')}', size: 7.5, color: muted)],
      pw.SizedBox(height: 8),
    ];
    if (page.rows.isEmpty) {
      body.add(text(t('no_data'), size: 8.5, color: muted));
    } else {
      final chart = this.chart(visual, page, card.slot, notes);
      if (chart != null) body.addAll([chart, pw.SizedBox(height: 8)]);
      if (visual != Visual.kpi && visual != Visual.hbar && visual != Visual.donut) {
        body.add(table(page, card.slot, notes));
      }
    }
    if (notes.isNotEmpty) {
      body.add(pw.SizedBox(height: 6));
      for (var i = 0; i < notes.length; i++) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 18, child: text('[${i + 1}]', size: 7, color: muted, maxWidth: 18)),
            pw.Expanded(child: text(notes[i], size: 7, color: muted, maxWidth: inner - 18)),
          ]),
        ));
      }
    }
    if (d.equation != null && d.equation!.isNotEmpty) {
      body.addAll([
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: grid, width: 0.5))),
          child: text(d.equation!, size: 7.5, color: muted, mono: true),
        ),
      ]);
    }
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _PageMark((page) => cardPages[index] = (page, cardPages[index]?.$2 ?? page)),
        pw.Container(height: 2.5, color: accent),
        pw.Padding(padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 10), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: body)),
        _PageMark((page) => cardPages[index] = (cardPages[index]?.$1 ?? page, page)),
      ]),
    );
  }

  /// A cell value: the text, or a note mark when the text is long.
  String cell(String v, List<String> notes) {
    if (v.length <= PdfExport.maxCell) return v;
    notes.add(v);
    return '[${notes.length}]';
  }

  pw.Widget table(DatasetPage page, Slot slot, List<String> notes) {
    final fields = page.descriptor.fields;
    if (fields.isEmpty) return pw.SizedBox();
    final many = fields.length > 6;
    final limit = compact ? 6 : (many ? 10 : ExportRows.limitFor(page, slot));
    final rows = page.rows.length > limit ? page.rows.sublist(0, limit) : page.rows;
    final size = many ? 6.5 : 7.5;
    bool numeric(FieldInfo f) => f.isNumeric && !f.isDimension;
    String head(FieldInfo f) => f.unit == null || f.unit!.isEmpty || f.unit == '%' ? f.label : '${f.label} (${f.unit})';
    final texts = [for (final r in rows) [for (final f in fields) valueText(r[f.name], f)]];
    // Column widths from the text lengths, at least 36 points.
    final lengths = [
      for (var c = 0; c < fields.length; c++)
        math.max(math.min(head(fields[c]).length, 18), texts.fold<int>(4, (m, r) => math.max(m, math.min(r[c].length, PdfExport.maxCell)))).toDouble()
    ];
    final sum = lengths.fold<double>(0, (a, b) => a + b);
    // A column is at least as wide as the longest word of its header (no word breaks).
    double minWidth(FieldInfo f) =>
        math.max(36.0, head(f).split(RegExp(r'\s+')).fold<int>(0, (m, w) => math.max(m, w.length)) * size * 0.58 + 8);
    var widths = [for (var c = 0; c < fields.length; c++) math.max(minWidth(fields[c]), inner * lengths[c] / sum)];
    final scale = inner / widths.fold<double>(0, (a, b) => a + b);
    widths = [for (final w in widths) w * scale];
    pw.Widget box(pw.Widget child, double w, bool right) =>
        pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5), alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft, child: child);
    final total = ExportRows.total(page);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Table(
        columnWidths: {for (var c = 0; c < fields.length; c++) c: pw.FixedColumnWidth(widths[c])},
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: grid, width: 0.4), bottom: pw.BorderSide(color: line, width: 0.5)),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: headerFill),
            children: [
              for (var c = 0; c < fields.length; c++)
                box(text(head(fields[c]), size: size, bold: true, maxWidth: widths[c] - 6, align: numeric(fields[c]) ? pw.TextAlign.right : pw.TextAlign.left), widths[c], numeric(fields[c])),
            ],
          ),
          for (final r in texts)
            pw.TableRow(children: [
              for (var c = 0; c < fields.length; c++)
                box(text(cell(r[c], notes), size: size, maxWidth: widths[c] - 6, align: numeric(fields[c]) ? pw.TextAlign.right : pw.TextAlign.left), widths[c],
                    numeric(fields[c])),
            ]),
        ],
      ),
      if (total > rows.length) ...[
        pw.SizedBox(height: 3),
        text(t('md_rows_note', {'shown': numberText(rows.length, 0), 'total': numberText(total, 0)}), size: 7, color: muted),
      ],
    ]);
  }

  // -- Charts -------------------------------------------------------------------------

  double get chartHeight => compact ? 90 : 140;

  pw.Widget? chart(Visual visual, DatasetPage page, Slot slot, List<String> notes) {
    final d = page.descriptor;
    final dims = VisualChooser.dimensions(d);
    final ms = VisualChooser.slotMeasures(d, slot);
    switch (visual) {
      case Visual.kpi:
        return kpi(page);
      case Visual.hbar:
      case Visual.donut:
        final (main, second) = VisualChooser.ranked(d, slot);
        final limit = compact ? 6 : ExportRows.limitFor(page, slot);
        return bars(page.rows.length > limit ? page.rows.sublist(0, limit) : page.rows, dims.first, main, second, notes, ExportRows.total(page));
      case Visual.line:
      case Visual.curve:
        final x = dims.isNotEmpty ? dims.first : d.fields.first;
        return lines(page, x, ms, numericX: visual == Visual.curve);
      case Visual.bar:
        return columns(page, dims.first, ms.first, series(0));
      case Visual.combo:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          text(labelWithUnit(ms[0]), size: 7.5, color: muted),
          columns(page, dims.first, ms[0], series(0), height: chartHeight * 0.6),
          pw.SizedBox(height: 6),
          text(labelWithUnit(ms[1]), size: 7.5, color: muted),
          columns(page, dims.first, ms[1], series(1), height: chartHeight * 0.6),
        ]);
      case Visual.stackedBar:
        return stacked(page, dims[0], dims[1], ms.first);
      case Visual.map:
        return map(page, ms.first);
      case Visual.sankey:
        return sankey(page, VisualChooser.sankeyStages(d, slot), ms.first, notes);
      case Visual.table:
      case Visual.auto:
        return null;
    }
  }

  pw.Widget kpi(DatasetPage page) {
    final row = page.rows.first;
    final fields = page.descriptor.fields;
    final per = fields.length >= 3 ? 3 : fields.length;
    final w = (inner - (per - 1) * 6) / per;
    return pw.Wrap(spacing: 6, runSpacing: 6, children: [
      for (final f in fields)
        pw.Container(
          width: w,
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 7),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F4F4F4'), border: pw.Border(left: pw.BorderSide(color: accent, width: 2))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            text(f.label, size: 7, color: muted, maxWidth: w - 16),
            pw.SizedBox(height: 2),
            text(valueWithUnit(row[f.name], f), size: 13, bold: true, maxWidth: w - 16),
          ]),
        ),
    ]);
  }

  /// Ranking rows: rank, label, bar, value (one color). Donuts print as bars too.
  pw.Widget bars(List<Map<String, dynamic>> rows, FieldInfo label, FieldInfo measure, FieldInfo? second, List<String> notes, int total) {
    final maxV = rows.fold<double>(0, (m, r) => math.max(m, asDouble(r[measure.name]) ?? 0));
    const labelW = 170.0, valueW = 110.0, rankW = 16.0;
    final barW = inner - labelW - valueW - rankW - 12;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (var i = 0; i < rows.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
          child: pw.Row(children: [
            pw.SizedBox(width: rankW, child: text('${i + 1}', size: 7, color: muted, maxWidth: rankW)),
            pw.SizedBox(width: labelW, child: text(cell(valueText(rows[i][label.name], label), notes), size: 7.5, maxWidth: labelW - 4)),
            pw.SizedBox(width: 6),
            pw.Container(
              width: maxV <= 0 ? 0 : math.max(1.0, barW * (asDouble(rows[i][measure.name]) ?? 0) / maxV),
              height: 6,
              color: series(0),
            ),
            pw.Spacer(),
            pw.SizedBox(
              width: valueW,
              child: text(
                [valueWithUnit(rows[i][measure.name], measure), if (second != null) valueWithUnit(rows[i][second.name], second)].join('  '),
                size: 7.5,
                align: pw.TextAlign.right,
                maxWidth: valueW,
              ),
            ),
          ]),
        ),
      if (total > rows.length) ...[
        pw.SizedBox(height: 3),
        text(t('md_rows_note', {'shown': numberText(rows.length, 0), 'total': numberText(total, 0)}), size: 7, color: muted),
      ],
    ]);
  }

  static const double axisW = 34;

  /// Plot frame: y labels on the left (min, middle, max), the marks, x labels below.
  pw.Widget plot({required double height, required YRange range, required List<String> xLabels, required bool centered, required void Function(PdfGraphics g, double w, double Function(double v) y) paint}) {
    final w = inner - axisW;
    double y(double v) => (v - range.min) / (range.max - range.min) * height;
    final ticks = [range.min, (range.min + range.max) / 2, range.max];
    final n = xLabels.length;
    final step = (n / 6).ceil().clamp(1, 1 << 20);
    double xAt(int i) => centered ? (i + 0.5) * w / n : (n <= 1 ? w / 2 : i * w / (n - 1));
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(
        width: axisW,
        height: height,
        child: pw.Stack(overflow: pw.Overflow.visible, children: [
          for (final v in ticks)
            pw.Positioned(
              right: 4,
              bottom: (y(v) - 4).clamp(-4.0, height - 4),
              child: text(compactNumber(v), size: 6.5, color: muted, maxWidth: axisW - 4),
            ),
        ]),
      ),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(
          width: w,
          height: height,
          child: pw.CustomPaint(
            size: PdfPoint(w, height),
            painter: (g, size) {
              g
                ..setStrokeColor(grid)
                ..setLineWidth(0.4);
              for (final v in ticks) {
                g
                  ..moveTo(0, y(v))
                  ..lineTo(w, y(v))
                  ..strokePath();
              }
              paint(g, w, y);
            },
          ),
        ),
        pw.SizedBox(
          width: w,
          height: 11,
          child: pw.Stack(overflow: pw.Overflow.visible, children: [
            for (var i = 0; i < n; i += step)
              pw.Positioned(
                left: (xAt(i) - 24).clamp(0.0, math.max(0.0, w - 48)),
                top: 2,
                child: pw.SizedBox(width: 48, child: pw.Text(xLabels[i], textAlign: pw.TextAlign.center, style: pw.TextStyle(font: fonts.regular, fontSize: 6.5, color: muted))),
              ),
          ]),
        ),
      ]),
    ]);
  }

  /// X labels never hold Thai: dates, hours and numbers. Other text labels use the row number.
  List<String> xLabels(List<Map<String, dynamic>> rows, FieldInfo x) => [
        for (var i = 0; i < rows.length; i++)
          () {
            final s = ChartLabel.of(rows[i][x.name], x);
            return ThaiText.has(s) ? '${i + 1}' : s;
          }(),
      ];

  pw.Widget columns(DatasetPage page, FieldInfo x, FieldInfo m, PdfColor color, {double? height}) {
    final rows = page.rows;
    final values = [for (final r in rows) asDouble(r[m.name]) ?? 0];
    final range = YRange.of(values, zero: true);
    return plot(
      height: height ?? chartHeight,
      range: range,
      xLabels: xLabels(rows, x),
      centered: true,
      paint: (g, w, y) {
        final slot = w / math.max(1, values.length);
        final bw = math.max(0.6, slot * 0.7);
        g.setFillColor(color);
        for (var i = 0; i < values.length; i++) {
          final y0 = y(0), y1 = y(values[i]);
          g.drawRect(i * slot + (slot - bw) / 2, math.min(y0, y1), bw, (y1 - y0).abs());
        }
        g.fillPath();
      },
    );
  }

  pw.Widget legend(List<(String, PdfColor)> items) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Wrap(spacing: 10, runSpacing: 3, children: [
          for (final (name, color) in items)
            pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Container(width: 7, height: 7, color: color),
              pw.SizedBox(width: 3),
              text(name, size: 7, maxWidth: 160),
            ]),
        ]),
      );

  pw.Widget lines(DatasetPage page, FieldInfo x, List<FieldInfo> ms, {required bool numericX}) {
    final rows = page.rows;
    final shown = ms.take(ReportPalette.slots).toList();
    final range = YRange.of([
      for (final m in shown)
        for (final r in rows)
          if (asDouble(r[m.name]) != null) asDouble(r[m.name])!
    ]);
    final xs = [for (var i = 0; i < rows.length; i++) numericX ? (asDouble(rows[i][x.name]) ?? i.toDouble()) : i.toDouble()];
    final minX = xs.isEmpty ? 0.0 : xs.reduce(math.min), maxX = xs.isEmpty ? 1.0 : xs.reduce(math.max);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      plot(
        height: chartHeight,
        range: range,
        xLabels: numericX ? [for (final v in xs) compactNumber(v)] : xLabels(rows, x),
        centered: false,
        paint: (g, w, y) {
          double px(double v) => maxX <= minX ? w / 2 : (v - minX) / (maxX - minX) * w;
          for (var m = 0; m < shown.length; m++) {
            g
              ..setStrokeColor(series(m))
              ..setLineWidth(1.2);
            var started = false;
            for (var i = 0; i < rows.length; i++) {
              final v = asDouble(rows[i][shown[m].name]);
              if (v == null) {
                started = false;
                continue;
              }
              started ? g.lineTo(px(xs[i]), y(v)) : g.moveTo(px(xs[i]), y(v));
              started = true;
            }
            g.strokePath();
          }
        },
      ),
      if (shown.length > 1) legend([for (var m = 0; m < shown.length; m++) (labelWithUnit(shown[m]), series(m))]),
    ]);
  }

  pw.Widget stacked(DatasetPage page, FieldInfo x, FieldInfo category, FieldInfo m) {
    final xs = <String, dynamic>{};
    final totals = <String, double>{};
    final values = <String, Map<String, double>>{};
    final names = <String, String>{};
    for (final r in page.rows) {
      final xk = '${r[x.name]}', ck = '${r[category.name]}';
      xs.putIfAbsent(xk, () => r[x.name]);
      names[ck] = valueText(r[category.name], category);
      final v = asDouble(r[m.name]) ?? 0;
      totals[ck] = (totals[ck] ?? 0) + v;
      (values[xk] ??= {})[ck] = (values[xk]?[ck] ?? 0) + v;
    }
    final cats = foldCategories(totals.keys.toList(), totals, ReportPalette.slots - 1);
    final kept = cats.where((c) => c != otherKey).toSet();
    final xKeys = xs.keys.toList();
    double valueOf(String xk, String c) =>
        c == otherKey ? (values[xk] ?? {}).entries.where((e) => !kept.contains(e.key)).fold<double>(0, (s, e) => s + e.value) : (values[xk]?[c] ?? 0);
    PdfColor colorOf(int i, String c) => c == otherKey ? pdf(palette.other) : series(i);
    final stacks = [for (final xk in xKeys) cats.fold<double>(0, (s, c) => s + valueOf(xk, c))];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      plot(
        height: chartHeight,
        range: YRange.of(stacks, zero: true),
        xLabels: [for (final k in xKeys) ChartLabel.of(xs[k], x)],
        centered: true,
        paint: (g, w, y) {
          final slot = w / math.max(1, xKeys.length);
          final bw = math.max(0.6, slot * 0.7);
          for (var i = 0; i < xKeys.length; i++) {
            var base = 0.0;
            for (var c = 0; c < cats.length; c++) {
              final v = valueOf(xKeys[i], cats[c]);
              if (v <= 0) continue;
              g
                ..setFillColor(colorOf(c, cats[c]))
                ..drawRect(i * slot + (slot - bw) / 2, y(base), bw, y(base + v) - y(base))
                ..fillPath();
              base += v;
            }
          }
        },
      ),
      legend([for (var c = 0; c < cats.length; c++) (cats[c] == otherKey ? t('other') : names[cats[c]] ?? cats[c], colorOf(c, cats[c]))]),
    ]);
  }

  /// Flows between category stages: the same layout as the dashboard. First-stage nodes
  /// take series colors and the links carry them; later nodes are neutral gray.
  pw.Widget sankey(DatasetPage page, List<FieldInfo> stages, FieldInfo measure, List<String> notes) {
    final layout = SankeyLayout.build(page.rows, stages, measure);
    if (layout.isEmpty) return text(t('no_data'), size: 8.5, color: muted);
    final tallest = layout.columns.fold<int>(0, (m, c) => math.max(m, c.length));
    final h = compact ? 110.0 : math.min(260.0, math.max(140.0, tallest * 22.0)), w = inner;
    const labelW = 120.0;
    layout.place(w, h, left: labelW, right: labelW, nodeWidth: 8, gap: 6);
    PdfColor colorOf(SankeyNode n) => n.stage > 0 ? muted : (n.isOther ? pdf(palette.other) : series(layout.columns[0].indexOf(n)));
    String name(SankeyNode n) => n.isOther ? t('other') : cell(valueText(n.raw, stages[n.stage]), notes);
    final last = layout.columns.length - 1;
    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.Stack(overflow: pw.Overflow.visible, children: [
        pw.CustomPaint(
          size: PdfPoint(w, h),
          painter: (g, size) {
            // PDF y grows upward: flip the layout coordinates.
            double y(double v) => h - v;
            for (final l in layout.links) {
              final x0 = l.source.x + l.source.width, x1 = l.target.x, xm = (x0 + x1) / 2;
              final th = math.max(0.6, l.thickness);
              g
                ..saveContext()
                ..setGraphicState(const PdfGraphicState(fillOpacity: 0.4))
                ..setFillColor(colorOf(l.source))
                ..moveTo(x0, y(l.sourceY))
                ..curveTo(xm, y(l.sourceY), xm, y(l.targetY), x1, y(l.targetY))
                ..lineTo(x1, y(l.targetY + th))
                ..curveTo(xm, y(l.targetY + th), xm, y(l.sourceY + th), x0, y(l.sourceY + th))
                ..closePath()
                ..fillPath()
                ..restoreContext();
            }
            for (final col in layout.columns) {
              for (final n in col) {
                g
                  ..setFillColor(colorOf(n))
                  ..drawRect(n.x, y(n.y + math.max(0.6, n.height)), n.width, math.max(0.6, n.height))
                  ..fillPath();
              }
            }
          },
        ),
        for (final col in layout.columns)
          for (final n in col)
            pw.Positioned(
              left: n.stage == 0 ? 0 : n.x + n.width + 4,
              top: (n.y + n.height / 2 - 4.5).clamp(0.0, h - 9),
              child: pw.SizedBox(
                width: n.stage == 0 || n.stage == last ? labelW - 6 : labelW,
                child: text('${name(n)}  ${compactNumber(n.value)}',
                    size: 7, maxWidth: labelW - 6, align: n.stage == 0 ? pw.TextAlign.right : pw.TextAlign.left),
              ),
            ),
      ]),
    );
  }

  /// Points on their position, sized by value; the top 10 in the project color.
  pw.Widget map(DatasetPage page, FieldInfo value) {
    FieldInfo? ofType(String type) => page.descriptor.fields.where((f) => f.type == type).firstOrNull;
    final lat = ofType('latitude'), lon = ofType('longitude');
    if (lat == null || lon == null) return pw.SizedBox();
    final pts = [
      for (final r in page.rows)
        if (asDouble(r[lat.name]) != null && asDouble(r[lon.name]) != null) (asDouble(r[lon.name])!, asDouble(r[lat.name])!, asDouble(r[value.name]) ?? 0)
    ];
    if (pts.isEmpty) return pw.SizedBox();
    final h = compact ? 120.0 : 200.0, w = inner;
    var minX = pts.map((p) => p.$1).reduce(math.min), maxX = pts.map((p) => p.$1).reduce(math.max);
    var minY = pts.map((p) => p.$2).reduce(math.min), maxY = pts.map((p) => p.$2).reduce(math.max);
    final padX = (maxX - minX) * 0.08 + 1e-4, padY = (maxY - minY) * 0.08 + 1e-4;
    minX -= padX;
    maxX += padX;
    minY -= padY;
    maxY += padY;
    final kx = math.cos((minY + maxY) / 2 * math.pi / 180);
    final scale = math.min(w / ((maxX - minX) * kx), h / (maxY - minY));
    final offX = (w - (maxX - minX) * kx * scale) / 2, offY = (h - (maxY - minY) * scale) / 2;
    final maxV = pts.map((p) => p.$3).reduce(math.max);
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: grid, width: 0.5)),
      child: pw.CustomPaint(
        size: PdfPoint(w, h),
        painter: (g, size) {
          for (var i = pts.length - 1; i >= 0; i--) {
            final p = pts[i];
            final cx = offX + (p.$1 - minX) * kx * scale, cy = offY + (p.$2 - minY) * scale;
            final r = 2 + 9 * math.sqrt(maxV <= 0 ? 0 : (p.$3 / maxV).clamp(0.0, 1.0));
            final color = i < 10 ? accent : series(0);
            g
              ..saveContext()
              ..setGraphicState(const PdfGraphicState(fillOpacity: 0.35))
              ..setFillColor(color)
              ..drawEllipse(cx, cy, r, r)
              ..fillPath()
              ..restoreContext()
              ..setStrokeColor(i < 10 ? ink : color)
              ..setLineWidth(0.6)
              ..drawEllipse(cx, cy, r, r)
              ..strokePath();
          }
        },
      ),
    );
  }
}

/// Short x label of a value (dates as month-day), as on the dashboard.
class ChartLabel {
  static String of(dynamic v, FieldInfo f) {
    if (f.type == 'date' && v is String && v.length >= 10) return v.substring(5, 10);
    return valueText(v, f);
  }
}
