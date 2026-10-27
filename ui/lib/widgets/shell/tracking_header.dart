import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/tracking_manifest.dart';
import '../../l10n/strings.dart';
import 'top_bar.dart';

/// Maps the existing shared header without changing its widgets or design.
class ReportsTrackingRoot extends StatelessWidget {
  const ReportsTrackingRoot({
    super.key,
    required this.tracker,
    required this.child,
  });
  final AsodyaTracker tracker;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final aliases = <String, TrackingElement>{
      for (final tab in TopBar.tabs)
        context.tr(tab.labelKey): reportElements['shell.navigation.${tab.id}']!,
      'EN': reportElements['shell.language.english']!,
      'PT': reportElements['shell.language.portuguese']!,
      'TH': reportElements['shell.language.thai']!,
      context.tr('switch_to_light'): reportElements['shell.theme.toggle']!,
      context.tr('switch_to_dark'): reportElements['shell.theme.toggle']!,
      context.tr('pub_nav_open_menu'): reportElements['shell.navigation.menu']!,
      context.tr('pub_nav_close_menu'):
          reportElements['shell.navigation.close']!,
      context.tr('auth_log_out'): reportElements['shell.account.logout']!,
    };
    return TrackingRoot(
      tracker: tracker,
      locale: context.langCode,
      resolveElement: (event, result) {
        if (tracker.currentScreen.name == 'embed') return null;
        if (event.position.dy < TopBar.height &&
            event.position.dx < 175 &&
            result.path.any(
              (entry) =>
                  entry.target is RenderSemanticsAnnotations &&
                  (entry.target as RenderSemanticsAnnotations)
                          .properties
                          .link ==
                      true,
            )) {
          return reportElements['shell.navigation.home'];
        }
        return elementFromSemantics(result, aliases);
      },
      child: child,
    );
  }
}
