import '../models/report.dart';
import 'api_client.dart';
import 'session_store.dart';

/// Report and dataset data with the access rules of the engine.
///
/// A guest reads the showcase (`/projects/{p}/showcase/{r}`): it already holds the first
/// rows of every public card, so those cards need no second call. A signed-in user reads
/// the session routes. If the session expired (401), the store becomes a guest and the
/// guest view loads; nothing redirects. A 403 stays an error: access is limited.
class ReportService {
  static ReportService instance = ReportService(ApiClient());

  final ApiClient api;
  final Duration ttl;
  final Map<String, (DateTime, ReportView)> _reports = {};
  final Map<String, DatasetPage> _datasets = {};

  /// Rows of a public card that the showcase sends inline.
  static const int showcaseRows = 500;

  ReportService(this.api, {this.ttl = const Duration(minutes: 5)});

  String get _mode => SessionStore.instance.hasSession ? 'u:${SessionStore.instance.user?.userId}' : 'guest';

  /// [tier] keeps only the cards of that tier (engine filter); null shows every card.
  Future<ReportView> report(String project, String report, {required String lang, String? tier}) async {
    final key = '$_mode/$project/$report/$lang/${tier ?? ''}';
    final q = {'lang': lang, 'tier': ?tier};
    final hit = _reports[key];
    if (hit != null && DateTime.now().difference(hit.$1) < ttl) return hit.$2;
    final session = SessionStore.instance;
    if (session.hasSession) {
      try {
        final view = ReportView.fromJson(await api.getJson('/projects/$project/reports/$report', q));
        _reports[key] = (DateTime.now(), view);
        return view;
      } on ApiException catch (e) {
        if (!e.needsLogin) rethrow;
        session.markExpired();
      }
    }
    final showcase = Showcase.fromJson(await api.getJson('/projects/$project/showcase/$report', q));
    final guestKey = 'guest/$project/$report/$lang/${tier ?? ''}';
    _reports[guestKey] = (DateTime.now(), showcase.view);
    showcase.pages.forEach((id, page) => _datasets[_datasetKey('guest', project, report, id, lang, showcaseRows, 0, const {})] = page);
    return showcase.view;
  }

  static String _datasetKey(String mode, String project, String report, String id, String lang, int limit, int offset, Map<String, String> filters) {
    final sorted = filters.keys.toList()..sort();
    return '$mode/$project/$report/$id/$lang/$limit/$offset/${sorted.map((k) => '$k=${filters[k]}').join('&')}';
  }

  /// [filters] holds query parameters such as `f.provider` or `f.day.from`.
  Future<DatasetPage> dataset(String project, String report, String datasetId,
      {required String lang, Map<String, String> filters = const {}, int limit = 500, int offset = 0}) async {
    final mode = _mode;
    final key = _datasetKey(mode, project, report, datasetId, lang, limit, offset, filters);
    final hit = _datasets[key];
    if (hit != null) return hit;
    // A guest first page that the showcase already sent.
    if (mode == 'guest' && offset == 0 && filters.isEmpty && limit <= showcaseRows) {
      final inline = _datasets[_datasetKey('guest', project, report, datasetId, lang, showcaseRows, 0, const {})];
      if (inline != null && (inline.rows.length < showcaseRows || limit == showcaseRows)) {
        final page = DatasetPage(descriptor: inline.descriptor, rows: inline.rows.take(limit).toList(), offset: 0, limit: limit, totalRows: inline.totalRows, lineage: inline.lineage);
        _datasets[key] = page;
        return page;
      }
    }
    final query = {'lang': lang, 'limit': '$limit', 'offset': '$offset', ...filters};
    final session = SessionStore.instance;
    if (session.hasSession) {
      try {
        final page = DatasetPage.fromJson(await api.getJson('/projects/$project/reports/$report/datasets/$datasetId', query));
        _datasets[key] = page;
        return page;
      } on ApiException catch (e) {
        if (!e.needsLogin) rethrow;
        session.markExpired();
      }
    }
    final page = DatasetPage.fromJson(await api.getJson('/projects/$project/showcase/$report/cards/$datasetId', query));
    _datasets[_datasetKey('guest', project, report, datasetId, lang, limit, offset, filters)] = page;
    return page;
  }

  /// All rows of a dataset (up to [maxRows]) through `limit` and `offset` pages.
  Future<DatasetPage> allRows(String project, String report, String datasetId,
      {required String lang, Map<String, String> filters = const {}, int pageSize = 1000, int maxRows = 5000}) async {
    final first = await dataset(project, report, datasetId, lang: lang, filters: filters, limit: pageSize);
    final rows = [...first.rows];
    final target = first.totalRows < maxRows ? first.totalRows : maxRows;
    var offset = first.rows.length;
    while (rows.length < target && offset < target) {
      final next = await dataset(project, report, datasetId, lang: lang, filters: filters, limit: pageSize, offset: offset);
      if (next.rows.isEmpty) break;
      rows.addAll(next.rows);
      offset += next.rows.length;
    }
    return DatasetPage(descriptor: first.descriptor, rows: rows.take(target).toList(), offset: 0, limit: target, totalRows: first.totalRows, lineage: first.lineage);
  }

  int get cachedDatasets => _datasets.length;

  void clear() {
    _reports.clear();
    _datasets.clear();
  }
}
