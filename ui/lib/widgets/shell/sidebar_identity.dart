import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/strings.dart';
import '../../services/session_store.dart';
import '../../themes/report_palette.dart';
import '../../core/build_info.dart';
import 'session_prompt.dart';

/// Bottom of the sidebar: the signed-in user (avatar, name, identification, role) with a
/// Log out button, and below it the deploy time. Without a session only the deploy time shows.
class SidebarFooter extends StatefulWidget {
  final bool open;

  /// Deploy time text; only the value shows, never a label.
  final String stamp;

  const SidebarFooter({
    super.key,
    required this.open,
    this.stamp = buildTimestamp,
  });

  @override
  State<SidebarFooter> createState() => _SidebarFooterState();
}

class _SidebarFooterState extends State<SidebarFooter> {
  @override
  void initState() {
    super.initState();
    // Name and email come from the gateway after the session check (see main.dart).
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionStore.instance,
      builder: (context, _) {
        final user = SessionStore.instance.hasSession
            ? SessionStore.instance.user
            : null;
        final showStamp = widget.open && widget.stamp.isNotEmpty;
        if (user == null && !showStamp) return const SizedBox.shrink();
        final p = context.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(height: 1, color: p.border),
            if (user != null)
              _IdentityBlock(
                user: user,
                open: widget.open,
                stamp: widget.stamp,
              ),
            if (showStamp)
              Padding(
                padding: EdgeInsets.fromLTRB(16, user == null ? 10 : 0, 16, 10),
                child: Text(
                  widget.stamp,
                  key: const Key('deploy_stamp'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  final SessionUser user;
  final bool open;
  final String stamp;

  const _IdentityBlock({
    required this.user,
    required this.open,
    required this.stamp,
  });

  String _role(BuildContext context) {
    final key = 'auth_role_${user.role}';
    final role = Strings.values.containsKey(key) ? context.tr(key) : user.role;
    return user.provider.isEmpty ? role : '$role · ${user.provider}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = user.name.isEmpty ? user.userId : user.name;
    final avatar = CircleAvatar(
      key: const Key('identity_avatar'),
      radius: 15,
      backgroundColor: p.accent,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: p.onAccent,
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          key: const Key('identity_name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        if (user.email.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            user.email,
            key: const Key('identity_identification'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.25, color: p.textMuted),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _role(context),
          key: const Key('identity_role'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: p.textMuted,
          ),
        ),
      ],
    );
    final tooltip = [
      name,
      if (user.email.isNotEmpty) user.email,
      _role(context),
      if (stamp.isNotEmpty) stamp,
    ].join('\n');
    void onLogOut() => logOut(GoRouter.of(context));
    if (!open) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              key: const Key('identity_block'),
              message: tooltip,
              child: avatar,
            ),
            const SizedBox(height: 8),
            IconButton(
              key: const Key('identity_log_out'),
              tooltip: context.tr('auth_log_out'),
              icon: Icon(Icons.logout_rounded, size: 18, color: p.textMuted),
              onPressed: onLogOut,
            ),
          ],
        ),
      );
    }
    return Padding(
      key: const Key('identity_block'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(child: details),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('identity_log_out'),
            onPressed: onLogOut,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: Text(context.tr('auth_log_out')),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.border),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
