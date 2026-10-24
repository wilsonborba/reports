import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../utils/browser.dart';
import 'client_telemetry_service.dart';
import 'http_client.dart';
import 'session_store.dart';

/// Routes of the login flow.
class AuthRoutes {
  /// auth_apps returns here with `auth_exchange_token`.
  static const String sync = ReportsConfig.syncPath;
  static const String home = '/v1/home';
  static const String menu = '/v1/menu';

  /// The UI path after a login: an internal path under /v1, else /v1/menu.
  static String safeNext(String? next) {
    final n = (next ?? '').trim();
    final internal = n.startsWith('/v1/') && !n.contains('//') && !n.contains('..') && !n.contains('\\') && !n.contains(':');
    if (!internal || n.startsWith(sync)) return menu;
    return n;
  }
}

/// Asodya Auth login through auth_apps and the api_for_apps session exchange, the same
/// flow as cortex and certifications:
/// 1. [signIn] stores the page to come back to and opens auth_apps with an encrypted
///    `app_context` (app Reports, return origin of this app).
/// 2. auth_apps signs the user in and returns to `<origin>/sync?auth_exchange_token=...`.
/// 3. [exchange] redeems the one-time token at `POST /apps/api/v1/exchange`; the gateway
///    sets the httpOnly `sid` and the readable `csrf` cookies. No token is ever stored.
/// 4. [logOut] revokes the session at `POST /user/sync/v1/log-out` with the CSRF header.
class AuthService {
  static AuthService instance = AuthService();

  AuthService({http.Client? client, this.launcher, this.cookieReader = readCookie}) : _client = client ?? createCredentialsClient();

  final http.Client _client;

  /// Reads the readable `csrf` cookie (injectable for tests).
  final String? Function(String name) cookieReader;

  /// Opens a URL in this tab (injectable for tests).
  final Future<void> Function(Uri uri)? launcher;

  static const String _nextKey = 'reports_after_login';

  /// The auth_apps login URL for this app.
  Uri loginUri({required String returnOrigin}) {
    final appContext = <String, dynamic>{
      'name': 'Reports',
      'description': 'Reports, statistics and dashboards of the Asodya projects.',
      'logo_image_url': '$returnOrigin/icons/Icon-192.png',
      'url_app': returnOrigin,
      'two_fa_auth': false,
      'primary_color': '#0B0C10',
      'secondary_color': '#12151E',
      'tertiary_color': '#8C52FF',
      'quartary_color': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    final key = encrypt.Key.fromBase64(ReportsConfig.appContextFernetKey);
    final encrypted = encrypt.Encrypter(encrypt.Fernet(key)).encrypt(jsonEncode(appContext)).base64;
    return Uri.parse(ReportsConfig.authBaseUrl)
        .replace(path: ReportsConfig.authLoginRoute, queryParameters: {ReportsConfig.appContextParam: encrypted});
  }

  /// Starts a login and comes back to [returnTo] (an internal path) afterwards.
  Future<void> signIn({String? returnTo}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nextKey, AuthRoutes.safeNext(returnTo));
    } catch (_) {}
    final uri = loginUri(returnOrigin: currentOrigin());
    await (launcher ?? _launch)(uri);
  }

  static Future<void> _launch(Uri uri) => launchUrl(uri, webOnlyWindowName: '_self');

  /// The page stored by [signIn] (read once).
  Future<String> takeNext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = prefs.getString(_nextKey);
      await prefs.remove(_nextKey);
      return AuthRoutes.safeNext(next);
    } catch (_) {
      return AuthRoutes.menu;
    }
  }

  /// Redeems the one-time token. True when the gateway opened a session.
  Future<bool> exchange(String token) async {
    const path = '/apps/api/v1/exchange';
    try {
      final res = await _client
          .post(Uri.parse('${ReportsConfig.gatewayBaseUrl}$path'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({ReportsConfig.exchangeTokenParam: token, 'app': ReportsConfig.appIdentifier}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return true;
      ClientTelemetryService.instance.reportServiceFailure(
          service: 'gateway', method: 'POST', path: path, status: res.statusCode, route: AuthRoutes.sync);
      return false;
    } catch (e) {
      ClientTelemetryService.instance.reportServiceFailure(
          service: 'gateway', method: 'POST', path: path, status: 0, message: '$e', route: AuthRoutes.sync);
      return false;
    }
  }

  /// Name and email of the signed-in user from the gateway (best effort).
  Future<void> loadUserInfo() async {
    const path = '/user/info/v1/';
    try {
      final res = await _client.get(Uri.parse('${ReportsConfig.gatewayBaseUrl}$path')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        if (res.statusCode != 401 && res.statusCode != 403) {
          ClientTelemetryService.instance.reportServiceFailure(service: 'gateway', method: 'GET', path: path, status: res.statusCode);
        }
        return;
      }
      final data = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data'];
      if (data is Map) {
        final name = '${data['full_name'] ?? data['name'] ?? ''}'.trim();
        SessionStore.instance.updateInfo(name: name.isEmpty ? null : name, email: data['email'] as String?);
      }
    } catch (e) {
      ClientTelemetryService.instance.reportServiceFailure(service: 'gateway', method: 'GET', path: path, status: 0, message: '$e');
    }
  }

  /// Revokes the gateway session, then clears the local signal. Never throws.
  Future<void> logOut() async {
    const path = '/user/sync/v1/log-out';
    final csrf = cookieReader('csrf');
    try {
      final res = await _client
          .post(Uri.parse('${ReportsConfig.gatewayBaseUrl}$path'), headers: {
            if (csrf != null && csrf.isNotEmpty) 'X-CSRF-Token': csrf,
            if (csrf != null && csrf.isNotEmpty) 'X-CSRFToken': csrf,
          })
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 300 && res.statusCode != 401 && res.statusCode != 403) {
        ClientTelemetryService.instance.reportServiceFailure(service: 'gateway', method: 'POST', path: path, status: res.statusCode);
      }
    } catch (e) {
      ClientTelemetryService.instance.reportServiceFailure(service: 'gateway', method: 'POST', path: path, status: 0, message: '$e');
    }
    deleteCookie('csrf');
    SessionStore.instance.clear();
  }
}
