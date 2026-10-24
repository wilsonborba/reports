import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../export/card_filter_state.dart';
import '../../services/auth_service.dart';
import '../../services/catalog_service.dart';
import '../../services/report_service.dart';

/// Logs out: the gateway revokes the session, then the app clears every cached report,
/// catalog answer and card filter, and opens [to] (the public home by default).
Future<void> logOut(GoRouter router, {String to = AuthRoutes.home}) async {
  await AuthService.instance.logOut();
  ReportService.instance.clear();
  CatalogService.instance.clear();
  CardFilterState.instance.clear();
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith('catalog_cache:')).toList()) {
      await prefs.remove(key);
    }
  } catch (_) {}
  router.go(to);
}
