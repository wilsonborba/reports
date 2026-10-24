import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/catalog.dart';
import '../../services/catalog_service.dart';
import '../../themes/report_palette.dart';
import '../../widgets/charts/format.dart';
import '../../widgets/public/code_panel.dart';
import '../../widgets/public/flow_diagram.dart';
import '../../widgets/public/public_blocks.dart';
import '../../widgets/public/public_layout.dart';
import '../../widgets/public/public_motion.dart';
import '../../widgets/public/public_page.dart';
import 'api_examples.dart';
import 'overview_view.dart';

/// Schema draft of the storage slide: part of the real Cortex `telemetry_event` schema.
const String schemaDraftJson = '''{
  "schema_name": "telemetry_event",
  "version": 1,
  "description": "cortex_api TelemetryEvent: one LLM execution",
  "fields": [
    { "path": "provider", "type": "string", "required": true },
    { "path": "model", "type": "string", "required": true },
    { "path": "total_tokens", "type": "integer", "required": true },
    { "path": "latency_ms", "type": "integer", "required": true },
    { "path": "success", "type": "boolean", "required": true },
    { "path": "error_type", "type": "string", "required": false }
  ]
}''';

/// Architecture page (/v1/home/architecture). It follows the slide layout of the
/// Reports presentation: a numbered kicker, a title, a subtitle on a rule, then the
/// text on the left and one visual on the right (diagram, table, tiles or list).
class ArchitectureView extends StatelessWidget {
  const ArchitectureView({super.key});

