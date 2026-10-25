import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reports_ui/export/card_filter_state.dart';
import 'package:reports_ui/services/api_client.dart';
import 'package:reports_ui/services/auth_service.dart';
import 'package:reports_ui/services/client_telemetry_service.dart';
import 'package:reports_ui/services/session_store.dart';
import 'package:reports_ui/widgets/shell/guest_prompt.dart';
import 'package:reports_ui/services/catalog_service.dart';
import 'package:reports_ui/services/report_service.dart';

/// Fake Reports engine for widget tests, with the engine paths behind the gateway
/// prefix (`/apps/reports/v1`). It counts calls per engine path.
class FakeApi {
  static const String base = 'http://gateway.test/apps/reports/v1';
  static const String prefix = '/apps/reports/v1';

  final Map<String, int> calls = {};
  final Map<String, dynamic Function(Map<String, String> query)> routes = {};

  /// Cortex with light theme tokens and its Domain details, as `/catalog` sends them.
  static Map<String, dynamic> cortexProject({String lang = 'en'}) => {
        'slug': 'cortex',
        'name': 'Cortex',
        'tagline': 'LLM gateway',
        'description': 'One API for every model provider',
        'website_url': 'https://cortex.asodya.com',
        'repository_url': 'https://github.com/wilsonborba/cortex',
        'report_count': 6,
        'domain_status': 'fresh',
        'domain': {
          'id': 'd-cortex',
          'slug': 'cortex',
          'name': 'Cortex',
          'tagline': 'LLM gateway',
          'description': 'One API for every model provider',
          'status': 'active',
          'main_link': 'https://cortex.asodya.com',
          'repository_url': 'https://github.com/wilsonborba/cortex',
          'cover_url': 'https://asodya.com/covers/cortex.png',
          'fetched_at': '2026-10-22T00:00:00Z',
          'detail': {
            'links': [
              {'link_type': 'website', 'url': 'https://cortex.asodya.com'},
            ],
            'categories': [
              {'category': 'Stack', 'item': 'Python'},
            ],
            'statistics': [
              {'name': 'Providers', 'value': '6'},
            ],
            'collaborators': [
              {'name': 'Wilson Borba', 'github_username': 'wilsonborba', 'role': 'owner'},
            ],
          },
        },
        'theme': {
          'light': {
            'canvas': '#FFFFFF', 'surface': '#F6F6F5', 'surface_alt': '#E6E7E8', 'border': '#C7C9CB',
            'text_primary': '#2B2D2F', 'text_muted': '#636466', 'accent': '#F9DF4E', 'on_accent': '#111213',
            'positive': '#8C7600', 'warning': '#8C7600', 'negative': '#C62828', 'info': '#636466', 'caution': '#8C7600',
            'series': ['#C9A800', '#e87ba4', '#008300', '#2a78d6', '#eb6834', '#1baf7a', '#6250d6', '#e34948'],
            'other': '#A8A8A8',
          },
        },
      };

  /// The signed-in test user (engine `GET /me`). Tests change it before install().
  Map<String, dynamic> me = {
    'user_id': 'u-test',
    'role': 'viewer',
    'is_super_admin': false,
    'admin_projects': <String>[],
  };

  /// Gateway user info (`GET /user/info/v1/`).
  Map<String, dynamic> userInfo = {'full_name': 'Test Viewer', 'email': 'viewer@example.org'};

