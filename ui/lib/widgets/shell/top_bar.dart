import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/session_store.dart';
import 'session_prompt.dart';
import '../../l10n/strings.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../themes/theme_controller.dart';
import '../brand/asodya_brand.dart';

/// One page of the public site navigation.
class PublicTab {
  final String id;
  final String route;
  final String labelKey;

  const PublicTab(this.id, this.route, this.labelKey);

  /// True when [path] is this page or a page below it (the overview matches itself only).
  bool matches(String path) => route == AppRoutes.home ? path == route || path == '$route/' : path.startsWith(route);
}

/// Top bar of every page (Carbon UI shell header): the Asodya mark on the left (opens the
/// public site), the navigation tabs in the middle (Reports is one of them), the language and
/// theme switches on the right. Narrow screens replace the tabs with a menu button. Session:
/// on the public site a signed-in user gets Log out at the right end; in the report area the
/// sidebar has it. A guest signs in from the overview hero or the report area prompt.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});

  static const double height = 52;

  /// Narrowest screen that shows the tabs in the bar; narrower screens use the menu button.
  static const double tabsMinWidth = 1100;

  static const List<PublicTab> tabs = [
    PublicTab('overview', AppRoutes.home, 'pub_nav_overview'),
    PublicTab('projects', AppRoutes.homeProjects, 'pub_nav_projects'),
    PublicTab('reports', AppRoutes.menu, 'pub_nav_reports'),
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
      if (!path.startsWith(AppRoutes.menu)) const _PublicLogOut(),
    ];
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: wide
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
              Row(mainAxisSize: MainAxisSize.min, children: switches),
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
            ]),
    );
  }

  /// Panel below the bar with the same links as the tabs.
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

/// Menu panel of narrow screens: one row per page, the current page marked on the left.
class _MenuPanel extends StatelessWidget {
  final String path;
  final ValueChanged<String> onSelect;

  const _MenuPanel({required this.path, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String id, String route, String label, bool selected) => Semantics(
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

/// Log out of a signed-in user on the public site (the report area has it in the sidebar).
/// An icon button with a tooltip: the six tabs leave no room for a label at desktop width.
class _PublicLogOut extends StatelessWidget {
  const _PublicLogOut();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionStore.instance,
      builder: (context, _) => SessionStore.instance.hasSession
          ? IconButton(
              key: const Key('top_bar_log_out'),
              tooltip: context.tr('auth_log_out'),
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => logOut(GoRouter.of(context)),
            )
          : const SizedBox.shrink(),
    );
  }
}
