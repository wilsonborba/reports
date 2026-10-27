import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../layouts/board_layout.dart';
import '../../layouts/report_layout.dart';
import '../../themes/report_palette.dart';

/// Smallest card for a visual (columns, rows).
(int, int) minSpan(Slot s) => switch (s.visual) {
  Visual.kpi => (1, 1),
  Visual.map => (2, 2),
  Visual.table => s.wide ? (2, 2) : (1, 2),
  _ => (1, 2),
};

enum _Grip { move, left, right, bottom, corner }

/// Edit mode of a section board: the cells of the board plus one free column and one
/// free row (up to 4 x 4), simple cards with a drag area and edge handles. Every change
/// snaps to the cells; a change that leaves the board or overlaps shows red and does nothing.
class BoardEditor extends StatefulWidget {
  final BoardLayout layout;
  final Map<String, Slot> slots;
  final Map<String, String> titles;
  final double rowHeight;
  final double gap;
  final ValueChanged<BoardLayout> onChanged;

  const BoardEditor({
    super.key,
    required this.layout,
    required this.slots,
    required this.titles,
    required this.onChanged,
    this.rowHeight = 180,
    this.gap = 16,
  });

  @override
  State<BoardEditor> createState() => _BoardEditorState();
}

class _BoardEditorState extends State<BoardEditor> {
  String? _key;
  _Grip? _grip;
  Offset _delta = Offset.zero;

  BoardItem? _candidate(BoardItem a, double colStep, double rowStep) {
    final dc = (_delta.dx / colStep).round();
    final dr = (_delta.dy / rowStep).round();
    final (minC, minR) = minSpan(widget.slots[a.key] ?? Slot(a.key));
    switch (_grip!) {
      case _Grip.move:
        return a.copyWith(col: a.col + dc, row: a.row + dr);
      case _Grip.left:
        final c = (a.col + dc).clamp(0, a.colEnd - minC);
        return a.copyWith(col: c, colSpan: a.colEnd - c);
      case _Grip.right:
        return a.copyWith(
          colSpan: (a.colSpan + dc).clamp(minC, BoardLayout.maxCols - a.col),
        );
      case _Grip.bottom:
        return a.copyWith(
          rowSpan: (a.rowSpan + dr).clamp(minR, BoardLayout.maxRows - a.row),
        );
      case _Grip.corner:
        return a.copyWith(
          colSpan: (a.colSpan + dc).clamp(minC, BoardLayout.maxCols - a.col),
          rowSpan: (a.rowSpan + dr).clamp(minR, BoardLayout.maxRows - a.row),
        );
    }
  }

  /// Result of applying [next]: a move can swap with one card; a resize must not overlap.
  BoardLayout? _apply(BoardItem next, _Grip grip) => grip == _Grip.move
      ? widget.layout.move(next.key, next.col, next.row)
      : widget.layout.withItem(next);

  void _start(String key, _Grip grip) => setState(() {
    _key = key;
    _grip = grip;
    _delta = Offset.zero;
  });

  void _end(double colStep, double rowStep) {
    final a = _key == null ? null : widget.layout.item(_key!);
    if (a != null && _grip != null) {
      final next = _candidate(a, colStep, rowStep);
      final out = next == null ? null : _apply(next, _grip!);
      if (out != null) widget.onChanged(out);
    }
    setState(() {
      _key = null;
      _grip = null;
      _delta = Offset.zero;
    });
  }