  @override
  Widget build(BuildContext context) {
    return PublicPage(sections: (context, data) {
      final p = context.palette;
      String t(String key) => context.tr(key);
      return [
        _TitleSlide(projects: data.projects),
        _Slide(
          number: 2,
          kicker: t('arch_k_de'),
          title: t('arch_s2_t'),
          subtitle: t('arch_s2_s'),
          paragraphs: [t('arch_s2_p1'), t('arch_s2_p2'), t('arch_s2_p3')],
          visual: FlowDiagram(steps: [
            FlowStep(t('arch_f1_t'), t('arch_f1_d'), Icons.upload_rounded),
            FlowStep(t('arch_f2_t'), t('arch_f2_d'), Icons.rule_rounded),
            FlowStep('CouchDB', t('arch_f3_d'), Icons.inventory_2_outlined),
            FlowStep(t('arch_f4_t'), t('arch_f4_d'), Icons.functions_rounded),
            FlowStep('Redis', t('arch_f5_d'), Icons.bolt_rounded),
            FlowStep(t('arch_f6_t'), t('arch_f6_d'), Icons.insert_chart_outlined_rounded),
          ]),
        ),
        _Slide(
          number: 3,
          kicker: t('arch_k_de'),
          title: t('arch_s3_t'),
          subtitle: t('arch_s3_s'),
          paragraphs: [t('arch_s3_p1'), t('arch_s3_p2'), t('arch_s3_p3')],
          background: p.surface,
          visual: const CodePanel(title: 'schema_draft.json', code: schemaDraftJson, language: CodeLanguage.json),
        ),
        _Slide(
          number: 4,
          kicker: t('arch_k_backend'),
          title: t('arch_s4_t'),
          subtitle: t('arch_s4_s'),
          paragraphs: [t('arch_s4_p1'), t('arch_s4_p2'), t('arch_s4_p3')],
          visual: _Tiles(key: const Key('arch_stores'), columns: 3, tiles: [
            ('PostgreSQL', 'asodya_reports', t('arch_tile_pg'), Icons.table_chart_outlined),
            ('CouchDB', 'reports_documents', t('arch_tile_couch'), Icons.inventory_2_outlined),
            ('Redis', 'reports:*', t('arch_tile_redis'), Icons.bolt_rounded),
          ]),
        ),
        _Slide(
          number: 5,
          kicker: t('arch_k_backend'),
          title: t('arch_s5_t'),
          subtitle: t('arch_s5_s'),
          paragraphs: [t('arch_s5_p1'), t('arch_s5_p2'), t('arch_s5_p3')],
          background: p.surface,
          visual: _TagList(key: const Key('arch_cache'), items: [
            (Icons.flash_on_rounded, t('arch_c1'), 'hit', false),
            (Icons.lock_clock_outlined, t('arch_c2'), 'miss', false),
            (Icons.playlist_remove_rounded, t('arch_c3'), 'ingest', true),
            (Icons.cloud_off_rounded, t('arch_c4'), 'fallback', false),
          ]),
        ),
        _Slide(
          number: 6,
          kicker: t('arch_k_security'),
          title: t('arch_s6_t'),
          subtitle: t('arch_s6_s'),
          paragraphs: [t('arch_s6_p1'), t('arch_s6_p2'), t('arch_s6_p3')],
          visual: FlowDiagram(steps: [
            FlowStep('Reports', t('arch_l1_d'), Icons.login_rounded),
            FlowStep('auth_apps', t('arch_l2_d'), Icons.verified_user_outlined),
            FlowStep('/sync', t('arch_l3_d'), Icons.key_rounded),
            FlowStep(t('arch_gateway'), t('arch_l4_d'), Icons.cookie_outlined),
            FlowStep('/me', t('arch_l5_d'), Icons.badge_outlined),
          ]),
        ),
        _Slide(
          number: 7,
          kicker: t('arch_k_security'),
          title: t('arch_s7_t'),
          subtitle: t('arch_s7_s'),
          paragraphs: [t('arch_s7_p1'), t('arch_s7_p2'), t('arch_s7_p3')],
          background: p.surface,
          visual: _Table(key: const Key('arch_access'), header: (t('arch_th_state'), t('arch_th_result')), rows: [
            (t('arch_a_readable'), t('arch_a_readable_d')),
            (t('arch_a_disc'), t('arch_a_disc_d')),
            (t('arch_a_hidden'), t('arch_a_hidden_d')),
          ]),
        ),
        _Slide(
          number: 8,
          kicker: t('arch_k_frontend'),
          title: t('arch_s8_t'),
          subtitle: t('arch_s8_s'),
          paragraphs: [t('arch_s8_p1'), t('arch_s8_p2'), t('arch_s8_p3')],
          visual: _Tiles(key: const Key('arch_charts'), columns: 4, tiles: [
            for (final (name, icon) in [
              ('KPI', Icons.looks_one_outlined),
              (t('arch_v_line'), Icons.show_chart_rounded),
              (t('arch_v_bar'), Icons.bar_chart_rounded),
              (t('arch_v_rank'), Icons.align_horizontal_left_rounded),
              (t('arch_v_donut'), Icons.donut_large_rounded),
              (t('arch_v_map'), Icons.map_outlined),
              (t('arch_v_table'), Icons.table_rows_outlined),
              ('Sankey', Icons.account_tree_outlined),
            ])
              (name, null, null, icon),
          ]),
        ),
        _Slide(
          number: 9,
          kicker: t('arch_k_platform'),
          title: t('arch_s9_t'),
          subtitle: t('arch_s9_s'),
          paragraphs: [t('arch_s9_p1'), t('arch_s9_p2'), t('arch_s9_p3')],
          background: p.surface,
          extra: Wrap(spacing: 24, runSpacing: 8, children: [
            ArrowLink(key: const Key('arch_api_docs'), label: t('pub_api_docs'), icon: Icons.open_in_new_rounded, onTap: () => openPublicLink(engineUrl(apiDocsPath))),
            ArrowLink(label: t('pub_api_openapi'), icon: Icons.open_in_new_rounded, onTap: () => openPublicLink(engineUrl(openApiPath))),
          ]),
          visual: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Table(key: const Key('arch_routes'), mono: true, header: (t('arch_th_route'), t('arch_th_access')), rows: [
              ('GET /catalog', t('arch_r_public')),
              ('GET /projects/{project}/showcase/{report}', t('arch_r_public')),
              ('GET /me', t('arch_r_session')),
              ('GET /projects/{project}/reports/{report}', t('arch_r_session')),
              ('POST /projects/{project}/admin/ingest/{schema}', t('arch_r_admin')),
            ]),
            const SizedBox(height: 24),
            const CodePanel(title: 'read_card.sh', code: datasetRequestShell, language: CodeLanguage.shell),
          ]),
        ),
        ...nextStepBand(context),
      ];
    });
  }
}

