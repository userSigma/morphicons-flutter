import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/region.dart';
import '../core/spring.dart';
import '../core/types.dart';
import 'morph_controller.dart';

/// A dependency-free native Flutter morphing icon on a 24×24 logical grid.
///
/// Use [icon] for implicit animation, [from]/[to]/[progress] for deterministic
/// scrubbing, or [controller] for imperative animation. A complete controlled
/// pair takes precedence over [icon]. The external controller stays caller-owned.
class MorphIcon extends StatefulWidget {
  const MorphIcon({
    super.key,
    this.icon,
    this.from,
    this.to,
    this.progress = 0,
    this.controller,
    this.size = 24,
    this.color,
    this.strokeWidth = 2,
    this.absoluteStrokeWidth = false,
    this.spring,
    this.reducedMotion = ReducedMotion.never,
    this.label,
  })  : assert(size > 0),
        assert(strokeWidth > 0),
        assert(progress >= 0 && progress <= 1);

  final IconInput? icon;
  final IconInput? from;
  final IconInput? to;
  final double progress;
  final MorphController? controller;
  final double size;
  final Color? color;
  final double strokeWidth;
  final bool absoluteStrokeWidth;
  final SpringConfig? spring;
  final ReducedMotion reducedMotion;
  final String? label;

  @override
  State<MorphIcon> createState() => _MorphIconState();
}

class _MorphIconState extends State<MorphIcon>
    with SingleTickerProviderStateMixin {
  late MorphController _controller;
  late final Ticker _ticker;
  bool _ownsController = false;
  bool _wasControlled = false;
  bool _tickerEnabled = true;
  bool _initialized = false;
  Duration? _lastElapsed;
  IconInput? _lastIcon;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _attach();
  }

  void _attach() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? MorphController();
    _controller.addListener(_onChange);
    _wasControlled = false;
    _lastIcon = null;
  }

  void _detach() {
    _ticker.stop();
    _lastElapsed = null;
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep compatibility with Flutter 3.19 (valuesOf arrived in 3.35).
    // ignore: deprecated_member_use
    _tickerEnabled = TickerMode.of(context);
    _sync();
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant MorphIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach();
      _attach();
    }
    if (_initialized) _sync();
  }

  void _sync() {
    _controller.configure(
      spring: widget.spring,
      strokeWidth: widget.strokeWidth /
          (widget.absoluteStrokeWidth ? widget.size / 24 : 1),
      reducedMotion: widget.reducedMotion,
      userReducedMotion:
          MediaQuery.maybeOf(context)?.disableAnimations ?? false,
    );
    final controlled = widget.from != null && widget.to != null;
    if (controlled) {
      _controller.seek(widget.to!, widget.progress, from: widget.from);
    } else {
      if (_wasControlled) _controller.clearControlledPair();
      if (widget.icon != null && (_wasControlled || _lastIcon != widget.icon)) {
        _controller.morphTo(widget.icon!);
      }
    }
    _lastIcon = widget.icon;
    _wasControlled = controlled;
    _onChange();
  }

  void _onChange() {
    final shouldTick = _controller.isAnimating && _tickerEnabled;
    if (shouldTick && !_ticker.isActive) {
      _lastElapsed = null;
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
      _lastElapsed = null;
    }
  }

  void _tick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous != null) _controller.advance(elapsed - previous);
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = widget.color ?? theme.color ?? const Color(0xFF000000);
    final opacity = theme.opacity ?? 1;
    final icon = RepaintBoundary(
        child: CustomPaint(
      size: Size.square(widget.size),
      painter: _MorphPainter(
          _controller,
          opacity == 1
              ? color
              :
              // alpha is used instead of a to retain Flutter 3.19 compatibility.
              // ignore: deprecated_member_use
              color.withAlpha((color.alpha * opacity).round()),
          widget.absoluteStrokeWidth),
    ));
    return widget.label == null
        ? ExcludeSemantics(child: icon)
        : Semantics(
            label: widget.label,
            image: true,
            child: ExcludeSemantics(child: icon));
  }

  @override
  void dispose() {
    _detach();
    _ticker.dispose();
    super.dispose();
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.controller, this.color, this.absoluteStrokeWidth)
      : super(repaint: controller);
  final MorphController controller;
  final Color color;
  final bool absoluteStrokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    if (scale <= 0 || controller.isDisposed) return;
    final path = Path();
    final curves = controller.cubics;
    if (curves != null) {
      for (final curve in curves) {
        final p = curve.pts;
        if (p.length < 2) continue;
        path.moveTo(p[0], p[1]);
        for (var i = 2; i + 5 < p.length; i += 6) {
          path.cubicTo(p[i], p[i + 1], p[i + 2], p[i + 3], p[i + 4], p[i + 5]);
        }
        if (curve.closed) path.close();
      }
    } else {
      for (final contour in controller.contours ?? const <Sampled>[]) {
        final p = contour.pts;
        if (p.length < 2) continue;
        path.moveTo(p[0], p[1]);
        for (var i = 2; i + 1 < p.length; i += 2) {
          path.lineTo(p[i], p[i + 1]);
        }
        if (contour.closed) path.close();
      }
    }
    canvas.save();
    canvas.translate(
        (size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2);
    canvas.scale(scale);
    canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..color = color
          ..style = controller.paint == IconPaint.fill
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = controller.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MorphPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.color != color ||
      oldDelegate.absoluteStrokeWidth != absoluteStrokeWidth;
}