  KeyEventResult _onKey(String key, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final a = widget.layout.item(key);
    if (a == null) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final (minC, minR) = minSpan(widget.slots[key] ?? Slot(key));
    BoardLayout? out;
    final k = e.logicalKey;
    if (shift) {
      if (k == LogicalKeyboardKey.arrowRight) {
        out = widget.layout.withItem(a.copyWith(colSpan: a.colSpan + 1));
      }
      if (k == LogicalKeyboardKey.arrowLeft && a.colSpan > minC) {
        out = widget.layout.withItem(a.copyWith(colSpan: a.colSpan - 1));
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        out = widget.layout.withItem(a.copyWith(rowSpan: a.rowSpan + 1));
      }
      if (k == LogicalKeyboardKey.arrowUp && a.rowSpan > minR) {
        out = widget.layout.withItem(a.copyWith(rowSpan: a.rowSpan - 1));
      }
    } else {
      if (k == LogicalKeyboardKey.arrowRight) {
        out = widget.layout.move(key, a.col + 1, a.row);
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        out = widget.layout.move(key, a.col - 1, a.row);
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        out = widget.layout.move(key, a.col, a.row + 1);
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        out = widget.layout.move(key, a.col, a.row - 1);
      }
    }
    const arrows = [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ];
    if (!arrows.contains(k)) return KeyEventResult.ignored;
    if (out != null) widget.onChanged(out);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = widget.layout;
    final cols = (l.usedCols + 1).clamp(1, BoardLayout.maxCols);
    final rows = (l.usedRows + 1).clamp(1, BoardLayout.maxRows);
    return LayoutBuilder(
      builder: (context, c) {
        // In edit mode the cells always fit the width, so dragging never fights a scroll.
        final colW = (c.maxWidth - widget.gap * (cols - 1)) / cols;
        final colStep = colW + widget.gap,
            rowStep = widget.rowHeight + widget.gap;
        Rect rect(BoardItem i) => Rect.fromLTWH(
          i.col * colStep,
          i.row * rowStep,
          i.colSpan * colW + (i.colSpan - 1) * widget.gap,
          i.rowSpan * widget.rowHeight + (i.rowSpan - 1) * widget.gap,
        );
        final active = _key == null ? null : l.item(_key!);
        final candidate = active == null
            ? null
            : _candidate(active, colStep, rowStep);
        final valid = candidate != null && _apply(candidate, _grip!) != null;

        Widget handle(
          String key,
          _Grip grip, {
          required Alignment at,
          required double w,
          required double h,
          required MouseCursor cursor,
          required String tip,
        }) {
          return Align(
            alignment: at,
            child: MouseRegion(
              cursor: cursor,
              child: Tooltip(
                message: tip,
                waitDuration: const Duration(milliseconds: 600),
                child: track(
                  'report.layout.drag',
                  GestureDetector(
                    key: Key('grip_${grip.name}_$key'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => _start(key, grip),
                    onPanUpdate: (d) => setState(() => _delta += d.delta),
                    onPanEnd: (_) => _end(colStep, rowStep),
                    onPanCancel: () => _end(colStep, rowStep),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Center(
                        child: Container(
                          width: grip == _Grip.bottom
                              ? 34
                              : (grip == _Grip.corner ? 12 : 5),
                          height: grip == _Grip.bottom
                              ? 5
                              : (grip == _Grip.corner ? 12 : 34),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          key: const Key('board_editor'),
          width: c.maxWidth,
          height: rows * rowStep - widget.gap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var col = 0; col < cols; col++)
                for (var row = 0; row < rows; row++)
                  Positioned.fromRect(
                    key: ValueKey('cellpos_${col}_$row'),
                    rect: rect(BoardItem('', col, row, 1, 1)),
                    child: Container(
                      key: Key('cell_${col}_$row'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: col >= l.usedCols || row >= l.usedRows
                            ? p.accent.withValues(alpha: 0.06)
                            : p.surfaceAlt.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(
                          ReportPalette.surfaceRadius,
                        ),
                        border: Border.all(
                          color:
                              (col >= l.usedCols || row >= l.usedRows
                                      ? p.accent
                                      : p.border)
                                  .withValues(alpha: 0.35),
                        ),
                      ),
                      child: col >= l.usedCols || row >= l.usedRows
                          ? Text(
                              context.tr('drop_here'),
                              style: TextStyle(
                                fontSize: 11,
                                color: p.accent.withValues(alpha: 0.8),
                              ),
                            )
                          : null,
                    ),
                  ),
              for (final item in l.items)
                Positioned.fromRect(
                  key: ValueKey('cardpos_${item.key}'),
                  rect: rect(item),
                  child: Opacity(
                    opacity: item.key == _key ? 0.45 : 1,
                    child: Focus(
                      key: Key('edit_focus_${item.key}'),
                      onKeyEvent: (_, e) => _onKey(item.key, e),
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return track(
                            'report.layout.resize',
                            GestureDetector(
                              key: Key('edit_card_${item.key}'),
                              onTap: () => Focus.of(context).requestFocus(),
                              onPanStart: (_) => _start(item.key, _Grip.move),
                              onPanUpdate: (d) =>
                                  setState(() => _delta += d.delta),
                              onPanEnd: (_) => _end(colStep, rowStep),
                              onPanCancel: () => _end(colStep, rowStep),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.surface,
                                    borderRadius: BorderRadius.circular(
                                      ReportPalette.surfaceRadius,
                                    ),
                                    border: Border.all(
                                      color: focused ? p.accent : p.border,
                                      width: focused ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  widget.titles[item.key] ??
                                                      item.key,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                    color: p.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.drag_indicator_rounded,
                                                size: 18,
                                                color: p.textMuted,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Positioned(
                                        left: 0,
                                        bottom: 0,
                                        child: Container(
                                          key: Key('size_${item.key}'),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: p.accent,
                                            borderRadius: BorderRadius.circular(
                                              ReportPalette.controlRadius,
                                            ),
                                          ),
                                          child: Text(
                                            '${item.colSpan} × ${item.rowSpan}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: p.onAccent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              for (final item in l.items) ...[
                Positioned.fromRect(
                  key: ValueKey('leftpos_${item.key}'),
                  rect: rect(item),
                  child: handle(
                    item.key,
                    _Grip.left,
                    at: Alignment.centerLeft,
                    w: 14,
                    h: 60,
                    cursor: SystemMouseCursors.resizeLeftRight,
                    tip: context.tr('resize_width'),
                  ),
                ),
                Positioned.fromRect(
                  key: ValueKey('rightpos_${item.key}'),
                  rect: rect(item),
                  child: handle(
                    item.key,
                    _Grip.right,
                    at: Alignment.centerRight,
                    w: 14,
                    h: 60,
                    cursor: SystemMouseCursors.resizeLeftRight,
                    tip: context.tr('resize_width'),
                  ),
                ),
                Positioned.fromRect(
                  key: ValueKey('bottompos_${item.key}'),
                  rect: rect(item),
                  child: handle(
                    item.key,
                    _Grip.bottom,
                    at: Alignment.bottomCenter,
                    w: 60,
                    h: 14,
                    cursor: SystemMouseCursors.resizeUpDown,
                    tip: context.tr('resize_height'),
                  ),
                ),
                Positioned.fromRect(
                  key: ValueKey('cornerpos_${item.key}'),
                  rect: rect(item),
                  child: handle(
                    item.key,
                    _Grip.corner,
                    at: Alignment.bottomRight,
                    w: 22,
                    h: 22,
                    cursor: SystemMouseCursors.resizeDownRight,
                    tip: context.tr('resize_corner'),
                  ),
                ),
              ],
              if (candidate != null)
                Positioned.fromRect(
                  key: const ValueKey('ghostpos'),
                  rect: rect(candidate),
                  child: IgnorePointer(
                    child: Container(
                      key: Key(valid ? 'ghost_ok' : 'ghost_blocked'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (valid ? p.accent : p.negative).withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(
                          ReportPalette.surfaceRadius,
                        ),
                        border: Border.all(
                          color: valid ? p.accent : p.negative,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '${candidate.colSpan} × ${candidate.rowSpan}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: valid ? p.accent : p.negative,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
