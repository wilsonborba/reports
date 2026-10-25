import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import 'package:go_router/go_router.dart';
import '../../services/catalog_service.dart';
import '../../services/session_store.dart';
import '../../themes/catalog_brands.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_controller.dart';
import '../../themes/theme_registry.dart';
import '../../routes.dart';
import 'guest_prompt.dart';
import 'sidebar.dart';
import 'top_bar.dart';

/// Frame of every screen: top bar on top, page content below. Inside a project the
/// whole frame uses the theme of that project from the catalog API; outside, and until
/// the catalog answers, the Reports theme.
class AppShell extends StatefulWidget {
  final String? project;
  final String? report;
  final Widget child;

  /// The landing page has no sidebar.
  final bool showSidebar;

  const AppShell({super.key, required this.project, this.report, required this.child, this.showSidebar = true});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String? _requested;

  @override
  void initState() {
    super.initState();
    SessionStore.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    SessionStore.instance.removeListener(_onSession);
    super.dispose();
  }

  /// The gateway ended the session: say so once, change nothing else (the guest prompt
  /// offers the login).
  void _onSession() {
    final session = SessionStore.instance;
    if (!session.sessionEnded || !mounted) return;
    session.sessionEnded = false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      key: const Key('session_ended'),
      content: Text(context.tr('auth_session_ended_text')),
      duration: const Duration(seconds: 8),
    ));
  }

  void _ensureCatalog(String lang) {
    final key = '${widget.project}/$lang';
    if (widget.project == null || _requested == key) return;
    _requested = key;
    // Loads the project texts, theme and logos; CatalogBrands notifies when they arrive.
    CatalogService.instance.project(widget.project!, lang: lang).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    _ensureCatalog(context.langCode);
    final brightness = ThemeScope.of(context).brightness;
    return ListenableBuilder(
      listenable: CatalogBrands.instance,
      builder: (context, _) => Theme(
        data: ThemeRegistry.theme(widget.project, brightness),
        child: Builder(
          builder: (context) {
            final path = GoRouterState.of(context).uri.path;
            final inReports = path.startsWith(AppRoutes.menu);
            return Scaffold(
              backgroundColor: context.palette.canvas,
              body: Column(
                children: [
                  const TopBar(),
                  Expanded(
                    child: Stack(children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.showSidebar) Sidebar(project: widget.project, report: widget.report),
                          // The content takes the remaining width and adjusts when the sidebar changes.
                          Expanded(child: widget.child),
                        ],
                      ),
                      // A guest in the report area gets the sign in prompt at the bottom.
                      if (inReports)
                        Positioned(left: 0, right: 0, bottom: 20, child: Center(child: GuestPrompt(returnTo: path))),
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