  FakeApi() {
    routes['/me'] = (q) => me;
    // Gateway routes of the login flow (outside the Reports prefix).
    routes['/user/info/v1/'] = (q) => {'data': userInfo};
    routes['/apps/api/v1/exchange'] = (q) => {'ok': true};
    routes['/user/sync/v1/log-out'] = (q) => {'ok': true};
    Map<String, dynamic> catalog(Map<String, String> q) => {
          'items': [
            cortexProject(lang: q['lang'] ?? 'en'),
            {'slug': 'certifications', 'name': 'Certifications', 'description': 'Certificates and courses', 'report_count': 2, 'domain_status': 'unlinked'},
            {'slug': 'fsm', 'name': 'FSM', 'description': 'Finite state machines', 'report_count': 0, 'domain_status': 'unlinked'},
          ],
          'page': 1,
          'page_size': 100,
          'total': 3,
          'language': q['lang'] ?? 'en',
        };
    routes['/catalog'] = catalog;
    routes['/projects'] = catalog;
    routes['/projects/cortex'] = (q) => cortexProject(lang: q['lang'] ?? 'en');
    Map<String, dynamic> stats(String project, int reports, int rows) => {
          'project': project, 'reports': reports, 'charts': reports * 12, 'collections': 2, 'rows': rows, 'fields': 9,
          'bytes': rows * 150, 'period_start': '2026-10-01', 'period_end': '2026-10-05',
          'rows_by_report': [for (var i = 0; i < reports; i++) {'report': 'report_${i + 1}', 'title': 'Report ${i + 1}', 'value': rows ~/ (i + 1)}],
          'charts_by_report': [for (var i = 0; i < reports; i++) {'report': 'report_${i + 1}', 'title': 'Report ${i + 1}', 'value': 12}],
          'rows_by_day': [for (var d = 1; d <= 5; d++) {'date': '2026-10-0$d', 'rows': 100 * d}],
        };
    routes['/stats'] = (q) => {
          'projects': 3, 'reports': 8, 'charts': 96, 'rows': 519209, 'bytes': 79367981,
          'items': [stats('cortex', 6, 356160), stats('certifications', 2, 1200), stats('fsm', 0, 0)],
        };
    Map<String, dynamic> reports(Map<String, String> q) {
      final size = int.parse(q['page_size'] ?? '12');
      final page = int.parse(q['page'] ?? '1');
      final all = List.generate(6, (i) => {
            'slug': 'report_${i + 1}',
            'project': 'cortex',
            'title': 'Report ${i + 1}',
            'description': 'Description ${i + 1}',
            'period': {'start': '2026-09-01', 'end': '2026-10-20'},
            'dataset_count': 12,
            'updated_at': '2026-10-21T10:00:00Z',
            'tags': ['tokens'],
          });
      final filtered = (q['q'] ?? '').isEmpty ? all : all.where((r) => '${r['title']}'.contains(q['q']!)).toList();
      return {
        'items': filtered.skip((page - 1) * size).take(size).toList(),
        'page': page,
        'page_size': size,
        'total': filtered.length,
        'language': q['lang'] ?? 'en',
      };
    }

    routes['/projects/cortex/reports'] = reports;
    routes['/me/projects/cortex/reports'] = reports;
  }

  /// Registers the list route of [project] for guests and for a session.
  void setReports(String project, dynamic Function(Map<String, String> query) handler) {
    routes['/projects/$project/reports'] = handler;
    routes['/me/projects/$project/reports'] = handler;
  }

