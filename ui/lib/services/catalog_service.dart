import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../themes/catalog_brands.dart';
import 'api_client.dart';
import 'session_store.dart';

/// Catalog data: projects (with their domain_api details), statistics and report lists.
/// Public answers stay in memory and browser storage for [ttl]; the engine caches them in
/// Redis too, so navigation never recalculates.
class CatalogService {
  static CatalogService instance = CatalogService(ApiClient());

  final ApiClient api;
  final Duration ttl;
  final Map<String, _Entry> _memory = {};

  CatalogService(this.api, {this.ttl = const Duration(minutes: 5)});

  Future<Paged<ProjectSummary>> projects({required String lang, int page = 1, int pageSize = 100}) async {
    final j = await _cached('projects:$lang:$page:$pageSize', () => api.getJson('/catalog', {'lang': lang, 'page': '$page', 'page_size': '$pageSize'}));
    final paged = Paged.fromJson(j, ProjectSummary.fromJson);
    CatalogBrands.instance.update(paged.items);
    return paged;
  }

  /// Totals of every project and the numbers of each project (guest view).
  Future<GlobalStats> stats({required String lang}) async =>
      GlobalStats.fromJson(await _cached('stats:$lang', () => api.getJson('/stats', {'lang': lang})));

  /// One project with its full Domain details (links, categories, statistics).
  Future<ProjectSummary?> project(String slug, {required String lang}) async {
    try {
      final project = ProjectSummary.fromJson(await _cached('project:$slug:$lang', () => api.getJson('/projects/$slug', {'lang': lang}), persist: false));
      CatalogBrands.instance.update([project]);
      return project;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Reports that this viewer can see: guests get the public list, a signed-in user gets
  /// the session list (granted and signed-in reports too).
  /// [tier] keeps only the reports of that tier (engine filter): sample, hybrid or real.
  Future<Paged<ReportSummary>> reports(String project,
      {required String lang, int page = 1, int pageSize = 12, String query = '', String? tier}) async {
    final q = {'lang': lang, 'page': '$page', 'page_size': '$pageSize', if (query.isNotEmpty) 'q': query, 'tier': ?tier};
    final session = SessionStore.instance;
    if (session.hasSession) {
      try {
        final key = 'me:${session.user?.userId}:reports:$project:$lang:$page:$pageSize:$query:${tier ?? ''}';
        return Paged.fromJson(await _cached(key, () => api.getJson('/me/projects/$project/reports', q), persist: false), ReportSummary.fromJson);
      } on ApiException catch (e) {
        if (!e.needsLogin && !e.accessLimited) rethrow;
        session.markExpired();
      }
    }
    final j = await _cached('reports:$project:$lang:$page:$pageSize:$query:${tier ?? ''}', () => api.getJson('/projects/$project/reports', q));
    return Paged.fromJson(j, ReportSummary.fromJson);
  }

  /// Absolute URL of an image path (Domain covers are absolute already).
  String assetUrl(String path) => path.startsWith('http') ? path : api.uri(path).toString();

  void clear() => _memory.clear();

  Future<Map<String, dynamic>> _cached(String key, Future<Map<String, dynamic>> Function() load, {bool persist = true}) async {
    final now = DateTime.now();
    final hit = _memory[key];
    if (hit != null && now.difference(hit.at) < ttl) return hit.data;
    SharedPreferences? prefs;
    if (persist) {
      try {
        prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString('catalog_cache:$key');
        if (stored != null) {
          final decoded = jsonDecode(stored) as Map<String, dynamic>;
          final at = DateTime.fromMillisecondsSinceEpoch(decoded['at'] as int);
          if (now.difference(at) < ttl) {
            final data = decoded['data'] as Map<String, dynamic>;
            _memory[key] = _Entry(at, data);
            return data;
          }
        }
      } catch (_) {
        // Browser storage can be blocked; the API answers instead.
      }
    }
    final data = await load();
    _memory[key] = _Entry(now, data);
    if (persist) {
      try {
        await prefs?.setString('catalog_cache:$key', jsonEncode({'at': now.millisecondsSinceEpoch, 'data': data}));
      } catch (_) {}
    }
    return data;
  }
}

class _Entry {
  final DateTime at;
  final Map<String, dynamic> data;
  _Entry(this.at, this.data);
}