/// `NN / SECTION` above a slide title.
String _kicker(int number, String section) => '${number.toString().padLeft(2, '0')} / ${section.toUpperCase()}';

/// The first slide on a dark band, with live numbers from `GET /stats`.
class _TitleSlide extends StatefulWidget {
  final List<ProjectSummary> projects;

  const _TitleSlide({required this.projects});

  @override
  State<_TitleSlide> createState() => _TitleSlideState();
}

class _TitleSlideState extends State<_TitleSlide> {
  Future<GlobalStats>? _stats;
  String? _lang;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = context.langCode;
    if (_lang != lang) {
      _lang = lang;
      // The catalog service keeps the answer for five minutes; nothing loads twice.
      _stats = CatalogService.instance.stats(lang: lang);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = PublicLayout.isPhone(context);
    final fg = p.canvas;
    final muted = p.canvas.withValues(alpha: 0.72);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_kicker(1, context.tr('arch_k_overview')), style: TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 14, color: muted, letterSpacing: 0.6)),
      const SizedBox(height: 12),
      Text(context.tr('arch_title'),
          key: const Key('arch_title'), style: TextStyle(fontSize: phone ? 40 : 64, fontWeight: FontWeight.w300, color: fg, height: 1.1)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: fg))),
        child: Text(context.tr('arch_subtitle'), style: TextStyle(fontSize: phone ? 19 : 24, color: muted, height: 1.3)),
      ),
      const SizedBox(height: 28),
      for (final key in ['arch_s1_p1', 'arch_s1_p2', 'arch_s1_p3'])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(context.tr(key), style: TextStyle(fontSize: phone ? 17 : 20, color: fg, height: 1.45)),
        ),
    ]);
    final visual = FutureBuilder<GlobalStats>(
      future: _stats,
      builder: (context, snap) {
        final s = snap.data;
        String n(int? v) => v == null ? '…' : numberText(v, 0);
        return _Tiles(key: const Key('arch_numbers'), columns: 2, dark: true, tiles: [
          (n(s?.projects ?? (widget.projects.isEmpty ? null : widget.projects.length)), null, context.tr('arch_t_projects'), null),
          (n(s?.reports), null, context.tr('arch_t_reports'), null),
          (n(s?.charts), null, context.tr('arch_t_charts'), null),
          (n(s?.rows), null, context.tr('arch_t_rows'), null),
        ]);
      },
    );
    return PublicSection(
      key: const Key('arch_slide_1'),
      background: p.textPrimary,
      child: SplitBlock(text: text, visual: Reveal(delay: const Duration(milliseconds: 120), child: visual)),
    );
  }
}

/// One slide: kicker, title, subtitle on a rule, text left and visual right.
class _Slide extends StatelessWidget {
  final int number;
  final String kicker;
  final String title;
  final String subtitle;
  final List<String> paragraphs;
  final Widget visual;
  final Widget? extra;
  final Color? background;

  const _Slide({
    required this.number,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.paragraphs,
    required this.visual,
    this.extra,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = PublicLayout.isPhone(context);
    final heading = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_kicker(number, kicker), style: TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 14, color: p.textMuted, letterSpacing: 0.6)),
      const SizedBox(height: 10),
      Text(title, style: TextStyle(fontSize: phone ? 30 : 44, fontWeight: FontWeight.w300, color: p.textPrimary, height: 1.15)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.textPrimary))),
        child: Text(subtitle, style: TextStyle(fontSize: phone ? 18 : 22, color: p.textMuted, height: 1.3)),
      ),
      const SizedBox(height: 32),
    ]);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final para in paragraphs)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(para, style: TextStyle(fontSize: phone ? 16 : 19, color: p.textPrimary, height: 1.5)),
        ),
      if (extra != null) ...[const SizedBox(height: 8), extra!],
    ]);
    return PublicSection(
      key: Key('arch_slide_$number'),
      background: background,
      topBorder: background == null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Reveal(child: heading),
        SplitBlock(text: text, visual: Reveal(delay: const Duration(milliseconds: 120), child: visual)),
      ]),
    );
  }
}