  /// Registers a report with [count] datasets; each dataset returns [rowsPerDataset] rows.
  /// The session routes and the guest showcase both answer (the showcase without rows,
  /// so a guest card loads its page from the card route).
  FakeApi withReport(String project, String report, int count, {int rowsPerDataset = 3}) {
    final datasets = List.generate(count, (i) => {
          'dataset_id': 'd${i + 1}',
          'title': 'Dataset ${i + 1}',
          'description': 'Description ${i + 1}',
          'equation': i == 0 ? 'T_total = sum(tokens_i)' : null,
          'fields': [
            {'name': 'day', 'label': 'Day', 'type': 'date', 'role': 'dimension'},
            {'name': 'value', 'label': 'Value', 'type': 'integer', 'role': 'measure', 'unit': 'tokens'},
          ],
          'filters': [
            {'field': 'kind', 'label': 'Kind', 'type': 'category', 'options': [
              {'value': 'a', 'label': 'Kind A'}, {'value': 'b', 'label': 'Kind B'}]},
            {'field': 'day', 'label': 'Day', 'type': 'date', 'min': '2026-10-01', 'max': '2026-10-05'},
          ],
        });
    Map<String, dynamic> head(Map<String, String> q) => {
          'project': project,
          'report': report,
          'title': 'Test Report',
          'description': 'A report for tests',
          'tags': ['test'],
          'period': {'start': '2026-10-01', 'end': '2026-10-05'},
          'updated_at': '2026-10-21T10:00:00Z',
          'language': q['lang'] ?? 'en',
        };
    routes['/projects/$project/reports/$report'] = (q) => {...head(q), 'datasets': datasets};
    routes['/projects/$project/showcase/$report'] = (q) => {
          ...head(q),
          'cards': [
            for (final d in datasets) {'dataset_id': d['dataset_id'], 'title': d['title'], 'visibility': 'public', 'data_tier': 'sample', 'can_view': true, 'descriptor': d},
          ],
        };
    for (final d in datasets) {
      Map<String, dynamic> page(Map<String, String> q) {
        final kind = q['f.kind'];
        final limit = int.parse(q['limit'] ?? '500');
        final offset = int.parse(q['offset'] ?? '0');
        final all = List.generate(rowsPerDataset, (i) => {'day': '2026-10-0${(i % 5) + 1}', 'value': kind == 'b' ? 1000 + i : 10 + i});
        return {
          ...d,
          'language': q['lang'] ?? 'en',
          'rows': all.skip(offset).take(limit).toList(),
          'offset': offset,
          'limit': limit,
          'total_rows': all.length,
          'applied_filters': {},
        };
      }

      routes['/projects/$project/reports/$report/datasets/${d['dataset_id']}'] = page;
      routes['/projects/$project/showcase/$report/cards/${d['dataset_id']}'] = page;
    }
    return this;
  }

  /// Every request in order (method, headers and body for the gateway checks).
  final List<http.Request> requests = [];

  /// Raw answers per engine path; they win over [routes] (for example a 401).
  final Map<String, http.Response Function(http.Request req)> overrides = {};

  http.Client get client => MockClient((req) async {
        var path = req.url.path;
        if (path.startsWith(prefix)) path = path.substring(prefix.length);
        calls[path] = (calls[path] ?? 0) + 1;
        requests.add(req);
        final raw = overrides[path];
        if (raw != null) return raw(req);
        final handler = routes[path];
        if (handler == null) return http.Response('{"code":"not_found","message":"not found"}', 404);
        return http.Response.bytes(utf8.encode(jsonEncode(handler(req.url.queryParameters))), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

  ApiClient get apiClient => ApiClient(baseUrl: base, client: client);

  /// Installs this fake as the catalog, report and session API of the app, with the
  /// signed-in test user ([withSession] false: a guest). With [checkSession] the store
  /// starts unknown and checks the `csrf` cookie and `GET /me` like the real app.
  FakeApi install({bool withSession = true, bool checkSession = false}) {
    // Card filters and the closed guest prompt live in session memory; each test starts fresh.
    CardFilterState.instance.clear();
    GuestPrompt.dismissed = false;
    GuestPrompt.report.value = null;
    ClientTelemetryService.instance = ClientTelemetryService(
        client: MockClient((req) async {
          telemetry.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('{}', 202);
        }),
        environment: 'test');
    final api = apiClient;
    CatalogService.instance = CatalogService(api);
    ReportService.instance = ReportService(api);
    String? cookie(String name) => withSession && name == 'csrf' ? 'csrf-test' : null;
    AuthService.instance = AuthService(client: client, launcher: (uri) async => launched.add(uri), cookieReader: cookie);
    SessionStore.instance = SessionStore(api: api, cookieReader: cookie);
    if (!checkSession) SessionStore.instance.setForTest(withSession ? SessionUser.fromMe(me) : null);
    return this;
  }

  /// URLs that the app opened in this tab (the auth_apps login).
  final List<Uri> launched = [];

  /// Client-error reports that the app sent to the gateway telemetry.
  final List<Map<String, dynamic>> telemetry = [];
}
