import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../services/report_service.dart';
import '../services/session_store.dart';
import '../utils/address_bar.dart';
import 'auth_message_page.dart';

/// `/sync`: auth_apps returns here with a one-time `auth_exchange_token`.
///
/// The token leaves the address bar at once and is redeemed exactly once. Success goes
/// to the page stored before the login. Failure shows a message with a manual "Sign in
/// again" button: nothing redirects automatically, so the app can never loop.
class SyncView extends StatefulWidget {
  final String? token;

  const SyncView({super.key, this.token});

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  bool _failed = false;
  static final Set<String> _redeemed = {};

  @override
  void initState() {
    super.initState();
    removeQueryFromAddressBar();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final token = widget.token;
    if (token == null || token.isEmpty || !_redeemed.add(token)) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final ok = await AuthService.instance.exchange(token);
    if (!ok) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    await SessionStore.instance.refresh();
    if (!SessionStore.instance.hasSession) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    AuthService.instance.loadUserInfo();
    // Caches built for the guest view must not hide signed-in content.
    CatalogService.instance.clear();
    ReportService.instance.clear();
    final next = await AuthService.instance.takeNext();
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_failed) {
      return AuthMessagePage(
        key: const Key('sync_busy'),
        icon: Icons.sync_rounded,
        title: context.tr('auth_signing_in'),
        text: context.tr('auth_signing_in_text'),
        busy: true,
        showHomeLink: false,
      );
    }
    return AuthMessagePage(
      key: const Key('sync_error'),
      icon: Icons.error_outline_rounded,
      title: context.tr('auth_sync_failed'),
      text: context.tr('auth_error_exchange'),
      actionLabel: context.tr('auth_sign_in_again'),
      onAction: () => AuthService.instance.signIn(),
    );
  }
}
