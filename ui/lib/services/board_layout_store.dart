import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../layouts/board_layout.dart';

/// Board layout of one report section in the browser (per report and section).
class BoardLayoutStore {
  static String key(String project, String report, int section) => 'board_layout/$project/$report/$section';

  static Future<BoardLayout?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The list layout of the old arrange mode no longer applies.
      for (final old in prefs.getKeys().where((k) => k.startsWith('card_layout/')).toList()) {
        await prefs.remove(old);
      }
      final raw = prefs.getString(key);
      return raw == null ? null : BoardLayout.fromJson(jsonDecode(raw));
    } catch (_) {
      // Blocked or broken browser storage: the default layout stays.
      return null;
    }
  }

  static Future<void> save(String key, BoardLayout layout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(layout.toJson()));
    } catch (_) {}
  }

  static Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
