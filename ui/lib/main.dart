import 'views/embed_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'l10n/strings.dart';
import 'routes.dart';
import 'services/auth_service.dart';
import 'services/client_telemetry_service.dart';
import 'themes/theme_controller.dart';
import 'themes/theme_registry.dart';
import 'views/landing_view.dart';
import 'views/public/architecture_view.dart';
import 'views/public/contact_view.dart';
import 'views/public/overview_view.dart';
import 'views/public/projects_view.dart';
import 'views/public/science_view.dart';
import 'views/report_list_view.dart';
import 'views/dataset_full_view.dart';
import 'views/report_page_view.dart';
import 'views/sync_view.dart';
import 'widgets/shell/app_shell.dart';
import 'services/session_store.dart';
import 'core/config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ClientTelemetryService.instance.init();
  // Path URLs without the hash sign. The base href is / (see ui/scripts/build_cloudflare.sh).
  usePathUrlStrategy();
  runApp(const ReportsApp());
}

class ReportsApp extends StatefulWidget {
  /// First route; tests open deep links with it.
  final String initialLocation;

  const ReportsApp({super.key, this.initialLocation = AppRoutes.home});

  @override
  State<ReportsApp> createState() => _ReportsAppState();
}

class _ReportsAppState extends State<ReportsApp> {
  late final GoRouter _router;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ThemeController _theme = ThemeController();
  final LanguageController _language = LanguageController();

  @override
  void initState() {
    super.initState();
    _theme.load();
    _language.load();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      navigatorKey: _navigatorKey,
      // No route needs a session up front: guests browse the public reports, and the
      // engine decides per card. Nothing here redirects to the login page.
      routes: <RouteBase>[
        // auth_apps returns here with the one-time exchange token.
        GoRoute(
          path: AuthRoutes.sync,
          builder: (context, state) => SyncView(token: state.uri.queryParameters[ReportsConfig.exchangeTokenParam]),
        ),
        // Old links of the previous login flow open the public site.
        GoRoute(path: '/v1/sync', redirect: (context, state) => AppRoutes.home),
        GoRoute(path: '/v1/login-required', redirect: (context, state) => AppRoutes.home),
        // The root and /v1 open the public site.
        GoRoute(
          path: '/',
          redirect: (context, state) => AppRoutes.home,
        ),
        GoRoute(
          path: '/v1',
          redirect: (context, state) => AppRoutes.home,
        ),
        // Compact, public item view: no app shell or full-report navigation.
        GoRoute(
          path: '/v1/embed/:project/:report/:dataset',
          builder: (context,state) => EmbedView(
            key: ValueKey(state.uri.toString()),
            project:state.pathParameters['project']!,report:state.pathParameters['report']!,dataset:state.pathParameters['dataset']!,
            language:state.uri.queryParameters['lang'] ?? context.langCode,query:state.uri.queryParameters,
          ),
        ),
        // Every page lives inside the app shell (top bar and project theme).
        ShellRoute(
          builder: (context, state, child) => AppShell(
            project: state.pathParameters['project'],
            report: state.pathParameters['report'],
            // The landing page (/v1/menu) has no sidebar.
            showSidebar: state.pathParameters['project'] != null,
            child: child,
          ),
          routes: <RouteBase>[
            // Public site (no session): /v1/home, /v1/home/projects, /v1/home/science[/:topic], /v1/home/api, /v1/home/contact
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const OverviewView(),
              routes: <RouteBase>[
                GoRoute(path: 'projects', builder: (context, state) => const ProjectsView()),
                GoRoute(
                  path: 'science',
                  builder: (context, state) => const ScienceView(),
                  routes: <RouteBase>[
                    GoRoute(path: ':topic', builder: (context, state) => ScienceTopicView(topic: state.pathParameters['topic']!)),
                  ],
                ),
                GoRoute(path: 'architecture', builder: (context, state) => const ArchitectureView()),
                GoRoute(path: 'api', redirect: (context, state) => AppRoutes.homeArchitecture),
                GoRoute(path: 'contact', builder: (context, state) => const ContactView()),
              ],
            ),
            // Hierarchical menu tree: /v1/menu -> /v1/menu/:project -> /v1/menu/:project/:report
            GoRoute(
              path: AppRoutes.menu,
              builder: (context, state) => const LandingView(),
              routes: <RouteBase>[
                GoRoute(
                  path: ':project',
                  builder: (context, state) => ReportListView(project: state.pathParameters['project']!),
                  routes: <RouteBase>[
                    GoRoute(
                      path: ':report',
                      builder: (context, state) => ReportPageView(
                        project: state.pathParameters['project']!,
                        report: state.pathParameters['report']!,
                        section: int.tryParse(state.uri.queryParameters['section'] ?? '') ?? 1,
                      ),
                      routes: <RouteBase>[
                        // One chart with all rows: /v1/menu/:project/:report/:dataset
                        GoRoute(
                          path: ':dataset',
                          builder: (context, state) => DatasetFullView(
                            project: state.pathParameters['project']!,
                            report: state.pathParameters['report']!,
                            datasetId: state.pathParameters['dataset']!,
                            visual: DatasetFullView.visualOf(state.uri.queryParameters['visual']),
                            filters: DatasetFullView.filtersOf(state.uri.queryParameters),
                            table: state.uri.queryParameters['view'] == 'table',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    // One session check per page load (no network call for a browser without session).
    SessionStore.instance.ensureLoaded().then((_) {
      if (SessionStore.instance.hasSession) AuthService.instance.loadUserInfo();
    });
  }

  @override
  void dispose() {
    _theme.dispose();
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_theme, _language]),
      builder: (context, _) => MaterialApp.router(
        title: 'Reports',
        debugShowCheckedModeBanner: false,
        // Screens outside a project use the Reports theme; project screens
        // apply their own static theme in the same brightness.
        theme: ThemeRegistry.theme(null, _theme.brightness),
        routerConfig: _router,
        builder: (context, child) => ThemeScope(
          controller: _theme,
          child: LanguageScope(controller: _language, child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
