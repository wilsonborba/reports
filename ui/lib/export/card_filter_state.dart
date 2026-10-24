/// Active card filters of the open reports, in session memory. A card keeps its filters
/// when the user changes the section, and the exports use them (owner decision 4).
class CardFilterState {
  static CardFilterState instance = CardFilterState();

  final Map<String, Map<String, String>> _values = {};

  static String key(String project, String report, String slotKey) => '$project/$report/$slotKey';

  Map<String, String> get(String project, String report, String slotKey) => _values[key(project, report, slotKey)] ?? const {};

  void set(String project, String report, String slotKey, Map<String, String> filters) {
    final k = key(project, report, slotKey);
    if (filters.isEmpty) {
      _values.remove(k);
    } else {
      _values[k] = Map.unmodifiable(filters);
    }
  }

  void clear() => _values.clear();
}
