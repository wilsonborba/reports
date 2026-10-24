import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../themes/report_palette.dart';
import 'chart_parts.dart';
import 'format.dart';
import 'motion.dart';

/// Points sized by value on their latitude and longitude, with optional links
/// (from_lat, from_lon, to_lat, to_lon). On wide cards the top list sits on the
/// right of the map; on narrow cards it sits below the map and scrolls.
/// Hovering a point shows its tooltip and highlights its list row; hovering a row
/// highlights its point. A tap does the same on touch screens. The top 3 points pulse
/// 3 times after the first show (a pulse that never stops costs CPU on every board).
class SpatialMap extends StatefulWidget {
  final DatasetPage points;
  final DatasetPage? links;
  final FieldInfo label;
  final FieldInfo value;
  final FieldInfo? share;
  final int listSize;

  /// Height of the chart area on a board card; null keeps the natural size.
  final double? height;

  /// Largest map height when [height] is null (full view: 80% of the screen).
  final double? maxHeight;

  const SpatialMap(
      {super.key, required this.points, this.links, required this.label, required this.value, this.share, this.listSize = 8, this.height, this.maxHeight});

  /// Number of top points that pulse.
  static const int pulsing = 3;

  /// Largest number of points with a rank badge on the map; the list ranks every row.
  static const int numbered = 10;

  static FieldInfo? _fieldOfType(DatasetDescriptor d, String type, [String? prefix]) {
    for (final f in d.fields) {
      if (f.type == type && (prefix == null || f.name.startsWith(prefix))) return f;
    }
    return null;
  }

  @override
  State<SpatialMap> createState() => _SpatialMapState();
}

