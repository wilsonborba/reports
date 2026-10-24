import 'package:flutter/foundation.dart';

import '../utils/browser.dart';
import 'api_client.dart';

/// The signed-in Asodya user as Reports sees it (engine `GET /me` plus the gateway user info).
class SessionUser {
  final String userId;
  final String name;
  final String email;

  /// viewer, project_admin or super_admin
  final String role;
  final bool isSuperAdmin;
  final List<String> adminProjects;

  const SessionUser({
    required this.userId,
    this.name = '',
    this.email = '',
    this.role = 'viewer',
    this.isSuperAdmin = false,
    this.adminProjects = const [],
  });

  /// Kept for the identity block: Reports logins always come from Asodya Auth.
  String get provider => 'Asodya';

  factory SessionUser.fromMe(Map<String, dynamic> j) => SessionUser(
        userId: '${j['user_id'] ?? ''}',
        role: '${j['role'] ?? 'viewer'}',
        isSuperAdmin: j['is_super_admin'] == true,
        adminProjects: [for (final p in (j['admin_projects'] as List? ?? const [])) '$p'],
      );

  SessionUser withInfo({String? name, String? email}) => SessionUser(
        userId: userId,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role,
        isSuperAdmin: isSuperAdmin,
        adminProjects: adminProjects,
      );
}

enum SessionState { unknown, guest, signedIn }

/// Session state of this browser.
///
/// The real session is the httpOnly `sid` cookie of the gateway. Its readable companion
/// cookie `csrf` says that a session may exist (no network call for guests); the engine
/// `GET /me` confirms it. A rejected session becomes a guest at once, without any
/// redirect, so the app never loops between login and the page.
class SessionStore extends ChangeNotifier {
  static SessionStore instance = SessionStore();

  SessionStore({ApiClient? api, this.cookieReader = readCookie}) : _api = api;

  ApiClient? _api;
  ApiClient get api => _api ??= ApiClient();
  set api(ApiClient value) => _api = value;

  /// Injectable for tests (VM tests have no cookie jar).
  final String? Function(String name) cookieReader;

  SessionState _state = SessionState.unknown;
  SessionUser? _user;
  Future<void>? _loading;

  /// True when the last check ended a session that the browser still claimed.
  bool sessionEnded = false;

  SessionState get state => _state;
  SessionUser? get user => _user;
  bool get hasSession => _state == SessionState.signedIn;
  bool get isLoaded => _state != SessionState.unknown;

  /// Checks once; later calls reuse the answer until [refresh].
  Future<void> ensureLoaded() => _loading ??= _check();

  /// Checks the session again (after login, logout or a 401).
  Future<void> refresh() => _loading = _check();

  Future<void> _check() async {
    final csrf = cookieReader('csrf');
    if (csrf == null || csrf.isEmpty) {
      _set(SessionState.guest, null);
      return;
    }
    try {
      final me = await api.getJson('/me');
      _set(SessionState.signedIn, SessionUser.fromMe(me));
    } on ApiException catch (e) {
      if (e.needsLogin || e.accessLimited) {
        // The gateway refused the session (expired or revoked): guest, no redirect.
        sessionEnded = true;
        _set(SessionState.guest, null);
      } else {
        // Engine unreachable: keep what the browser says, the next call reports it.
        _set(SessionState.guest, null);
      }
    }
  }

  /// Name and email from the gateway (best effort).
  void updateInfo({String? name, String? email}) {
    final u = _user;
    if (u == null) return;
    _user = u.withInfo(name: name, email: email);
    notifyListeners();
  }

  /// A session route answered 401: the session is gone.
  void markExpired() {
    if (_state != SessionState.signedIn) return;
    sessionEnded = true;
    _loading = Future.value();
    _set(SessionState.guest, null);
  }

  void clear() {
    _loading = Future.value();
    _set(SessionState.guest, null);
  }

  void _set(SessionState state, SessionUser? user) {
    _state = state;
    _user = user;
    notifyListeners();
  }

  /// Sets a session in memory only (widget tests).
  @visibleForTesting
  void setForTest(SessionUser? user) {
    _loading = Future.value();
    _set(user == null ? SessionState.guest : SessionState.signedIn, user);
  }
}
