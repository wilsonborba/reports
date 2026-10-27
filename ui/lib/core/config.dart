/// Runtime configuration injected at build time (Cloudflare Pages or local development).
///
/// Production: the browser calls the api_for_apps gateway at api.asodya.com; the
/// gateway forwards `/apps/reports/v1/...` to the Reports engine. Development
/// (`--dart-define=DEVELOPMENT_MODE=true`) uses the LAN gateway and auth app, the same
/// hosts cortex and certifications use, with the Reports dev server on port 8110.
class ReportsConfig {
  static const bool isDevelopment = bool.fromEnvironment(
    'DEVELOPMENT_MODE',
    defaultValue: false,
  );

  /// The api_for_apps gateway.
  static const String gatewayBaseUrl = String.fromEnvironment(
    'GATEWAY_BASE_URL',
    defaultValue: isDevelopment
        ? 'http://192.168.1.103:8101'
        : 'https://api.asodya.com',
  );

  /// Reports engine through the gateway. Tests set it to '' (same origin, fake client).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '$gatewayBaseUrl/apps/reports/v1',
  );

  /// The Asodya auth app (auth_apps).
  static const String authBaseUrl = String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: isDevelopment
        ? 'http://192.168.1.103:8100'
        : 'https://auth.asodya.com',
  );

  /// Login route of auth_apps.
  static const String authLoginRoute = '/login';

  /// Sign up route of auth_apps (same app_context as the login).
  static const String authSignupRoute = '/signup';

  /// auth_apps sends the browser back to `<origin>/sync?auth_exchange_token=...`.
  static const String syncPath = '/sync';
  static const String exchangeTokenParam = 'auth_exchange_token';
  static const String appContextParam = 'app_context';

  /// App id of Reports in the gateway exchange allowlist.
  static const String appIdentifier = 'reports';

  /// Fernet key that auth_apps uses to read `app_context` (shared by every Asodya
  /// frontend, the same value as in cortex and certifications; not a secret).
  static const String appContextFernetKey =
      'mEt5jdm9aTbUYnjhQM_tY_CTQL-JvXe0u9VdKEM2KmY=';

  /// Shared frontend error telemetry of the gateway.
  static const String telemetryUrl =
      '$gatewayBaseUrl/apps/api/v1/telemetry/errors';

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.0.0',
  );
}