class _SpatialMapState extends State<SpatialMap> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  int? _hover;
  Offset? _pointer;
  bool _started = false;

  Future<void> _pulseTimes(int n) async {
    for (var i = 0; i < n && mounted; i++) {
      try {
        await _pulse.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) _pulse.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_started) {
      _started = true;
      _pulseTimes(3);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _setHover(int? i, [Offset? at]) {
    if (i == _hover && at == _pointer) return;
    setState(() {
      _hover = i;
      _pointer = at;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = widget;
    final lat = SpatialMap._fieldOfType(w.points.descriptor, 'latitude')!;
    final lon = SpatialMap._fieldOfType(w.points.descriptor, 'longitude')!;
    final rows = w.points.rows.where((r) => asDouble(r[lat.name]) != null && asDouble(r[lon.name]) != null).toList();
    final top = rows.take(w.listSize).toList();
    final hover = _hover;

    Widget tooltip(int i, Size size, _Projection proj) {
      final r = rows[i];
      final at = proj.point(r);
      const width = 190.0;
      final left = (at.dx + 14).clamp(4.0, math.max(4.0, size.width - width - 4)).toDouble();
      final above = at.dy > 70;
      return Positioned(
        left: left,
        top: above ? null : at.dy + 14,
        bottom: above ? size.height - at.dy + 14 : null,
        child: IgnorePointer(
          child: Container(
            key: const Key('map_tooltip'),
            constraints: const BoxConstraints(maxWidth: width),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.textPrimary, borderRadius: BorderRadius.circular(ReportPalette.controlRadius)),
            child: Text.rich(
              TextSpan(style: ChartTooltip.base(p), children: [
                TextSpan(text: '${valueText(r[w.label.name], w.label)}\n', style: const TextStyle(fontWeight: FontWeight.w700)),
                ...ChartTooltip.row(p, valueWithUnit(r[w.value.name], w.value), w.value.label),
                if (w.share != null) ...[const TextSpan(text: '\n'), ...ChartTooltip.row(p, valueText(r[w.share!.name], w.share), w.share!.label)],
              ]),
            ),
          ),
        ),
      );
    }

    Widget mapBox(double? h) => _box(
          h,
          Container(
            decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius), border: Border.all(color: p.border)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ReportPalette.surfaceRadius),
              child: LayoutBuilder(builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                final proj = _Projection.fit(rows, w.links, lat, lon, size);
                int? hit(Offset at) => proj.hit(at, rows, w.value);
                return MouseRegion(
                  key: const Key('map_area'),
                  onHover: (e) => _setHover(hit(e.localPosition), e.localPosition),
                  onExit: (_) => _setHover(null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (e) {
                      final i = hit(e.localPosition);
                      _setHover(i == _hover ? null : i, e.localPosition);
                    },
                    child: Stack(children: [
                      Positioned.fill(
                        child: EntryAnimation(
                          duration: const Duration(milliseconds: 600),
                          builder: (context, t) => CustomPaint(
                            painter: _MapPainter(
                              rows: rows,
                              links: w.links,
                              lat: lat,
                              lon: lon,
                              value: w.value,
                              palette: p,
                              highlight: math.min(top.length, SpatialMap.numbered),
                              hover: hover,
                              grow: t,
                              pulse: _pulse,
                              projection: proj,
                            ),
                          ),
                        ),
                      ),
                      if (hover != null && hover < rows.length) tooltip(hover, size, proj),
                    ]),
                  ),
                );
              }),
            ),
          ),
        );

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < top.length; i++)
        MouseRegion(
          key: Key('map_row_$i'),
          onEnter: (_) => _setHover(i),
          onExit: (_) => _setHover(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setHover(_hover == i ? null : i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                color: hover == i ? p.surfaceAlt : Colors.transparent,
                border: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.6))),
              ),
              child: Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                  child: Text('${i + 1}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.onAccent)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(valueText(top[i][w.label.name], w.label),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.textPrimary)),
                    Text(
                      [valueWithUnit(top[i][w.value.name], w.value), if (w.share != null) valueText(top[i][w.share!.name], w.share)].join('  '),
                      style: TextStyle(fontSize: 11.5, color: p.textMuted),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
    ]);
    return LayoutBuilder(builder: (context, c) {
      // Full view: the natural 1.25 shape, but never taller than maxHeight.
      double? capped(double mapWidth) => w.maxHeight == null ? null : math.min(mapWidth / 1.25, w.maxHeight!);
      final wide = c.maxWidth >= 760;
      final h = w.height ?? capped(wide ? (c.maxWidth - 16) * 3 / 5 : c.maxWidth);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: mapBox(h)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: h == null ? list : SizedBox(height: h, child: SingleChildScrollView(child: list))),
        ]);
      }
      // Narrow card: the map on top, the list below; on a board card both share the height.
      final mapH = w.height == null ? h : w.height! * 0.62;
      final listH = w.height == null ? (w.maxHeight == null ? 240.0 : w.maxHeight! * 0.5) : (w.height! - mapH! - 12).clamp(60.0, 4000.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        mapBox(mapH),
        const SizedBox(height: 12),
        SizedBox(height: listH, child: SingleChildScrollView(child: list)),
      ]);
    });
  }

  /// The map keeps its 1.25 shape without a height, and fills the height on a board card.
  Widget _box(double? h, Widget child) => h == null ? AspectRatio(aspectRatio: 1.25, child: child) : SizedBox(height: h, child: child);
}

/// Equirectangular projection with the latitude correction, fitted into a canvas.
class _Projection {
  final FieldInfo lat;
  final FieldInfo lon;
  final double minX, maxY, kx, scale, offX, offY;

  const _Projection(this.lat, this.lon, this.minX, this.maxY, this.kx, this.scale, this.offX, this.offY);

  static _Projection fit(List<Map<String, dynamic>> rows, DatasetPage? links, FieldInfo lat, FieldInfo lon, Size size) {
    final coords = <Offset>[
      for (final r in rows) Offset(asDouble(r[lon.name])!, asDouble(r[lat.name])!),
      for (final l in links?.rows ?? const <Map<String, dynamic>>[])
        if (asDouble(l['from_lon']) != null && asDouble(l['from_lat']) != null) Offset(asDouble(l['from_lon'])!, asDouble(l['from_lat'])!),
    ];
    if (coords.isEmpty || size.isEmpty) return _Projection(lat, lon, 0, 0, 1, 1, 0, 0);
    var minX = coords.map((o) => o.dx).reduce(math.min), maxX = coords.map((o) => o.dx).reduce(math.max);
    var minY = coords.map((o) => o.dy).reduce(math.min), maxY = coords.map((o) => o.dy).reduce(math.max);
    final padX = (maxX - minX).abs() * 0.08 + 1e-4, padY = (maxY - minY).abs() * 0.08 + 1e-4;
    minX -= padX;
    maxX += padX;
    minY -= padY;
    maxY += padY;
    final kx = math.cos((minY + maxY) / 2 * math.pi / 180);
    final spanX = (maxX - minX) * kx, spanY = maxY - minY;
    final scale = math.min(size.width / spanX, size.height / spanY);
    return _Projection(lat, lon, minX, maxY, kx, scale, (size.width - spanX * scale) / 2, (size.height - spanY * scale) / 2);
  }

