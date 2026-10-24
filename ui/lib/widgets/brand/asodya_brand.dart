import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';

/// Shared Asodya identity used by the application shell and the public site.
/// The mark is the same source asset used by the Asodya applications.
class AsodyaBrand extends StatelessWidget {
  final double logoSize;
  final bool showName;

  const AsodyaBrand({super.key, this.logoSize = 28, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: context.tr('app_name'),
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/asodya_logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            semanticLabel: context.tr('asodya_logo'),
            errorBuilder: (_, _, _) =>
                Icon(Icons.data_usage_rounded, size: logoSize, color: p.accent),
          ),
          if (showName) ...[
            const SizedBox(width: 9),
            Text(
              context.tr('app_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
