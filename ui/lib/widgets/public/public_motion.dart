import 'package:flutter/material.dart';
import '../charts/motion.dart';
import 'public_layout.dart';

/// Plays an animation once (0 to 1) when the widget first comes into the visible part of
/// the page, and gives the progress to [builder]. The run starts after [delay].
/// With reduced motion the progress is 1 at once; with [staticOnPhone] phones also get 1.
/// Every run is finite: the pages never animate without end.
class PlayWhenVisible extends StatefulWidget {
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final bool staticOnPhone;
  final Widget Function(BuildContext context, double t) builder;

  const PlayWhenVisible({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 700),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
    this.staticOnPhone = false,
  });

  @override
  State<PlayWhenVisible> createState() => _PlayWhenVisibleState();
}

class _PlayWhenVisibleState extends State<PlayWhenVisible> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration + widget.delay);
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds / (widget.duration + widget.delay).inMilliseconds.clamp(1, 1 << 30),
      1,
      curve: widget.curve,
    ),
  );
  ScrollPosition? _position;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    if (reduceMotion(context) || (widget.staticOnPhone && PublicLayout.isPhone(context))) {
      _started = true;
      _controller.value = 1;
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_check);
      _position = position?..addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screen = MediaQuery.sizeOf(context).height;
    if (top < screen * 0.95 && bottom > 0) {
      _started = true;
      _position?.removeListener(_check);
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _progress, builder: (context, _) => widget.builder(context, _progress.value));
}

/// Fades a block in and moves it up a little when it first comes into view.
class Reveal extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) => PlayWhenVisible(
        delay: delay,
        duration: const Duration(milliseconds: 600),
        builder: (context, t) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
        ),
      );
}
