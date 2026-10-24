import 'package:flutter/material.dart';
import '../../widgets/public/code_panel.dart';
import '../../widgets/public/formula_card.dart';
import '../../widgets/public/science_charts.dart';
import 'overview_view.dart';

/// Static content of one Science topic: string keys, formulas, code panels and the
/// decorative chart. The texts live in strings.dart (English and Thai).
class ScienceTopic {
  final String id;

  /// Short key of the string group (de, ds, ml, dl, st).
  final String short;
  final List<Formula> formulas;
  final List<(String title, String code, CodeLanguage language)> code;
  final Widget Function() chart;

  const ScienceTopic({required this.id, required this.short, required this.formulas, required this.chart, this.code = const []});

  String get titleKey => 'pub_topic_$short';
  String get summaryKey => 'pub_topic_${short}_short';
  String get leadKey => 'pub_sci_${short}_lead';
  String get projectsKey => 'pub_sci_${short}_projects';
  String pointTitle(int i) => 'pub_sci_${short}_p${i}_t';
  String pointText(int i) => 'pub_sci_${short}_p${i}_d';
  String get codeTitleKey => 'pub_sci_${short}_code_t';
  String get codeTextKey => 'pub_sci_${short}_code_d';
}

/// Example training configuration (illustration of planned work: Reports has no
/// prediction yet). It reads the Cortex `telemetry_event` records of schema version 1.
const String trainingConfigYaml = '''# train_request_failure.yaml
data:
  source: reports://cortex/telemetry_event
  schema_version: 1
  label: success
  features: [provider, model, task_type, tier_requested, input_tokens]
  split: { train: 0.7, validation: 0.15, test: 0.15 }
model:
  type: gradient_boosting
  classes: 2
  max_depth: 6
training:
  learning_rate: 0.05
  rounds: 400
  early_stopping: 30
  metric: f1_macro
registry:
  approval: required   # a person approves the active model''';

/// Example training loop (illustration).
const String trainingLoopPython = '''import torch
from torch import nn

model = nn.Sequential(nn.Linear(12, 64), nn.ReLU(), nn.Linear(64, 2))
loss_fn = nn.CrossEntropyLoss()
optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3)

for epoch in range(40):
    model.train()
    for features, labels in train_loader:
        optimizer.zero_grad()
        loss = loss_fn(model(features), labels)
        loss.backward()      # gradients of the loss
        optimizer.step()     # theta = theta - lr * grad
    val_f1 = evaluate(model, val_loader)
    print(f"epoch {epoch}: loss={loss.item():.3f} f1={val_f1:.3f}")''';

/// The five topics, in menu order (ids match `scienceTopics` of the page frame).
final List<ScienceTopic> scienceContent = [
  ScienceTopic(
    id: 'data-engineering',
    short: 'de',
    formulas: const [
      Formula('pub_f_lag', r'\Delta t = t_{\text{received}} - t_{\text{event}}'),
      Formula('pub_f_pass', r'p = \frac{n_{\text{valid}}}{n_{\text{received}}}'),
      Formula('pub_f_rollup', r'V_h = \sum_{i \,:\, t_i \in h} v_i'),
    ],
    code: const [('ingest_batch.json', ingestionEnvelopeJson, CodeLanguage.json)],
    chart: () => const GrowingBars(),
  ),
  ScienceTopic(
    id: 'data-science',
    short: 'ds',
    formulas: const [
      Formula('pub_f_mean', r'\bar{x} = \frac{1}{n}\sum_{i=1}^{n} x_i'),
      Formula('pub_f_std', r'\sigma = \sqrt{\frac{1}{n}\sum_{i=1}^{n}(x_i-\bar{x})^2}'),
      Formula('pub_f_pearson', r'r = \frac{\sum_i (x_i-\bar{x})(y_i-\bar{y})}{\sqrt{\sum_i (x_i-\bar{x})^2}\,\sqrt{\sum_i (y_i-\bar{y})^2}}'),
      Formula('pub_f_ols', r'\hat{\beta} = (X^{\top}X)^{-1}X^{\top}y'),
    ],
    chart: () => const ScatterFit(),
  ),
  ScienceTopic(
    id: 'machine-learning',
    short: 'ml',
    formulas: const [
      Formula('pub_f_sigmoid', r'\sigma(z) = \frac{1}{1 + e^{-z}}'),
      Formula('pub_f_softmax', r'\operatorname{softmax}(z)_k = \frac{e^{z_k}}{\sum_{j=1}^{K} e^{z_j}}'),
      Formula('pub_f_ce', r'\mathcal{L} = -\sum_{k=1}^{K} y_k \log \hat{y}_k'),
      Formula('pub_f_gd', r'\theta_{t+1} = \theta_t - \eta\, \nabla_{\theta}\, \mathcal{L}(\theta_t)'),
      Formula('pub_f_f1', r'F_1 = \frac{2PR}{P + R}'),
    ],
    code: const [
      ('train_request_failure.yaml', trainingConfigYaml, CodeLanguage.yaml),
      ('train.py', trainingLoopPython, CodeLanguage.python),
    ],
    chart: () => const LossCurves(),
  ),
  ScienceTopic(
    id: 'deep-learning',
    short: 'dl',
    formulas: const [
      Formula('pub_f_relu', r'\operatorname{ReLU}(x) = \max(0, x)'),
      Formula('pub_f_conv', r'(I * K)(i,j) = \sum_{m}\sum_{n} I(i+m,\, j+n)\, K(m,n)'),
      Formula('pub_f_iou', r'\operatorname{IoU} = \frac{|A \cap B|}{|A \cup B|}'),
      Formula('pub_f_cos', r'\cos\theta = \frac{\mathbf{a}\cdot\mathbf{b}}{\lVert\mathbf{a}\rVert\,\lVert\mathbf{b}\rVert}'),
    ],
    chart: () => const NeuralNetDiagram(),
  ),
  ScienceTopic(
    id: 'statistics',
    short: 'st',
    formulas: const [
      Formula('pub_f_normal', r'f(x) = \frac{1}{\sigma\sqrt{2\pi}}\, e^{-\frac{(x-\mu)^2}{2\sigma^2}}'),
      Formula('pub_f_bayes', r'P(A \mid B) = \frac{P(B \mid A)\,P(A)}{P(B)}'),
      Formula('pub_f_kl', r'D_{\mathrm{KL}}(P \,\|\, Q) = \sum_{x} P(x) \log \frac{P(x)}{Q(x)}'),
      Formula('pub_f_brier', r'\mathrm{BS} = \frac{1}{N}\sum_{t=1}^{N} (f_t - o_t)^2'),
    ],
    chart: () => const BellCurve(),
  ),
];

ScienceTopic? scienceTopic(String id) {
  for (final t in scienceContent) {
    if (t.id == id) return t;
  }
  return null;
}
