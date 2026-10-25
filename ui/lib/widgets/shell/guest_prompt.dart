import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../models/report.dart';
import '../../services/auth_service.dart';
import '../../services/session_store.dart';
import '../../themes/report_palette.dart';

/// Medium prompt at the bottom of the report area for a guest: sign in or create an
/// account to see more dashboards (Carbon actionable notification). It is the only sign in
/// action of the report area. Closing it keeps it closed for this visit.
class GuestPrompt extends StatefulWidget {
  /// Page to come back to after the login.
  final String returnTo;

  const GuestPrompt({super.key, required this.returnTo});

  /// Access counts of the open report, from the engine (null outside a report).
  static final ValueNotifier<AccessSummary?> report = ValueNotifier(null);

  /// True after the guest closed the prompt (this visit only).
  static bool dismissed = false;

  @override
  State<GuestPrompt> createState() => _GuestPromptState();
}

class _GuestPromptState extends State<GuestPrompt> {
  void _close() => setState(() => GuestPrompt.dismissed = true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SessionStore.instance, GuestPrompt.report]),
      builder: (context, _) {
        final session = SessionStore.instance;
        if (GuestPrompt.dismissed || !session.isLoaded || session.hasSession) return const SizedBox.shrink();
        final locked = GuestPrompt.report.value?.needsSignIn ?? 0;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child)),
          child: _card(context, locked),
        );
      },
    );
  }

  Widget _card(BuildContext context, int locked) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final title = locked > 0 ? context.tr('guest_prompt_locked_title', {'n': locked}) : context.tr('guest_prompt_title');
    return Semantics(
      container: true,
      liveRegion: true,
      label: title,
      child: Container(
        key: const Key('guest_prompt'),
        width: width < 600 ? width - 32 : 560,
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
        decoration: BoxDecoration(
          color: p.surface,
          // Square corners: the accent stripe on the left and the outline differ in color.
          border: Border(left: BorderSide(color: p.accent, width: 4), top: BorderSide(color: p.border), right: BorderSide(color: p.border), bottom: BorderSide(color: p.border)),
          // Neutral, light shadow only to lift it off the cards (no colored glow).
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.insights_rounded, size: 22, color: p.accent)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textPrimary)),
              const SizedBox(height: 4),
              Text(context.tr('guest_prompt_text'), style: TextStyle(fontSize: 13.5, color: p.textMuted, height: 1.45)),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: [
                FilledButton(
                  key: const Key('guest_prompt_sign_in'),
                  onPressed: () => AuthService.instance.signIn(returnTo: widget.returnTo),
                  child: Text(context.tr('sign_in')),
                ),
                TextButton(
                  key: const Key('guest_prompt_sign_up'),
                  onPressed: () => AuthService.instance.signIn(returnTo: widget.returnTo, signUp: true),
                  child: Text(context.tr('sign_up')),
                ),
              ]),
            ]),
          ),
          IconButton(
            key: const Key('guest_prompt_close'),
            tooltip: context.tr('close'),
            icon: Icon(Icons.close_rounded, size: 20, color: p.textMuted),
            onPressed: _close,
          ),
        ]),
      ),
    );
  }
}
