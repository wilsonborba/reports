import 'package:flutter/foundation.dart';
import '../models/catalog.dart';

/// Projects that the app has loaded from the catalog API, with their texts, theme tokens
/// and logos. Screens listen to it, so a theme or logo appears as soon as it arrives.
class CatalogBrands extends ChangeNotifier {
  static final CatalogBrands instance = CatalogBrands();

  final Map<String, ProjectSummary> _projects = {};

  ProjectSummary? project(String? slug) => slug == null ? null : _projects[slug.toLowerCase()];

  /// Stores the projects; notifies only when something changed.
  void update(Iterable<ProjectSummary> projects) {
    var changed = false;
    for (final p in projects) {
      final key = p.slug.toLowerCase();
      final old = _projects[key];
      if (old == null || !mapEquals(old.toJson().map((k, v) => MapEntry(k, '$v')), p.toJson().map((k, v) => MapEntry(k, '$v')))) {
        _projects[key] = p;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  @visibleForTesting
  void clear() {
    _projects.clear();
    notifyListeners();
  }
}
