import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../core/tracking_manifest.dart';

/// Shared SQL-backed tracking, with the existing Reports error-call interface.
class ClientTelemetryService {
  static ClientTelemetryService instance = ClientTelemetryService();
  ClientTelemetryService({
    http.Client? client,
    this.endpoint = ReportsConfig.telemetryUrl,
    this.appVersion = ReportsConfig.appVersion,
    this.environment = kReleaseMode ? 'production' : 'development',
    String? Function()? currentRoute,
    bool? autoFlush,
  }) : _client = client,
       currentRoute = currentRoute ?? _browserRoute,
       _autoFlush = autoFlush ?? client == null;
  final http.Client? _client;
  final bool _autoFlush;
  final String endpoint, appVersion, environment;
  final String? Function() currentRoute;
  AsodyaTracker? _tracker;
  final Map<String, DateTime> _recentErrors = {};
  static const duplicateThrottleWindow = Duration(seconds: 15);
  static String? _browserRoute() => kIsWeb ? Uri.base.path : null;
  AsodyaTracker get tracker => _tracker ??= AsodyaTracker(
    appId: 'reports',
    baseUrl: Uri.parse(endpoint).origin,
    buildVersion: appVersion,
    screens: reportScreens,
    client: _client,
    autoFlush: _autoFlush,
  );
  void init() => tracker.installErrorCapture();
  void detach(AsodyaTracker current) {
    if (identical(_tracker, current)) {
      _tracker = null;
    }
    current.dispose();
  }

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
    _recentErrors.removeWhere(
      (_, at) => now.difference(at) > duplicateThrottleWindow,
    );
    final currentRoute = route ?? this.currentRoute();
    final key = '$errorTitle:$errorMessage:$currentRoute';
    if (_recentErrors.containsKey(key)) return;
    _recentErrors[key] = now;
    tracker.error(
      '$errorTitle: $errorMessage',
      stackTrace == null ? null : StackTrace.fromString(stackTrace),
      type: errorCode ?? 'ClientError',
      route: currentRoute,
    );
    await tracker.flush();
  }

  Future<void> reportServiceFailure({
    required String service,
    required String method,
    required String path,
    required int status,
    String? code,
    String? message,
    String? route,
  }) => reportError(
    errorTitle: '$service $method ${routePath(path)} failed',
    errorMessage: status == 0
        ? 'network error: ${message ?? 'no answer'}'
        : 'HTTP $status${code == null ? '' : ' $code'}',
    errorCode: status == 0
        ? '${service.toUpperCase()}_NETWORK'
        : '${service.toUpperCase()}_$status',
    route: route,
  );
}
