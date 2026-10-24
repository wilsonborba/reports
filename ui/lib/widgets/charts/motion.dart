import 'package:flutter/material.dart';

/// True when the system asks for less motion: charts then show their final state at once.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Plays an entry animation once (0 to 1) and gives the progress to [builder].
/// With reduced motion the progress is 1 from the first frame.
class EntryAnimation extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;

  const EntryAnimation({super.key, required this.duration, required this.builder, this.curve = Curves.easeOutCubic});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return builder(context, 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// Progress of item [i] of [count] when the items start [stagger] apart inside a total
/// run of [total] (all values in milliseconds); [t] is the progress of the whole run.
double staggered(double t, int i, int count, {double each = 500, double stagger = 25}) {
  final total = each + stagger * (count - 1).clamp(0, 1 << 20);
  final start = stagger * i / total;
  final span = each / total;
  return ((t - start) / span).clamp(0.0, 1.0);
}

/// Opacity of a mark: full when nothing is highlighted or when it is the highlighted one.
double dimmed(bool anyHighlight, bool isHighlighted) => !anyHighlight || isHighlighted ? 1 : 0.4;