/// Grid of tiles with 1 px rules between them: (title, code, text, icon).
class _Tiles extends StatelessWidget {
  final List<(String, String?, String?, IconData?)> tiles;
  final int columns;
  final bool dark;

  const _Tiles({super.key, required this.tiles, this.columns = 3, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = dark ? p.canvas : p.textPrimary;
    final muted = dark ? p.canvas.withValues(alpha: 0.72) : p.textMuted;
    final rule = dark ? p.canvas.withValues(alpha: 0.3) : p.border;
    final cell = dark ? p.textPrimary : p.canvas;
    Widget tile((String, String?, String?, IconData?) t) {
      final (title, code, text, icon) = t;
      return Container(
        constraints: const BoxConstraints(minHeight: 120),
        color: cell,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 28, color: fg), const SizedBox(height: 12)],
          Text(title, style: TextStyle(fontSize: dark ? 34 : 18, fontWeight: dark ? FontWeight.w300 : FontWeight.w600, color: fg)),
          if (code != null) ...[
            const SizedBox(height: 4),
            Text(code, style: TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 12.5, color: muted)),
          ],
          if (text != null) ...[
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 14.5, color: muted, height: 1.4)),
          ],
        ]),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 420 ? (columns > 2 ? 2 : columns) : columns;
      // Rows of equal height; the last row is filled with empty cells, so the rule
      // color shows only as the 1 px lines between tiles.
      final rows = [for (var i = 0; i < tiles.length; i += cols) tiles.sublist(i, (i + cols).clamp(0, tiles.length))];
      return Container(
        color: rule,
        padding: const EdgeInsets.all(1),
        child: Column(children: [
          for (final (r, row) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : 1),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var k = 0; k < cols; k++) ...[
                    if (k > 0) const SizedBox(width: 1),
                    Expanded(child: k < row.length ? tile(row[k]) : Container(color: cell)),
                  ],
                ]),
              ),
            ),
        ]),
      );
    });
  }
}

/// Two-column table with a header on a dark rule.
class _Table extends StatelessWidget {
  final (String, String) header;
  final List<(String, String)> rows;

  /// The first column holds code (routes).
  final bool mono;

  const _Table({super.key, required this.header, required this.rows, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row((String, String) r, {bool head = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: head ? p.surfaceAlt : p.canvas,
            border: Border(bottom: BorderSide(color: head ? p.textPrimary : p.border)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 6,
              child: Text(r.$1,
                  style: TextStyle(
                    fontFamily: mono && !head ? ReportPalette.monoFont : null,
                    fontSize: mono && !head ? 13 : 15.5,
                    fontWeight: head ? FontWeight.w600 : FontWeight.w400,
                    color: p.textPrimary,
                  )),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: Text(r.$2, style: TextStyle(fontSize: 15.5, fontWeight: head ? FontWeight.w600 : FontWeight.w400, color: head ? p.textPrimary : p.textMuted)),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(header, head: true),
      for (final r in rows) row(r),
    ]);
  }
}

/// List with an icon, a text and a tag on the right: (icon, text, tag, filled tag).
class _TagList extends StatelessWidget {
  final List<(IconData, String, String, bool)> items;

  const _TagList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (icon, text, tag, filled) in items)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            Icon(icon, size: 24, color: p.textPrimary),
            const SizedBox(width: 16),
            Expanded(child: Text(text, style: TextStyle(fontSize: 16.5, color: p.textPrimary, height: 1.4))),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: filled ? p.textPrimary : null, border: Border.all(color: p.textPrimary)),
              child: Text(tag, style: TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 12.5, color: filled ? p.canvas : p.textPrimary)),
            ),
          ]),
        ),
    ]);
  }
}
