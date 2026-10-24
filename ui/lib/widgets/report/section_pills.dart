import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../services/section_name_store.dart';
import '../../themes/report_palette.dart';

/// Section switch: one pill per section. A pill shows the custom name of the user, or
/// the default name (Section One, Section Two). Double-click a pill, or press the pencil
/// of the active pill, to rename it: Enter saves, Esc cancels, an empty name returns to
/// the default.
class SectionPills extends StatefulWidget {
  final int count;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Custom names by section index.
  final Map<int, String> names;

  /// New name of a section; null returns to the default name.
  final void Function(int index, String? name)? onRename;

  const SectionPills({super.key, required this.count, required this.selected, required this.onSelect, this.names = const {}, this.onRename});

  /// Default name of a section (in the UI language).
  static String label(BuildContext context, int index) => labelWith(context.tr, index);

  /// Default name of a section with a given translation (exports use their own language).
  static String labelWith(String Function(String key, [Map<String, Object> args]) tr, int index) {
    if (index < Strings.sectionNumbers.length) return tr('section_${Strings.sectionNumbers[index]}');
    return tr('section', {'n': index + 1});
  }

  /// Name that the user sees for a section.
  static String nameOf(BuildContext context, Map<int, String> names, int index) => names[index] ?? label(context, index);

  @override
  State<SectionPills> createState() => _SectionPillsState();
}

class _SectionPillsState extends State<SectionPills> {
  int? _editing;
  String? _error;

  // A second tap on the same pill within this time is a double-click (the first tap
  // selects at once, so switching sections never waits for a double-tap timeout).
  static const _doubleClick = Duration(milliseconds: 350);
  int? _lastTap;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _tap(int i) {
    final now = DateTime.now();
    if (_lastTap == i && now.difference(_lastTapAt) < _doubleClick) {
      _lastTap = null;
      _start(i);
      return;
    }
    _lastTap = i;
    _lastTapAt = now;
    widget.onSelect(i);
  }
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(int i) {
    if (widget.onRename == null) return;
    widget.onSelect(i);
    setState(() {
      _editing = i;
      _error = null;
      _controller.text = SectionPills.nameOf(context, widget.names, i);
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _cancel() => setState(() {
        _editing = null;
        _error = null;
      });

  void _save() {
    final i = _editing;
    if (i == null) return;
    final others = [for (var j = 0; j < widget.count; j++) if (j != i) SectionPills.nameOf(context, widget.names, j)];
    final error = sectionNameError(_controller.text, others);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = _controller.text.trim();
    widget.onRename!(i, name.isEmpty || name == SectionPills.label(context, i) ? null : name);
    _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(
        spacing: 0,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < widget.count; i++)
            if (i == _editing) _editor(context, p) else _pill(context, p, i),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr(_error!), key: const Key('section_name_error'), style: TextStyle(fontSize: 12, color: p.negative)),
        ),
    ]);
  }

  Widget _pill(BuildContext context, ReportPalette p, int i) {
    final active = i == widget.selected;
    // A flat tab: the line under the row, a thick project-color line under the selected tab.
    return InkWell(
        key: Key('section_pill_$i'),
        onTap: () => _tap(i),
        child: AnimatedContainer(
          key: Key('section_tab_$i'),
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.fromLTRB(16, 10, active && widget.onRename != null ? 8 : 16, active ? 8 : 10),
          decoration: BoxDecoration(
            color: active ? p.surface : Colors.transparent,
            border: Border(bottom: BorderSide(color: active ? p.accent : p.border, width: active ? 3 : 1)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              SectionPills.nameOf(context, widget.names, i),
              style: TextStyle(fontSize: 13.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? p.textPrimary : p.textMuted),
            ),
            if (active && widget.onRename != null) ...[
              const SizedBox(width: 4),
              InkWell(
                key: Key('section_rename_$i'),
                borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
                onTap: () => _start(i),
                child: Tooltip(
                  message: context.tr('rename_section'),
                  child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.edit_outlined, size: 14, color: p.textMuted)),
                ),
              ),
            ],
          ]),
        ),
    );
  }

  Widget _editor(BuildContext context, ReportPalette p) {
    return Container(
      key: const Key('section_name_editor'),
      width: 260,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
        border: Border.all(color: _error == null ? p.accent : p.negative, width: 1.8),
      ),
      child: Row(children: [
        Expanded(
          child: Focus(
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
                _cancel();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              key: const Key('section_name_field'),
              controller: _controller,
              autofocus: true,
              maxLength: sectionNameMax,
              style: TextStyle(fontSize: 13, color: p.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                hintText: context.tr('section_name_hint'),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              // Keep the focus after Enter, so a refused name can be fixed or cancelled with Esc.
              onEditingComplete: () {},
              onSubmitted: (_) => _save(),
            ),
          ),
        ),
        IconButton(key: const Key('section_name_save'), visualDensity: VisualDensity.compact, tooltip: context.tr('save'), onPressed: _save, icon: Icon(Icons.check_rounded, size: 18, color: p.accent)),
        IconButton(key: const Key('section_name_cancel'), visualDensity: VisualDensity.compact, tooltip: context.tr('cancel'), onPressed: _cancel, icon: Icon(Icons.close_rounded, size: 18, color: p.textMuted)),
      ]),
    );
  }
}
