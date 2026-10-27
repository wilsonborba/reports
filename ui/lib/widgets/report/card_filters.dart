import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import '../charts/format.dart';

/// Filter values of one card as API query parameters: `f.<field>=a,b` for categories,
/// `f.<field>.from` and `f.<field>.to` for ranges.
class CardFilterQuery {
  static const int chipLimit = 6;

  static Set<String> selected(Map<String, String> q, String field) =>
      (q['f.$field'] ?? '').split(',').where((s) => s.isNotEmpty).toSet();

  static Map<String, String> withCategory(
    Map<String, String> q,
    String field,
    Set<String> values,
  ) {
    final out = {...q}..remove('f.$field');
    if (values.isNotEmpty) {
      out['f.$field'] = (values.toList()..sort()).join(',');
    }
    return out;
  }

  static Map<String, String> withRange(
    Map<String, String> q,
    String field,
    String? from,
    String? to,
  ) {
    final out = {...q}
      ..remove('f.$field.from')
      ..remove('f.$field.to');
    if (from != null) out['f.$field.from'] = from;
    if (to != null) out['f.$field.to'] = to;
    return out;
  }

  /// Number of filters with a value.
  static int active(Map<String, String> q) => q.keys
      .where((k) => k.startsWith('f.'))
      .map((k) => k.replaceAll(RegExp(r'\.(from|to)$'), ''))
      .toSet()
      .length;
}

