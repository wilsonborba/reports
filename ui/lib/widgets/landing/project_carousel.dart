import 'package:reports_ui/core/tracking_manifest.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../themes/report_palette.dart';

/// Carousel of project tiles: arrows, arrow keys and swipe (mouse drag too), no autoplay.
/// Desktop shows 2 tiles and a part of the next one; phones show 1 tile.
class ProjectCarousel extends StatefulWidget {
  final int count;
  final Widget Function(BuildContext context, int index, double height)
  itemBuilder;
  final double desktopHeight;
  final double phoneHeight;

  const ProjectCarousel({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.desktopHeight = 650,
    this.phoneHeight = 560,
  });

  /// Width from which 2 tiles show side by side.
  static const double desktopWidth = 900;

  /// Tiles that show at once for a width.
  static int visibleFor(double width) => width >= desktopWidth ? 2 : 1;

  @override
  State<ProjectCarousel> createState() => _ProjectCarouselState();
}

class _ProjectCarouselState extends State<ProjectCarousel> {
  PageController? _controller;
  double? _fraction;
  int _page = 0;
  final _focus = FocusNode(debugLabel: 'carousel');

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  PageController _controllerFor(double fraction) {
    if (_controller == null || _fraction != fraction) {
      _controller?.dispose();
      _fraction = fraction;
      _controller = PageController(
        viewportFraction: fraction,
        initialPage: _page,
      );
    }
    return _controller!;
  }

  void _go(int page, int last) {
    final target = page.clamp(0, last);
    setState(() => _page = target);
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      c.jumpToPage(target);
    } else {
      c.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final visible = ProjectCarousel.visibleFor(c.maxWidth);
        // 2 tiles and a 6% peek on desktop; 1 tile and a small peek on phones.
        final fraction = visible == 2 ? 0.47 : 0.92;
        final controller = _controllerFor(fraction);
        final last = (widget.count - visible).clamp(0, widget.count);
        final height = visible == 2 ? widget.desktopHeight : widget.phoneHeight;
        final page = _page.clamp(0, last);
        Widget arrow(
          Key key,
          IconData icon,
          String tip,
          int to,
          bool enabled,
        ) => track(
          'catalog.carousel.arrow',
          IconButton.outlined(
            key: key,
            tooltip: tip,
            onPressed: enabled ? () => _go(to, last) : null,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ReportPalette.controlRadius,
                ),
              ),
              side: BorderSide(color: p.border),
            ),
            icon: Icon(icon),
          ),
        );
        return Focus(
          focusNode: _focus,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _go(page + 1, last);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _go(page - 1, last);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              track(
                'catalog.carousel.surface',
                GestureDetector(
                  onTapDown: (_) => _focus.requestFocus(),
                  child: SizedBox(
                    key: const Key('carousel'),
                    height: height,
                    child: ScrollConfiguration(
                      // Mouse drag swipes too.
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                      child: PageView.builder(
                        controller: controller,
                        padEnds: false,
                        itemCount: widget.count,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: widget.itemBuilder(context, i, height),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Position marks; a tap goes to that tile.
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < widget.count; i++)
                          Semantics(
                            button: true,
                            label: context.tr('go_to_project', {
                              'n': '${i + 1}',
                            }),
                            child: track(
                              'catalog.carousel.project',
                              GestureDetector(
                                key: Key('carousel_dot_$i'),
                                onTap: () => _go(i, last),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: i >= page && i < page + visible
                                      ? 28
                                      : 12,
                                  height: 4,
                                  color: i >= page && i < page + visible
                                      ? p.accent
                                      : p.border,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  arrow(
                    const Key('carousel_prev'),
                    Icons.chevron_left_rounded,
                    context.tr('previous_project'),
                    page - 1,
                    page > 0,
                  ),
                  const SizedBox(width: 8),
                  arrow(
                    const Key('carousel_next'),
                    Icons.chevron_right_rounded,
                    context.tr('next_project'),
                    page + 1,
                    page < last,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
