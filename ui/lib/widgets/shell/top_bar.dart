import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_controller.dart';
import '../brand/asodya_brand.dart';
import '../../services/auth_service.dart';
import '../../services/session_store.dart';
import 'session_prompt.dart';

/// One page of the public site navigation.
class PublicTab {
  final String id;
  final String route;
  final String labelKey;

  const PublicTab(this.id, this.route, this.labelKey);

  /// True when [path] is this page or a page below it (the overview matches itself only).
  bool matches(String path) => route == AppRoutes.home ? path == route || path == '$route/' : path.startsWith(route);
}

/// Top bar: the Asodya mark and Reports name on the left (opens the public site), the public site
/// tabs in the middle, the "Reports" button, the language and theme switches on the right.
/// Narrow screens replace the tabs and the Reports button with a menu button.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});

  static const double height = 52;

  /// Narrowest screen that shows the tabs in the bar; narrower screens use the menu button.
  static const double tabsMinWidth = 1100;

  static const List<PublicTab> tabs = [
    PublicTab('overview', AppRoutes.home, 'pub_nav_overview'),
    PublicTab('projects', AppRoutes.homeProjects, 'pub_nav_projects'),
    PublicTab('science', AppRoutes.homeScience, 'pub_nav_science'),
    PublicTab('architecture', AppRoutes.homeArchitecture, 'pub_nav_architecture'),
    PublicTab('contact', AppRoutes.homeContact, 'pub_nav_contact'),
  ];

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return _bar(context, '');
    // The bar is a constant widget: it listens to the router to mark the current tab.
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _bar(context, router.state.uri.path),
    );
  }

  Widget _bar(BuildContext context, String path) {
    final p = context.palette;
    final theme = ThemeScope.of(context);
    final lang = LanguageScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= tabsMinWidth;
    final compact = MediaQuery.sizeOf(context).width < 520;
    final inReports = path.startsWith(AppRoutes.menu);
    final inPublicSite = path == AppRoutes.home || path.startsWith('${AppRoutes.home}/');
    final name = Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        link: true,
        child: InkWell(
          key: const Key('top_bar_home'),
          borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          onTap: () => context.go(AppRoutes.home),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: AsodyaBrand(showName: !compact),
          ),
        ),
      ),
    );
    final switches = <Widget>[
      _LanguageSwitch(code: lang.code, onChanged: (c) => lang.set(c == 'th' ? AppLanguage.th : c == 'pt-BR' ? AppLanguage.pt : AppLanguage.en)),
      const SizedBox(width: 6),
      IconButton(
        key: const Key('top_bar_theme'),
        tooltip: context.tr(theme.isDark ? 'switch_to_light' : 'switch_to_dark'),
        icon: Icon(theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20),
        onPressed: theme.toggle,
      ),
      const SizedBox(width: 4),
      _SessionButton(path: path),
    ];
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: inPublicSite
          ? (wide
              // Equal sides keep the tabs in the middle of the bar.
              ? Row(children: [
                  name,
                  const Spacer(),
                  Semantics(
                    container: true,
                    label: context.tr('pub_nav_label'),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final t in tabs) _Tab(tab: t, selected: t.matches(path)),
                    ]),
                  ),
                  const Spacer(),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _ReportsButton(selected: inReports),
                    const SizedBox(width: 12),
                    ...switches,
                  ]),
                ])
              // The name gives way on narrow phones; the switches and the menu keep their size.
              : Row(children: [
                  Expanded(child: name),
                  ...switches,
                  IconButton(
                    key: const Key('top_bar_menu'),
                    tooltip: context.tr('pub_nav_open_menu'),
                    icon: const Icon(Icons.menu_rounded, size: 22),
                    onPressed: () => _openMenu(context, path),
                  ),
                ]))
          : Row(children: [
              Expanded(child: name),
              ...switches,
            ]),
    );
  }

  /// Panel below the bar with the same links as the tabs and the Reports button.
  void _openMenu(BuildContext context, String path) {
    final router = GoRouter.of(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.tr('pub_nav_close_menu'),
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _MenuPanel(
        path: path,
        onSelect: (route) {
          Navigator.of(dialogContext).pop();
          router.go(route);
        },
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.04), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
    );
  }
}

