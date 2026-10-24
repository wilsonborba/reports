import 'report_layout.dart';

/// Place of one card on a section board (cells start at 0).
class BoardItem {
  final String key;
  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;

  const BoardItem(this.key, this.col, this.row, this.colSpan, this.rowSpan);

  int get colEnd => col + colSpan;
  int get rowEnd => row + rowSpan;

  bool overlaps(BoardItem o) => col < o.colEnd && o.col < colEnd && row < o.rowEnd && o.row < rowEnd;

  BoardItem copyWith({int? col, int? row, int? colSpan, int? rowSpan}) =>
      BoardItem(key, col ?? this.col, row ?? this.row, colSpan ?? this.colSpan, rowSpan ?? this.rowSpan);

  Map<String, dynamic> toJson() => {'key': key, 'col': col, 'row': row, 'colSpan': colSpan, 'rowSpan': rowSpan};

  static BoardItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    int? n(String k) => (j[k] as num?)?.toInt();
    final key = j['key'];
    final col = n('col'), row = n('row'), cs = n('colSpan'), rs = n('rowSpan');
    if (key is! String || col == null || row == null || cs == null || rs == null) return null;
    return BoardItem(key, col, row, cs, rs);
  }

  @override
  bool operator ==(Object other) =>
      other is BoardItem && other.key == key && other.col == col && other.row == row && other.colSpan == colSpan && other.rowSpan == rowSpan;

  @override
  int get hashCode => Object.hash(key, col, row, colSpan, rowSpan);

  @override
  String toString() => '$key@$col,$row ${colSpan}x$rowSpan';
}

/// Card positions of one section: at most [maxCols] columns and [maxRows] rows.
class BoardLayout {
  static const int maxCols = 4;
  static const int maxRows = 4;

  final List<BoardItem> items;

  /// Cards that show only their header.
  final Set<String> minimized;

  const BoardLayout(this.items, {this.minimized = const {}});

  BoardItem? item(String key) {
    for (final i in items) {
      if (i.key == key) return i;
    }
    return null;
  }

  /// Columns and rows in use (the bounding box of the cards).
  int get usedCols => items.fold(0, (m, i) => i.colEnd > m ? i.colEnd : m);
  int get usedRows => items.fold(0, (m, i) => i.rowEnd > m ? i.rowEnd : m);

  /// Cards in reading order (row by row, then column), for phones and exports.
  List<BoardItem> get readingOrder => [...items]..sort((a, b) => a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));

  /// True when every card is inside the board and no two cards overlap.
  bool get isValid {
    for (var i = 0; i < items.length; i++) {
      final a = items[i];
      if (a.col < 0 || a.row < 0 || a.colSpan < 1 || a.rowSpan < 1 || a.colEnd > maxCols || a.rowEnd > maxRows) return false;
      for (var j = i + 1; j < items.length; j++) {
        if (a.overlaps(items[j]) || a.key == items[j].key) return false;
      }
    }
    return true;
  }

  BoardLayout copyWith({List<BoardItem>? items, Set<String>? minimized}) =>
      BoardLayout(items ?? this.items, minimized: minimized ?? this.minimized);

  /// Replaces one card. Returns null when the result leaves the board or overlaps.
  BoardLayout? withItem(BoardItem next) {
    final out = BoardLayout([for (final i in items) i.key == next.key ? next : i], minimized: minimized);
    return out.isValid ? out : null;
  }

  /// Moves a card to [col], [row]. On another card of a place that fits, the two swap.
  BoardLayout? move(String key, int col, int row) {
    final a = item(key);
    if (a == null) return null;
    final moved = a.copyWith(col: col, row: row);
    final direct = withItem(moved);
    if (direct != null) return direct;
    // Swap: exactly one other card under the new place, and it fits at the old place.
    final hit = items.where((o) => o.key != key && o.overlaps(moved)).toList();
    if (hit.length != 1) return null;
    final b = hit.first;
    final out = BoardLayout(
      [for (final i in items) i.key == key ? moved : (i.key == b.key ? b.copyWith(col: a.col, row: a.row) : i)],
      minimized: minimized,
    );
    return out.isValid ? out : null;
  }

  Map<String, dynamic> toJson() => {'items': [for (final i in items) i.toJson()], 'minimized': minimized.toList()};

  static BoardLayout? fromJson(dynamic j) {
    if (j is! Map || j['items'] is! List) return null;
    final items = <BoardItem>[];
    for (final e in j['items'] as List) {
      final i = BoardItem.fromJson(e);
      if (i == null) return null;
      items.add(i);
    }
    final minimized = ((j['minimized'] as List?) ?? const []).map((e) => '$e').toSet();
    return BoardLayout(items, minimized: minimized);
  }

  /// Default placement: cards in layout order, 2 x 2 blocks, wide cards over the full
  /// width when they fit, maps 2 x 4. When the cards do not fit in 4 x 4, wide cards use
  /// half the width.
  static BoardLayout fallback(List<Slot> slots) {
    for (final allowWide in [true, false]) {
      final placed = <BoardItem>[];
      var ok = true;
      for (final s in slots) {
        // Maps need height: half the width over all four rows.
        final tall = s.visual == Visual.map;
        final cs = tall ? 2 : (s.wide && allowWide ? maxCols : 2);
        final rs = tall ? maxRows : 2;
        final spot = _firstFree(placed, cs, rs);
        if (spot == null) {
          ok = false;
          break;
        }
        placed.add(BoardItem(s.key, spot.$1, spot.$2, cs, rs));
      }
      if (ok) return BoardLayout(placed);
    }
    // More than 4 cards: one column of blocks (the board then has more rows).
    return BoardLayout([for (var i = 0; i < slots.length; i++) BoardItem(slots[i].key, 0, i * 2, 2, 2)]);
  }

  static (int, int)? _firstFree(List<BoardItem> placed, int cs, int rs) {
    for (var row = 0; row + rs <= maxRows; row++) {
      for (var col = 0; col + cs <= maxCols; col++) {
        final c = BoardItem('', col, row, cs, rs);
        if (placed.every((p) => !p.overlaps(c))) return (col, row);
      }
    }
    return null;
  }

  /// A saved layout when it still matches the cards of the section, else the default.
  static BoardLayout resolve(BoardLayout? saved, List<Slot> slots) {
    final keys = slots.map((s) => s.key).toSet();
    if (saved != null && saved.isValid && saved.items.length == keys.length && saved.items.every((i) => keys.contains(i.key))) {
      return saved.copyWith(minimized: saved.minimized.where(keys.contains).toSet());
    }
    return fallback(slots);
  }
}
