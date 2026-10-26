import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../layouts/report_layout.dart';
import '../../routes.dart';
import '../../themes/report_palette.dart';
import '../../utils/browser.dart';
import '../../services/embed_service.dart';

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
  return Uri(
    path: AppRoutes.dataset(project, report, datasetId),
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// Link and embed options of one public chart/table.
Future<void> showShareDialog(BuildContext context, String path) =>
    showDialog<void>(
      context: context,
      builder: (ctx) =>
          _ItemShareDialog(path: path, url: '${currentOrigin()}$path'),
    );

class _ItemShareDialog extends StatefulWidget {
  final String path, url;
  const _ItemShareDialog({required this.path, required this.url});
  @override
  State<_ItemShareDialog> createState() => _ItemShareDialogState();
}

class _ItemShareDialogState extends State<_ItemShareDialog> {
  bool embed = false, loading = false;
  Map<String, dynamic>? descriptor;
  bool failed = false;
  Future<void> load() async {
    if (loading || descriptor != null) return;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final data = await itemEmbed(widget.path, language: context.langCode);
      if (mounted) setState(() => descriptor = data);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.tr(embed ? 'share_embed_copied' : 'share_copied');
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(key: const Key('share_copied'), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      key: const Key('share_dialog'),
      title: Text(context.tr('share_title')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.tr('share_link')),
                    icon: const Icon(Icons.link_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.tr('share_embed')),
                    icon: const Icon(Icons.code_rounded),
                  ),
                ],
                selected: {embed},
                onSelectionChanged: (value) {
                  setState(() => embed = value.first);
                  if (embed) load();
                },
              ),
              const SizedBox(height: 16),
              Text(
                context.tr(embed ? 'share_embed_help' : 'share_text'),
                style: TextStyle(
                  fontSize: 13.5,
                  color: p.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              if (embed && loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (embed && failed)
                Text(
                  context.tr('error_loading'),
                  style: TextStyle(color: p.negative),
                ),
              if (embed && descriptor != null) ...[
                Image.network(
                  descriptor!['thumbnail_url'],
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    border: Border.all(color: p.border),
                    borderRadius: BorderRadius.circular(
                      ReportPalette.controlRadius,
                    ),
                  ),
                  child: SelectableText(
                    descriptor!['html'],
                    key: const Key('share_embed_html'),
                    style: TextStyle(
                      fontFamily: ReportPalette.monoFont,
                      fontSize: 11,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  descriptor!['embed_url'],
                  key: const Key('share_embed_url'),
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ],
              if (!embed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    border: Border.all(color: p.border),
                    borderRadius: BorderRadius.circular(
                      ReportPalette.controlRadius,
                    ),
                  ),
                  child: SelectableText(
                    widget.url,
                    key: const Key('share_url'),
                    style: TextStyle(
                      fontFamily: ReportPalette.monoFont,
                      fontSize: 12.5,
                      color: p.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('close')),
        ),
        FilledButton.icon(
          key: Key(embed ? 'share_embed_copy' : 'share_copy'),
          onPressed: embed
              ? (descriptor == null ? null : () => copy(descriptor!['html']))
              : () => copy(widget.url),
          icon: Icon(embed ? Icons.code_rounded : Icons.link_rounded, size: 18),
          label: Text(context.tr(embed ? 'share_embed_copy' : 'share_copy')),
        ),
      ],
    );
  }
}
