import 'package:flutter/foundation.dart';
import 'export_plan.dart';

enum ArtifactFormat { pdf, md, csv }

enum ArtifactState { idle, running, saved, failed }

class ArtifactJob {
  final ArtifactState state;
  final ExportProgress? progress;
  final String? file;

  const ArtifactJob(this.state, {this.progress, this.file});

  static const idle = ArtifactJob(ArtifactState.idle);
}

typedef ArtifactRunner = Future<ExportFile> Function(ArtifactFormat format, ProgressSink progress);

/// Export jobs of one report page: one per format, each with its own progress.
/// A finished file goes to [save] (the browser download).
class ArtifactJobs extends ChangeNotifier {
  final ArtifactRunner runner;
  final void Function(ExportFile file) save;
  final Map<ArtifactFormat, ArtifactJob> _jobs = {};
  bool _disposed = false;

  ArtifactJobs({required this.runner, required this.save});

  ArtifactJob job(ArtifactFormat f) => _jobs[f] ?? ArtifactJob.idle;

  bool get busy => _jobs.values.any((j) => j.state == ArtifactState.running);

  void _set(ArtifactFormat f, ArtifactJob job) {
    if (_disposed) return;
    _jobs[f] = job;
    notifyListeners();
  }

  /// Starts an export; a running export of the same format is not started twice.
  Future<void> start(ArtifactFormat f, {required String preparing}) async {
    if (job(f).state == ArtifactState.running) return;
    _set(f, ArtifactJob(ArtifactState.running, progress: ExportProgress(preparing)));
    try {
      final file = await runner(f, (p) => _set(f, ArtifactJob(ArtifactState.running, progress: p)));
      save(file);
      _set(f, ArtifactJob(ArtifactState.saved, file: file.name));
    } catch (e, st) {
      debugPrint('Export ${f.name} failed: $e\n$st');
      _set(f, const ArtifactJob(ArtifactState.failed));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
