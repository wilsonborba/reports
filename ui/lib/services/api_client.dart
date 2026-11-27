import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../utils/browser.dart';
import 'client_telemetry_service.dart';
import 'http_client.dart';

class OwnerDeleteOutcome {
  final bool deleted;
  final bool requiresConfirmation;
  final int referenceCount;
  final String message;

  const OwnerDeleteOutcome({
    required this.deleted,
    required this.requiresConfirmation,
    required this.referenceCount,
    required this.message,
  });

  factory OwnerDeleteOutcome.fromJson(Map<String, dynamic> j) =>
      OwnerDeleteOutcome(
        deleted: j['deleted'] as bool? ?? false,
        requiresConfirmation: j['requires_confirmation'] as bool? ?? false,
        referenceCount: (j['reference_count'] as num?)?.toInt() ?? 0,
        message: (j['message'] ?? '') as String,
      );
}

class ApiException implements Exception {
  /// HTTP status; 0 when the service did not answer.
  final int status;
  final String message;
  const ApiException(this.status, this.message);

  /// Machine code of the engine error (for example `session_required`), or null.
  String? get code {
    try {
      final j = jsonDecode(message);
      return j is Map<String, dynamic> ? j['code'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// No valid session: a 401 of the engine, or a 403 of the gateway. The gateway answers
  /// 403 without an engine `code` when the `sid` cookie is missing or expired
  /// (`{"message": "Missing Authentications Parameters...", "data": null}`).
  bool get needsLogin => status == 401 || (status == 403 && code == null);

  /// A valid session without access: a 403 of the engine (it always sends a `code`).
  bool get accessLimited => status == 403 && code != null;

  @override
  String toString() => 'HTTP $status: $message';
}

/// JSON client of the Reports engine through the gateway. Calls carry the browser
/// cookies (the gateway session). Every failure except 401 and 403 (expected access
/// states) is reported to the shared error telemetry.
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  /// Name of the service in telemetry reports.
  final String service;
  final String? Function(String) _cookieReader;

  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.service = 'reports',
    String? Function(String) cookieReader = readCookie,
  }) : baseUrl = baseUrl ?? ReportsConfig.apiBaseUrl,
       _client = client ?? createCredentialsClient(),
       _cookieReader = cookieReader;

  Map<String, String> _csrfHeaders() {
    final csrf = _cookieReader('csrf');
    if (csrf == null || csrf.isEmpty) return const {};
    return {'X-CSRF-Token': csrf, 'X-CSRFToken': csrf};
  }

  Uri uri(String path, [Map<String, String> query = const {}]) => Uri.parse(
    '$baseUrl$path',
  ).replace(queryParameters: query.isEmpty ? null : query);

  Future<Map<String, dynamic>> getJson(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final value = await getAny(path, query);
    if (value is Map<String, dynamic>) return value;
    throw ApiException(500, 'unexpected answer of $path');
  }

  Future<dynamic> getAny(String path, [Map<String, String> query = const {}]) =>
      _send('GET', path, () => _client.get(uri(path, query)));

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final value = await _send(
      'PATCH',
      path,
      () => _client.patch(
        uri(path),
        headers: {'Content-Type': 'application/json', ..._csrfHeaders()},
        body: jsonEncode(body),
      ),
    );
    if (value is Map<String, dynamic>) return value;
    throw ApiException(500, 'unexpected answer of $path');
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final value = await _send(
      'DELETE',
      path,
      () => _client.delete(uri(path, query), headers: _csrfHeaders()),
    );
    if (value is Map<String, dynamic>) return value;
    throw ApiException(500, 'unexpected answer of $path');
  }

  Future<Map<String, dynamic>> getOwnerItem(
    String itemOrDatasetId, {
    String? project,
    String? report,
  }) {
    final query = <String, String>{};
    if (project != null && project.isNotEmpty) query['project'] = project;
    if (report != null && report.isNotEmpty) query['report'] = report;
    final uri = Uri(
      path: '/me/items/${Uri.encodeComponent(itemOrDatasetId)}',
      queryParameters: query.isEmpty ? null : query,
    );
    return getJson(uri.toString());
  }

  Future<Map<String, dynamic>> patchOwnerItemVisibility(
    String itemId,
    String visibility,
  ) => patchJson('/me/items/${Uri.encodeComponent(itemId)}', {
    'visibility': visibility,
  });

  Future<OwnerDeleteOutcome> deleteOwnerItem(
    String itemId, {
    bool confirm = false,
  }) async {
    final encoded = Uri.encodeComponent(itemId);
    try {
      final data = await deleteJson('/me/items/$encoded', {
        'confirm': confirm ? 'true' : 'false',
      });
      return OwnerDeleteOutcome.fromJson(data);
    } on ApiException catch (e) {
      if (e.status == 409) {
        try {
          final parsed = jsonDecode(e.message);
          if (parsed is Map<String, dynamic>) {
            return OwnerDeleteOutcome.fromJson(parsed);
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<dynamic> _send(
    String method,
    String path,
    Future<http.Response> Function() request,
  ) async {
    http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 30));
    } catch (e) {
      ClientTelemetryService.instance.reportServiceFailure(
        service: service,
        method: method,
        path: path,
        status: 0,
        message: '$e',
      );
      throw ApiException(0, '$e');
    }
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final error = ApiException(res.statusCode, body);
      if (res.statusCode != 401 && res.statusCode != 403) {
        ClientTelemetryService.instance.reportServiceFailure(
          service: service,
          method: method,
          path: path,
          status: res.statusCode,
          code: error.code,
        );
      }
      throw error;
    }
    return body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
  }
}
