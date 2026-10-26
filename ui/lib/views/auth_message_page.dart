import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/strings.dart';
import '../services/auth_service.dart';
import '../themes/report_palette.dart';

/// Simple centered page of the login flow (no shell, no session needed).
class AuthMessagePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool busy;
  final bool showHomeLink;

  /// Optional main action (for example "Sign in again").
  final String? actionLabel;
  final VoidCallback? onAction;

  const AuthMessagePage({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.busy = false,
    this.showHomeLink = true,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? const CircularProgressIndicator()
                    : Icon(icon, size: 44, color: p.textMuted),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    color: p.textPrimary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: p.textMuted,
                    height: 1.5,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 24),
                  track(
                    'auth.message.action',
                    FilledButton(
                      key: const Key('auth_action'),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
                if (showHomeLink) ...[
                  const SizedBox(height: 24),
                  track(
                    'auth.message.home',
                    TextButton(
                      key: const Key('auth_home_link'),
                      onPressed: () => context.go(AuthRoutes.home),
                      child: Text(context.tr('auth_go_home')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
