import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/material.dart';
import '../../export/artifact_jobs.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';

/// One "Artifacts" button with a menu: PDF report, Markdown, CSV data (ZIP). Each item
/// shows its own progress, then "Saved"; a failed item shows a retry. The menu stays
/// open while the files build.
class ArtifactsMenu extends StatelessWidget {
  final ArtifactJobs jobs;

  const ArtifactsMenu({super.key, required this.jobs});

  static const _items = [
    (
      ArtifactFormat.pdf,
      Icons.picture_as_pdf_outlined,
      'artifact_pdf',
      'artifact_pdf_hint',
    ),
    (
      ArtifactFormat.md,
      Icons.description_outlined,
      'artifact_md',
      'artifact_md_hint',
    ),
    (
      ArtifactFormat.csv,
      Icons.table_view_outlined,
      'artifact_csv',
      'artifact_csv_hint',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // The items live in an overlay: each one listens to the jobs itself.
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final (format, icon, title, hint) in _items)
          ListenableBuilder(
            listenable: jobs,
            builder: (context, _) => _item(context, format, icon, title, hint),
          ),
      ],
      builder: (context, controller, _) => ListenableBuilder(
        listenable: jobs,
        builder: (context, _) => track(
          'report.export.open',
          FilledButton.icon(
            key: const Key('artifacts_button'),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: jobs.busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.onAccent,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 16),
            label: Text(context.tr('artifacts')),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    ArtifactFormat format,
    IconData icon,
    String title,
    String hint,
  ) {
    final p = context.palette;
    final job = jobs.job(format);
    final (status, color) = switch (job.state) {
      ArtifactState.idle => (context.tr(hint), p.textMuted),
      ArtifactState.running => (
        job.progress?.text ?? context.tr('export_preparing'),
        p.textMuted,
      ),
      ArtifactState.saved => (
        context.tr('export_saved', {'file': job.file ?? ''}),
        p.positive,
      ),
      ArtifactState.failed => (context.tr('export_failed'), p.negative),
    };
    return track(
      format.name == 'md'
          ? 'report.export.markdown'
          : 'report.export.${format.name}',
      MenuItemButton(
        key: Key('artifact_${format.name}'),
        closeOnActivate: false,
        leadingIcon: Icon(
          switch (job.state) {
            ArtifactState.saved => Icons.check_circle_outline_rounded,
            ArtifactState.failed => Icons.refresh_rounded,
            _ => icon,
          },
          size: 20,
          color:
              job.state == ArtifactState.idle ||
                  job.state == ArtifactState.running
              ? p.textMuted
              : color,
        ),
        onPressed: () {
          if (job.state != ArtifactState.running) {
            jobs.start(format, preparing: context.tr('export_preparing'));
          }
        },
        child: SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr(title),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  key: Key('artifact_status_${format.name}'),
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, color: color),
                ),
                if (job.state == ArtifactState.running) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: job.progress?.fraction,
                    minHeight: 3,
                    color: p.accent,
                    backgroundColor: p.surfaceAlt,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
