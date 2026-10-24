import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Maximum length of a section name.
const int sectionNameMax = 32;

/// Checks a new section name. Returns the text key of the error, or null when valid.
/// [others] are the names that the other sections show now (custom or default).
/// Names cannot repeat in one report, ignoring upper and lower case.
String? sectionNameError(String name, List<String> others) {
  final n = name.trim();
  if (n.length > sectionNameMax) return 'section_name_too_long';
  if (n.isEmpty) return null;
  final lower = n.toLowerCase();
  if (others.any((o) => o.trim().toLowerCase() == lower)) return 'section_name_taken';
  return null;
}

/// Custom section names of one report in the browser (index to name).
class SectionNameStore {
  static String key(String project, String report) => 'section_names/$project/$report';

  static Future<Map<int, String>> load(String project, String report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key(project, report));
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) if (int.tryParse(e.key) != null && e.value is String) int.parse(e.key): e.value as String};
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String project, String report, Map<int, String> names) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key(project, report), jsonEncode({for (final e in names.entries) '${e.key}': e.value}));
    } catch (_) {}
  }
}
