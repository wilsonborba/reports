import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/layouts/board_layout.dart';
import 'package:reports_ui/layouts/report_layout.dart';

void main() {
  test('default: 2 x 2 blocks in reading order, wide cards over the full width', () {
    final b = BoardLayout.fallback(const [Slot('a', wide: true), Slot('b'), Slot('c')]);
    expect(b.items, const [BoardItem('a', 0, 0, 4, 2), BoardItem('b', 0, 2, 2, 2), BoardItem('c', 2, 2, 2, 2)]);
    expect((b.usedCols, b.usedRows), (4, 4));
    expect(b.isValid, isTrue);
  });

  test('wide cards use half the width when four cards need the space', () {
    final b = BoardLayout.fallback(const [Slot('a', wide: true), Slot('b', wide: true), Slot('c'), Slot('d')]);
    expect(b.items.every((i) => i.colSpan == 2 && i.rowSpan == 2), isTrue);
    expect(b.isValid, isTrue);
  });

  test('the board grows with the cards: two cards use two rows only', () {
    final b = BoardLayout.fallback(const [Slot('a'), Slot('b')]);
    expect((b.usedCols, b.usedRows), (4, 2));
    final one = BoardLayout(const [BoardItem('a', 0, 0, 1, 1)]);
    expect((one.usedCols, one.usedRows), (1, 1));
  });

  test('move to a free place, swap with one card, refuse overlaps and the edge', () {
    final b = BoardLayout(const [BoardItem('a', 0, 0, 1, 4), BoardItem('b', 1, 0, 1, 2), BoardItem('c', 1, 2, 1, 2)]);
    expect(b.move('b', 3, 0)!.item('b'), const BoardItem('b', 3, 0, 1, 2));
    final swapped = b.move('b', 1, 2)!;
    expect(swapped.item('b'), const BoardItem('b', 1, 2, 1, 2));
    expect(swapped.item('c'), const BoardItem('c', 1, 0, 1, 2));
    expect(b.move('a', 1, 0), isNull, reason: 'a 1 x 4 card on two cards cannot swap');
    expect(b.move('b', 3, 3), isNull, reason: 'past the last row');
  });

  test('a saved layout is used only when it matches the cards of the section', () {
    const slots = [Slot('a'), Slot('b')];
    final saved = BoardLayout(const [BoardItem('a', 2, 0, 2, 2), BoardItem('b', 0, 0, 2, 2)], minimized: {'b', 'gone'});
    final r = BoardLayout.resolve(saved, slots);
    expect(r.item('a')!.col, 2);
    expect(r.minimized, {'b'});
    expect(BoardLayout.resolve(BoardLayout(const [BoardItem('a', 0, 0, 2, 2)]), slots).items.length, 2, reason: 'missing card: default');
    expect(BoardLayout.resolve(BoardLayout.fromJson({'items': 'x'}), slots).isValid, isTrue);
  });

  test('reading order and JSON round trip', () {
    final b = BoardLayout(const [BoardItem('c', 1, 2, 1, 2), BoardItem('a', 0, 0, 1, 4), BoardItem('b', 1, 0, 1, 2)], minimized: {'a'});
    expect(b.readingOrder.map((i) => i.key), ['a', 'b', 'c']);
    final again = BoardLayout.fromJson(b.toJson())!;
    expect(again.items, b.items);
    expect(again.minimized, {'a'});
  });
}
