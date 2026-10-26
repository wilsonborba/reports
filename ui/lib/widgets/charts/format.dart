import 'dart:async';

import '../../models/report.dart';

/// Language of the number separators on screen. The language controller sets it.
/// pt-BR writes 1.234,5; English and Thai write 1,234.5.
String numberLanguage = 'en';

/// Runs [body] with the number separators of [lang] (an export in its own language).
/// A zone value follows the awaits of an async export and never changes the screen.
T withNumberLanguage<T>(String lang, T Function() body) => runZoned(body, zoneValues: {#numberLanguage: lang});

String get _language => (Zone.current[#numberLanguage] as String?) ?? numberLanguage;

/// Thousands and decimal separators of the current number language.
(String, String) get _separators => _language == 'pt-BR' ? ('.', ',') : (',', '.');

/// Number with thousands separators and a fixed number of decimals.
String numberText(num value, int decimals) {
  final (group, point) = _separators;
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(group);
    buf.write(digits[i]);
  }
  final out = parts.length > 1 ? '$buf$point${parts[1]}' : buf.toString();
  return negative ? '-$out' : out;
}

/// Short number for chart axes: 950, 1.2k, 3.4M.
String compactNumber(num value) {
  final point = _separators.$2;
  String d(String text) => point == '.' ? text : text.replaceAll('.', point);
  final a = value.abs();
  if (a >= 1e9) return '${d((value / 1e9).toStringAsFixed(1))}B';
  if (a >= 1e6) return '${d((value / 1e6).toStringAsFixed(1))}M';
  if (a >= 1e3) return '${d((value / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1))}k';
  if (a == a.roundToDouble()) return value.toInt().toString();
  return d(value.toStringAsFixed(1));
}

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Date of the current language: pt-BR writes DD/MM/AAAA; English and Thai keep the
/// ISO date. Anything after the date (a time) stays as it is.
String dateText(String v) {
  final m = _isoDate.firstMatch(v);
  if (m == null || _language != 'pt-BR') return v;
  return '${m[3]}/${m[2]}/${m[1]}${v.substring(10)}';
}

/// Short axis label of a date: month-day (MM-DD), or day/month (DD/MM) in pt-BR.
String shortDateText(String v) {
  final m = _isoDate.firstMatch(v);
  if (m == null) return v;
  return _language == 'pt-BR' ? '${m[3]}/${m[2]}' : '${m[2]}-${m[3]}';
}

double? asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Display text of a value for its field (type, decimals). Without the unit.
String valueText(dynamic v, FieldInfo? f) {
  if (v == null) return '';
  if (v is num && f != null) {
    switch (f.type) {
      case 'hour':
        return '${v.toInt().toString().padLeft(2, '0')}:00';
      case 'integer':
        return numberText(v, 0);
      case 'percent':
        return '${numberText(v, f.decimals ?? 1)}%';
      case 'latitude':
      case 'longitude':
        return v.toStringAsFixed(f.decimals ?? 5);
      default:
        return numberText(v, f.decimals ?? (v == v.roundToDouble() ? 0 : 2));
    }
  }
  if (v is num) return numberText(v, v == v.roundToDouble() ? 0 : 2);
  if (v is String && f?.type == 'date') return dateText(v);
  return '$v';
}

/// Display text with the unit (the percent sign already comes from [valueText]).
String valueWithUnit(dynamic v, FieldInfo? f) {
  final text = valueText(v, f);
  final unit = f?.unit;
  if (text.isEmpty || unit == null || unit.isEmpty || unit == '%' || unit == 'x' && text.endsWith('x')) return text;
  if (unit == 'x') return '${text}x';
  return '$text $unit';
}

/// Field label with its unit in parentheses.
String labelWithUnit(FieldInfo f) => (f.unit == null || f.unit!.isEmpty) ? f.label : '${f.label} (${f.unit})';

/// Stored data size: 950 B, 12.3 KB, 45.6 MB, 1.2 GB (1 KB = 1024 B).
String bytesText(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return u == 0 ? '${v.toInt()} B' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[u]}';
}