/// Tab of the public site: text with a thick line under the current page (Carbon header).
class _Tab extends StatelessWidget {
  final PublicTab tab;
  final bool selected;

  const _Tab({required this.tab, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      link: true,
      child: InkWell(
        key: Key('nav_tab_${tab.id}'),
        onTap: () => context.go(tab.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: TopBar.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? p.accent : Colors.transparent, width: 3)),
          ),
          child: Text(
            context.tr(tab.labelKey),
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? p.textPrimary : p.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Reports" button: opens the report area (/v1/menu).
class _ReportsButton extends StatelessWidget {
  final bool selected;

  const _ReportsButton({required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: context.tr('pub_nav_reports_hint'),
      child: FilledButton.icon(
        key: const Key('nav_reports'),
        onPressed: () => context.go(AppRoutes.menu),
        style: FilledButton.styleFrom(
          backgroundColor: selected ? p.surfaceAlt : p.accent,
          foregroundColor: selected ? p.textPrimary : p.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          minimumSize: const Size(0, 36),
        ),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: Text(context.tr('pub_nav_reports'), style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Menu panel of narrow screens: one row per page, the current page marked on the left.
class _MenuPanel extends StatelessWidget {
  final String path;
  final ValueChanged<String> onSelect;

  const _MenuPanel({required this.path, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String id, String route, String label, bool selected, {IconData? icon}) => Semantics(
          selected: selected,
          link: true,
          child: InkWell(
            key: Key('nav_menu_$id'),
            onTap: () => onSelect(route),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: selected ? p.surfaceAlt : Colors.transparent,
                border: Border(left: BorderSide(color: selected ? p.accent : Colors.transparent, width: 3)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: p.textPrimary)),
                ),
                if (icon != null) Icon(icon, size: 18, color: p.textMuted),
              ]),
            ),
          ),
        );
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: TopBar.height),
        child: Material(
          color: p.surface,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final t in TopBar.tabs) row(t.id, t.route, context.tr(t.labelKey), t.matches(path)),
                Divider(height: 1, color: p.border),
                row('reports', AppRoutes.menu, context.tr('pub_nav_reports'), path.startsWith(AppRoutes.menu),
                    icon: Icons.arrow_forward_rounded),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSwitch extends StatelessWidget {
  final String code;
  final ValueChanged<String> onChanged;

  const _LanguageSwitch({required this.code, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget option(String value, String label) {
      final selected = code == value;
      return InkWell(
        key: Key('lang_$value'),
        borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? p.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: selected ? p.onAccent : p.textMuted)),
        ),
      );
    }

    return Tooltip(
      message: context.tr('switch_language'),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [option('en', 'EN'), option('pt-BR', 'PT'), option('th', 'TH')]),
      ),
    );
  }
}

/// Sign in (guest) or log out (signed in). A guest returns to this page after the login.
class _SessionButton extends StatelessWidget {
  final String path;

  const _SessionButton({required this.path});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionStore.instance,
      builder: (context, _) {
        final session = SessionStore.instance;
        if (!session.isLoaded) return const SizedBox.shrink();
        if (session.hasSession) {
          return IconButton(
            key: const Key('top_bar_log_out'),
            tooltip: context.tr('auth_log_out'),
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => logOut(GoRouter.of(context)),
          );
        }
        final compact = MediaQuery.sizeOf(context).width < 520;
        void signIn() => AuthService.instance.signIn(returnTo: path.startsWith('/v1/') ? path : null);
        return compact
            ? IconButton(key: const Key('top_bar_sign_in'), tooltip: context.tr('sign_in'), icon: const Icon(Icons.login_rounded, size: 20), onPressed: signIn)
            : TextButton.icon(key: const Key('top_bar_sign_in'), onPressed: signIn, icon: const Icon(Icons.login_rounded, size: 18), label: Text(context.tr('sign_in')));
      },
    );
  }
}