  Offset project(double lonV, double latV) => Offset(offX + (lonV - minX) * kx * scale, offY + (maxY - latV) * scale);

  Offset point(Map<String, dynamic> r) => project(asDouble(r[lon.name])!, asDouble(r[lat.name])!);

  static double radius(double v, double maxV) => 4 + 18 * math.sqrt(maxV <= 0 ? 0 : (v / maxV).clamp(0.0, 1.0));

  /// Index of the point under [at]: the nearest center inside its circle (at least 10 px).
  int? hit(Offset at, List<Map<String, dynamic>> rows, FieldInfo value) {
    final maxV = rows.map((r) => asDouble(r[value.name]) ?? 0).fold<double>(0, math.max);
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < rows.length; i++) {
      final d = (point(rows[i]) - at).distance;
      final reach = math.max(10.0, radius(asDouble(rows[i][value.name]) ?? 0, maxV));
      if (d <= reach && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }
}

class _MapPainter extends CustomPainter {
  final List<Map<String, dynamic>> rows;
  final DatasetPage? links;
  final FieldInfo lat;
  final FieldInfo lon;
  final FieldInfo value;
  final ReportPalette palette;
  final int highlight;
  final int? hover;
  final double grow;
  final Animation<double> pulse;
  final _Projection projection;

  _MapPainter({
    required this.rows,
    required this.links,
    required this.lat,
    required this.lon,
    required this.value,
    required this.palette,
    required this.highlight,
    required this.hover,
    required this.grow,
    required this.pulse,
    required this.projection,
  }) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final proj = projection;
    final linkPaint = Paint()
      ..color = palette.textMuted.withValues(alpha: 0.35 * grow)
      ..strokeWidth = 1;
    for (final l in links?.rows ?? const <Map<String, dynamic>>[]) {
      final a = [l['from_lon'], l['from_lat'], l['to_lon'], l['to_lat']].map(asDouble).toList();
      if (a.any((v) => v == null)) continue;
      canvas.drawLine(proj.project(a[0]!, a[1]!), proj.project(a[2]!, a[3]!), linkPaint);
    }
    final maxV = rows.map((r) => asDouble(r[value.name]) ?? 0).fold<double>(0, math.max);
    final anyHover = hover != null;
    for (var i = rows.length - 1; i >= 0; i--) {
      final r = rows[i];
      final c = proj.point(r);
      final radius = _Projection.radius(asDouble(r[value.name]) ?? 0, maxV) * staggered(grow, i.clamp(0, 40), 41, each: 400, stagger: 5);
      final isTop = i < highlight;
      final base = isTop ? palette.accent : palette.seriesAt(0);
      final alpha = dimmed(anyHover, hover == i);
      // Top points pulse with a ring that grows and fades over 2 seconds.
      if (i < SpatialMap.pulsing && pulse.value > 0) {
        final t = pulse.value;
        canvas.drawCircle(
            c,
            radius + 4 + 12 * t,
            Paint()
              ..color = palette.accent.withValues(alpha: 0.45 * (1 - t) * alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      canvas.drawCircle(c, radius, Paint()..color = base.withValues(alpha: (isTop ? 0.30 : 0.16) * alpha));
      canvas.drawCircle(
          c,
          radius,
          Paint()
            ..color = base.withValues(alpha: (isTop ? 1.0 : 0.55) * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hover == i ? 2.4 : 1.4);
      if (hover == i) {
        canvas.drawCircle(
            c,
            radius + 3,
            Paint()
              ..color = palette.textPrimary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
      if (isTop) {
        canvas.drawCircle(c, 8, Paint()..color = palette.accent.withValues(alpha: alpha));
        final tp = TextPainter(
          text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: palette.onAccent.withValues(alpha: alpha))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.rows != rows || old.links != links || old.palette != palette || old.hover != hover || old.grow != grow || old.projection != projection;
}
