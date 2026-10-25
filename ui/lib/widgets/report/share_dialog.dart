import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../layouts/report_layout.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../utils/browser.dart';

/// Path of one chart in the full view with its state: chart type, chart or table, and the
/// card filters. Whoever opens the link sees the chart as it was shared.
String chartPath({
  required String project,
  required String report,
  required String datasetId,
  Visual visual = Visual.auto,
  bool table = false,
  Map<String, String> filters = const {},
}) {
  final query = <String, String>{
    if (visual != Visual.auto) 'visual': visual.name,
    if (table) 'view': 'table',
    ...filters,
  };
  return Uri(path: AppRoutes.dataset(project, report, datasetId), queryParameters: query.isEmpty ? null : query).toString();
}

/// Share dialog of a public chart: the full link as selectable text (Ctrl+C works) and a
/// button that copies it.
Future<void> showShareDialog(BuildContext context, String path) {
  final url = '${currentOrigin()}$path';
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return AlertDialog(
        key: const Key('share_dialog'),
        title: Text(ctx.tr('share_title')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ctx.tr('share_text'), style: TextStyle(fontSize: 13.5, color: p.textMuted, height: 1.45)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(ReportPalette.controlRadius),
              ),
              child: SelectableText(url, key: const Key('share_url'), style: TextStyle(fontFamily: ReportPalette.monoFont, fontSize: 12.5, color: p.textPrimary)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('close'))),
          FilledButton.icon(
            key: const Key('share_copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(key: const Key('share_copied'), content: Text(context.tr('share_copied'))));
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: Text(ctx.tr('share_copy')),
          ),
        ],
      );
    },
  );
}
