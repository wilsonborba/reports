import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Forwards frontend errors to the shared Asodya client-error pipeline of api_for_apps
/// (`/apps/api/v1/client-error`: Redis rate limit, CouchDB store, admin-only query).
/// It covers uncaught Flutter and platform errors and every failed call to another
/// service (Reports engine, gateway exchange, logout, user info). It never sends rows,
/// chart payloads, cookies, tokens or exchange artifacts, and it never reports itself.
class ClientTelemetryService {
  static ClientTelemetryService instance = ClientTelemetryService();

  final http.Client _client;
  final String endpoint;
  final String appVersion;
  final String environment;

  final Map<String, DateTime> _recentErrors = {};
  static const Duration duplicateThrottleWindow = Duration(seconds: 15);

  ClientTelemetryService({
    http.Client? client,
    this.endpoint = ReportsConfig.telemetryUrl,
    this.appVersion = ReportsConfig.appVersion,
    this.environment = kReleaseMode ? 'production' : 'development',
  }) : _client = client ?? http.Client();

  /// Hooks into Flutter framework error handlers.
  void init() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      reportError(
        errorTitle: details.exceptionAsString(),
        errorMessage: details.summary.toString(),
        stackTrace: details.stack?.toString(),
        details: {'context': details.context?.toString() ?? 'Flutter framework'},
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      reportError(
        errorTitle: error.toString(),
        errorMessage: error.toString(),
        stackTrace: stack.toString(),
      );
      return false;
    };
  }

  /// Sends a bounded, throttled client error report asynchronously.
  Future<void> reportError({
    required String errorTitle,
    required String errorMessage,
    String? errorCode,
    String? stackTrace,
    String? route,
    String? requestId,
    Map<String, dynamic> details = const {},
  }) async {
    final now = DateTime.now();
    _cleanThrottles(now);

    final key = '$errorTitle:$errorMessage:$route';
    final lastSent = _recentErrors[key];
    if (lastSent != null && now.difference(lastSent) < duplicateThrottleWindow) {
      return;
    }
    _recentErrors[key] = now;

    final sanitizedTitle = errorTitle.length > 200 ? errorTitle.substring(0, 200) : errorTitle;
    final sanitizedMessage = errorMessage.length > 4000 ? errorMessage.substring(0, 4000) : errorMessage;
    final sanitizedStack = stackTrace != null && stackTrace.length > 8000
        ? stackTrace.substring(0, 8000)
        : stackTrace;

    final payload = {
      'app_name': 'reports',
      'app_version': appVersion,
      'environment': environment,
      'route': route,
      'error_title': sanitizedTitle,
      'error_message': sanitizedMessage,
      'error_code': errorCode,
      'stack_trace': sanitizedStack,
      'request_id': requestId,
      'client_timestamp': now.toIso8601String(),
      'details': details,
    };

    try {
      await _client
          .post(
            Uri.parse(endpoint),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Fire-and-forget: never crash or loop if telemetry fails
    }
  }

  /// A failed call to another service. [path] must not contain a query (tokens).
  Future<void> reportServiceFailure({
    required String service,
    required String method,
    required String path,
    required int status,
    String? code,
    String? message,
    String? route,
  }) {
    final cleanPath = path.split('?').first;
    return reportError(
      errorTitle: '$service $method $cleanPath failed',
      errorMessage: status == 0 ? 'network error: ${message ?? 'no answer'}' : 'HTTP $status${code == null ? '' : ' $code'}',
      errorCode: status == 0 ? '${service.toUpperCase()}_NETWORK' : '${service.toUpperCase()}_$status',
      route: route,
      details: {'service': service, 'method': method, 'path': cleanPath, 'status': status, 'code': ?code},
    );
  }

  void _cleanThrottles(DateTime now) {
    _recentErrors.removeWhere((_, time) => now.difference(time) > duplicateThrottleWindow);
  }
}
