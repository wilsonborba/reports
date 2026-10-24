import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../layouts/board_layout.dart';
import '../../layouts/report_layout.dart';
import '../../models/report.dart';
import '../../services/board_layout_store.dart';
import '../../themes/report_palette.dart';
import 'board_editor.dart';
import 'dataset_card.dart';
import 'dataset_slot.dart';

/// Cards of one report section on a board of at most 4 columns x 4 rows. The board uses
/// the columns and rows that the cards cover; columns share the width (at least
/// [minColWidth] each) and the board scrolls horizontally only when they do not fit.
/// Phones show one column in reading order.
class SectionBoard extends StatefulWidget {
  final String project;
  final String report;
  final ReportView view;
  final int section;
  final List<Slot> slots;

  const SectionBoard({super.key, required this.project, required this.report, required this.view, required this.section, required this.slots});

  static const double minColWidth = 220;
  static const double rowHeight = 180;
  static const double gap = 16;

  /// Below this width the board is one column of cards.
  static const double phoneWidth = 600;

  /// Edit mode needs at least this width (touch drag and scroll conflict on small screens).
  static const double editWidth = 768;

  @override
  State<SectionBoard> createState() => SectionBoardState();
}

class SectionBoardState extends State<SectionBoard> {
  late BoardLayout layout = BoardLayout.fallback(widget.slots);
  final _horizontal = ScrollController();

  /// Layout under edit; null outside the edit mode.
  BoardLayout? draft;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  String get storeKey => BoardLayoutStore.key(widget.project, widget.report, widget.section);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(SectionBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section || oldWidget.report != widget.report || oldWidget.project != widget.project) {
      layout = BoardLayout.fallback(widget.slots);
      draft = null;
      _restore();
    }
  }

  Future<void> _restore() async {
    final key = storeKey;
    final saved = await BoardLayoutStore.load(key);
    if (mounted && key == storeKey) setState(() => layout = BoardLayout.resolve(saved, widget.slots));
  }

  void save() => BoardLayoutStore.save(storeKey, layout);

  Map<String, Slot> get _byKey => {for (final s in widget.slots) s.key: s};

  void startEdit() => setState(() => draft = layout);

  void _done() {
    setState(() {
      layout = draft ?? layout;
      draft = null;
    });
    save();
  }

  void _cancel() => setState(() => draft = null);

  void _reset() {
    setState(() {
      layout = BoardLayout.fallback(widget.slots);
      draft = null;
    });
    BoardLayoutStore.clear(storeKey);
  }

  CardControls controlsFor(String key, {required bool canEdit}) => CardControls(
        minimized: layout.minimized.contains(key),
        onMove: canEdit ? startEdit : null,
        onToggleMinimize: () {
          final m = {...layout.minimized};
          m.contains(key) ? m.remove(key) : m.add(key);
          setState(() => layout = layout.copyWith(minimized: m));
          save();
        },
      );

  Widget _card(Slot slot, {required bool fill, bool canEdit = false}) => DatasetSlot(
        project: widget.project,
        report: widget.report,
        view: widget.view,
        slot: slot,
        controls: controlsFor(slot.key, canEdit: canEdit),
        fill: fill,
      );

  Widget _editBar(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('edit_bar'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
        border: Border.all(color: p.accent.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(context.tr('arrange_hint'), style: TextStyle(fontSize: 12.5, color: p.textPrimary)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(key: const Key('reset_layout'), onPressed: _reset, child: Text(context.tr('reset_layout'))),
            const SizedBox(width: 6),
            OutlinedButton(key: const Key('edit_cancel'), onPressed: _cancel, child: Text(context.tr('cancel'))),
            const SizedBox(width: 6),
            FilledButton(key: const Key('edit_done'), onPressed: _done, child: Text(context.tr('done'))),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byKey = _byKey;
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < SectionBoard.phoneWidth) {
        return Column(
          key: const Key('board_phone'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in layout.readingOrder)
              if (byKey[item.key] != null)
                Padding(
                  key: ValueKey('card_${item.key}'),
                  padding: const EdgeInsets.only(bottom: SectionBoard.gap),
                  child: _card(byKey[item.key]!, fill: false),
                ),
          ],
        );
      }
      final canEdit = c.maxWidth >= SectionBoard.editWidth;
      if (draft != null && canEdit) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          _editBar(context),
          BoardEditor(
            layout: draft!,
            slots: byKey,
            titles: {for (final s in widget.slots) s.key: widget.view.dataset(s.datasetId)?.title ?? s.key},
            rowHeight: SectionBoard.rowHeight,
            gap: SectionBoard.gap,
            onChanged: (next) => setState(() => draft = next),
          ),
        ]);
      }
      final cols = layout.usedCols.clamp(1, BoardLayout.maxCols);
      final rows = layout.usedRows.clamp(1, 64);
      final colWidth = ((c.maxWidth - SectionBoard.gap * (cols - 1)) / cols).clamp(SectionBoard.minColWidth, double.infinity);
      final width = colWidth * cols + SectionBoard.gap * (cols - 1);
      final height = SectionBoard.rowHeight * rows + SectionBoard.gap * (rows - 1);
      double x(int col) => col * (colWidth + SectionBoard.gap);
      double y(int row) => row * (SectionBoard.rowHeight + SectionBoard.gap);
      double w(int span) => span * colWidth + (span - 1) * SectionBoard.gap;
      double h(int span) => span * SectionBoard.rowHeight + (span - 1) * SectionBoard.gap;
      final board = SizedBox(
        key: const Key('board'),
        width: width,
        height: height,
        child: Stack(children: [
          for (final item in layout.items)
            if (byKey[item.key] != null)
              Positioned(
                key: ValueKey('card_${item.key}'),
                left: x(item.col),
                top: y(item.row),
                width: w(item.colSpan),
                height: h(item.rowSpan),
                child: layout.minimized.contains(item.key)
                    ? Align(alignment: Alignment.topCenter, child: _card(byKey[item.key]!, fill: false, canEdit: canEdit))
                    : _card(byKey[item.key]!, fill: true, canEdit: canEdit),
              ),
        ]),
      );
      final editButton = Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextButton.icon(
            key: const Key('edit_layout'),
            onPressed: startEdit,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
            label: Text(context.tr('edit_layout')),
          ),
        ),
      );
      Widget withButton(Widget b) =>
          canEdit ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [editButton, b]) : b;
      if (width <= c.maxWidth + 0.5) return withButton(board);
      return withButton(Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const Key('board_scroll'),
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: Padding(padding: const EdgeInsets.only(bottom: 12), child: board),
        ),
      ));
    });
  }
}