/// Filter controls built from the `filters` list of a dataset.
class CardFilterBar extends StatelessWidget {
  final List<FilterInfo> filters;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  const CardFilterBar({
    super.key,
    required this.filters,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('card_filter_bar'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surfaceAlt.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final f in filters) _control(context, f),
          if (CardFilterQuery.active(values) > 0)
            track(
              'dataset.filter.reset',
              TextButton.icon(
                key: const Key('card_filters_reset'),
                onPressed: () => onChanged(const {}),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(context.tr('reset_filters')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _control(BuildContext context, FilterInfo f) {
    switch (f.type) {
      case 'category':
        return f.options.length <= CardFilterQuery.chipLimit
            ? _CategoryChips(filter: f, values: values, onChanged: onChanged)
            : _CategoryPicker(filter: f, values: values, onChanged: onChanged);
      case 'date':
      case 'hour':
      case 'number':
        return _RangeControl(filter: f, values: values, onChanged: onChanged);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: context.palette.textMuted,
    ),
  );
}

class _CategoryChips extends StatelessWidget {
  final FilterInfo filter;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  const _CategoryChips({
    required this.filter,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = CardFilterQuery.selected(values, filter.field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Label(filter.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in filter.options)
              track(
                'dataset.filter.category.option',
                FilterChip(
                  key: Key('filter_${filter.field}_${o.value}'),
                  label: Text(o.label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: selected.contains('${o.value}'),
                  onSelected: (on) {
                    trackInput(
                      context,
                      'dataset.filter.category.option',
                      '${o.value}:$on',
                    );
                    final next = {...selected};
                    on ? next.add('${o.value}') : next.remove('${o.value}');
                    onChanged(
                      CardFilterQuery.withCategory(values, filter.field, next),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final FilterInfo filter;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  const _CategoryPicker({
    required this.filter,
    required this.values,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _CategoryDialog(
        filter: filter,
        initial: CardFilterQuery.selected(values, filter.field),
      ),
    );
    if (result != null) {
      onChanged(CardFilterQuery.withCategory(values, filter.field, result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = CardFilterQuery.selected(values, filter.field).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Label(filter.label),
        const SizedBox(height: 6),
        track(
          'dataset.filter.category.open',
          OutlinedButton.icon(
            key: Key('filter_${filter.field}_open'),
            onPressed: () => _open(context),
            icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
            label: Text(
              n == 0
                  ? context.tr('all')
                  : context.tr('selected_count', {'n': n}),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  final FilterInfo filter;
  final Set<String> initial;

  const _CategoryDialog({required this.filter, required this.initial});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late Set<String> _selected = {...widget.initial};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.filter.options
        .where((o) => o.label.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return AlertDialog(
      key: const Key('filter_dialog'),
      title: Text(widget.filter.label),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            track(
              'dataset.filter.category.search',
              TextField(
                key: const Key('filter_search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  hintText: context.tr('search'),
                  isDense: true,
                ),
                onChanged: (v) {
                  trackInput(context, 'dataset.filter.category.search', v);
                  setState(() => _search = v);
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final o in options)
                    track(
                      'dataset.filter.category.toggle',
                      CheckboxListTile(
                        key: Key('filter_option_${o.value}'),
                        dense: true,
                        value: _selected.contains('${o.value}'),
                        title: Text(
                          o.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onChanged: (on) => setState(
                          () => on == true
                              ? _selected.add('${o.value}')
                              : _selected.remove('${o.value}'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        track(
          'dataset.filter.category.all',
          TextButton(
            onPressed: () => setState(() => _selected = {}),
            child: Text(context.tr('all')),
          ),
        ),
        track(
          'dataset.filter.category.apply',
          FilledButton(
            key: const Key('filter_apply'),
            onPressed: () {
              trackSubmit(context, 'dataset.filter.category.apply');
              Navigator.of(context).pop(_selected);
            },
            child: Text(context.tr('apply')),
          ),
        ),
      ],
    );
  }
}

/// Range selector within the filter min and max: dates by day, hours, or numbers.
class _RangeControl extends StatefulWidget {
  final FilterInfo filter;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  const _RangeControl({
    required this.filter,
    required this.values,
    required this.onChanged,
  });

  @override
  State<_RangeControl> createState() => _RangeControlState();
}

class _RangeControlState extends State<_RangeControl> {
  RangeValues? _dragging;

  bool get _isDate => widget.filter.type == 'date';
  DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

  /// Slider bounds: days from the first date for dates, the values for hours and numbers.
  (double, double)? get _bounds {
    final f = widget.filter;
    if (_isDate) {
      final a = _date(f.min), b = _date(f.max);
      if (a == null || b == null) return null;
      return (0, b.difference(a).inDays.toDouble());
    }
    final a = asDouble(f.min), b = asDouble(f.max);
    if (a == null || b == null) return null;
    return (a, b);
  }

  double _toSlider(String? v, double fallback) {
    if (v == null) return fallback;
    if (_isDate) {
      final d = _date(v), a = _date(widget.filter.min);
      return (d == null || a == null)
          ? fallback
          : d.difference(a).inDays.toDouble();
    }
    return double.tryParse(v) ?? fallback;
  }

  String _toQuery(double v) {
    if (_isDate) {
      final d = _date(widget.filter.min)!.add(Duration(days: v.round()));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    if (widget.filter.type == 'hour') return '${v.round()}';
    return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
  }

  String _display(double v) {
    if (widget.filter.type == 'hour') {
      return '${v.round().toString().padLeft(2, '0')}:00';
    }
    if (_isDate) return _toQuery(v);
    return compactNumber(v);
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds;
    if (bounds == null || bounds.$2 <= bounds.$1) {
      return const SizedBox.shrink();
    }
    final f = widget.filter;
    final current =
        _dragging ??
        RangeValues(
          _toSlider(
            widget.values['f.${f.field}.from'],
            bounds.$1,
          ).clamp(bounds.$1, bounds.$2),
          _toSlider(
            widget.values['f.${f.field}.to'],
            bounds.$2,
          ).clamp(bounds.$1, bounds.$2),
        );
    final integer = _isDate || f.type == 'hour';
    final divisions = integer ? (bounds.$2 - bounds.$1).round() : 100;
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Label(
            '${f.label}: ${_display(current.start)} ${context.tr('to').toLowerCase()} ${_display(current.end)}',
          ),
          track(
            'dataset.filter.range.input',
            RangeSlider(
              key: Key('filter_${f.field}_range'),
              min: bounds.$1,
              max: bounds.$2,
              divisions: divisions > 0 ? divisions : null,
              values: current,
              onChanged: (v) {
                trackInput(
                  context,
                  'dataset.filter.range.input',
                  '${v.start}:${v.end}',
                );
                setState(() => _dragging = v);
              },
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                final full =
                    (v.start - bounds.$1).abs() < 1e-9 &&
                    (v.end - bounds.$2).abs() < 1e-9;
                widget.onChanged(
                  CardFilterQuery.withRange(
                    widget.values,
                    f.field,
                    full ? null : _toQuery(v.start),
                    full ? null : _toQuery(v.end),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
