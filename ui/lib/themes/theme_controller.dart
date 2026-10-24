import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level light or dark mode. One controller for every screen; the choice
/// persists in the browser.
class ThemeController extends ChangeNotifier {
  static const _key = 'app_theme_mode';
  Brightness _brightness;

  ThemeController({Brightness initial = Brightness.dark}) : _brightness = initial;

  Brightness get brightness => _brightness;
  bool get isDark => _brightness == Brightness.dark;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'light' || saved == 'dark') {
        _brightness = saved == 'light' ? Brightness.light : Brightness.dark;
        notifyListeners();
      }
    } catch (_) {
      // Browser storage can be blocked; the default mode stays.
    }
  }

  Future<void> toggle() async {
    _brightness = isDark ? Brightness.light : Brightness.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, isDark ? 'dark' : 'light');
    } catch (_) {}
  }
}

/// Gives the theme controller to the widget tree.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
