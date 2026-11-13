import 'package:flutter/foundation.dart';

import '../core/interpolate.dart';
import '../core/normalize.dart';
import '../core/plan.dart';
import '../core/resample.dart';
import '../core/serialize.dart';
import '../core/spring.dart';
import '../core/types.dart';
import '../region/region.dart';

/// Whether imperative morphs honor the platform's animation preference.
enum ReducedMotion { never, user, always }

class _RestIcon {
  _RestIcon(this.input, this.d, this.cubics, this.paint);
  final IconInput input;
  final String d;
  final List<CubicPath> cubics;
  final IconPaint paint;
}

/// Native, interruptible morph state. A [MorphIcon] drives it with a ticker;
/// non-widget hosts may call [advance] themselves using elapsed frame time.
///
/// Inputs are SVG path strings or `List<IconNode>`. Do not mutate node lists
/// after handing them to a controller. Caller-owned controllers must be disposed.
class MorphController extends ChangeNotifier {
  MorphController({
    IconInput? icon,
    SpringConfig? spring,
    double strokeWidth = 2,
    ReducedMotion reducedMotion = ReducedMotion.never,
  }) {
    configure(
        spring: spring, strokeWidth: strokeWidth, reducedMotion: reducedMotion);
    if (icon != null) set(icon);
  }

  final Spring _spring = Spring();
  double _strokeWidth = 2;
  ReducedMotion _reducedMotion = ReducedMotion.never;
  bool _userReducedMotion = false;
  bool _disposed = false;
  bool _animating = false;
  double _progress = 1;
  IconPaint _paint = IconPaint.stroke;
  _RestIcon? _rest;
  _RestIcon? _target;
  _RestIcon? _source;
  String _sourceD = '';
  String? _canonicalD = '';
  List<CubicPath>? _cubics = const [];
  List<Sampled>? _contours;
  MorphPlan? _plan;
  List<Float64List>? _outputs;
  List<Sampled>? _flightContours;
  List<bool>? _closed;
  IconInput? _seekTarget;
  IconInput? _seekFrom;

  String get d => _canonicalD ?? serialize(_outputs!, _closed);
  double get progress => _progress;
  set progress(double value) {
    _checkAlive();
    _checkProgress(value);
    if (_target != null && _plan != null) {
      _animating = false;
      _spring.v = 0;
      _render(value);
      notifyListeners();
    }
  }

  double get velocity => _spring.v;
  bool get isAnimating => _animating;
  bool get isDisposed => _disposed;
  IconPaint get paint => _paint;
  double get strokeWidth => _strokeWidth;
  ReducedMotion get reducedMotion => _reducedMotion;

  /// Exact cubic curves at rest. In flight [contours] holds the live polylines.
  List<CubicPath>? get cubics => _cubics;
  List<Sampled>? get contours => _contours;

  bool get _reduce =>
      _reducedMotion == ReducedMotion.always ||
      (_reducedMotion == ReducedMotion.user && _userReducedMotion);

  void _checkAlive() {
    if (_disposed) throw StateError('MorphController has been disposed');
  }

  static void _checkProgress(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(
          value, 'progress', 'Expected a finite value in [0, 1]');
    }
  }

  /// Update policy before changing an icon so it governs that same transition.
  void configure({
    SpringConfig? spring,
    double? strokeWidth,
    ReducedMotion? reducedMotion,
    bool? userReducedMotion,
  }) {
    _checkAlive();
    if (strokeWidth != null && (!strokeWidth.isFinite || strokeWidth <= 0)) {
      throw ArgumentError.value(
          strokeWidth, 'strokeWidth', 'Expected a positive finite width');
    }
    if (spring != null &&
        (!spring.stiffness.isFinite ||
            spring.stiffness <= 0 ||
            !spring.damping.isFinite ||
            spring.damping < 0)) {
      throw ArgumentError.value(spring, 'spring',
          'Expected positive stiffness and nonnegative damping');
    }
    if (spring != null) _spring.config(spring.stiffness, spring.damping);
    final widthChanged = strokeWidth != null && strokeWidth != _strokeWidth;
    if (strokeWidth != null) _strokeWidth = strokeWidth;
    if (reducedMotion != null) _reducedMotion = reducedMotion;
    if (userReducedMotion != null) _userReducedMotion = userReducedMotion;
    if (_reduce && _animating && _target != null) {
      _snap(_target!);
      notifyListeners();
    } else if (widthChanged && _rest?.paint == IconPaint.fill) {
      final prepared = _prepare(_rest!.input);
      _snap(prepared);
      clearControlledPair();
      notifyListeners();
    } else if (widthChanged) {
      notifyListeners();
    }
  }

  _RestIcon _prepare(IconInput input) {
    final paint = paintOf(input);
    final rendered = paint == IconPaint.fill
        ? toRegion(input, RegionOptions(strokeWidth: _strokeWidth))
        : input;
    final curves = iconToCubics(rendered);
    final canonical = input is String && paint == IconPaint.stroke
        ? input
        : cubicsToPathD(curves);
    return _RestIcon(input, canonical, curves, paint);
  }

  void _snap(_RestIcon icon) {
    _rest = icon;
    _target = icon;
    _canonicalD = icon.d;
    _cubics = icon.cubics;
    _contours = icon.paint == IconPaint.fill ? resampleRegion(icon.d) : null;
    _paint = icon.paint;
    _progress = 1;
    _spring.x = 1;
    _spring.v = 0;
    _animating = false;
  }

  /// Jump immediately, retaining the canonical path at rest.
  void set(IconInput icon) {
    _checkAlive();
    final prepared = _prepare(icon);
    clearControlledPair();
    _plan = null;
    _outputs = null;
    _snap(prepared);
    notifyListeners();
  }

  List<Sampled> _snapshot() {
    final live = _contours;
    if (_cubics == null && live != null) {
      return live
          .map((path) => Sampled(Float64List.fromList(path.pts),
              closed: path.closed, hole: path.hole))
          .toList(growable: false);
    }
    // A newly started flight may still display exact rest cubics even though
    // _rest has been cleared. Sample what is painted, not a nullable input ref.
    if (_paint == IconPaint.fill)
      return resampleRegion(cubicsToPathD(_cubics!));
    return _cubics!
        .map((curve) => Sampled(resamplePath(curve), closed: curve.closed))
        .toList(growable: false);
  }

  MorphPlan _makePlan(_RestIcon target, _RestIcon? source) {
    if (source != null) {
      if (source.paint == IconPaint.fill || target.paint == IconPaint.fill) {
        return regionPlan(source.input, target.input, _strokeWidth);
      }
      return buildPlan(resampleIcon(source.input), resampleIcon(target.input));
    }
    if (_paint == IconPaint.fill || target.paint == IconPaint.fill) {
      final Object shape = _paint == IconPaint.fill ? _snapshot() : d;
      return regionPlanFrom(shape, target.input, _strokeWidth);
    }
    return buildPlan(_snapshot(), resampleIcon(target.input));
  }

  void _begin(_RestIcon target, {_RestIcon? from}) {
    final source = from ?? _rest;
    final sourceD = from?.d ?? d;
    final plan = _makePlan(target, source);
    _source = source;
    _sourceD = sourceD;
    _target = target;
    _plan = plan;
    _outputs = allocOutputs(plan);
    _closed = plan.items.map((item) => item.closed).toList(growable: false);
    _flightContours = List<Sampled>.generate(
        plan.items.length,
        (i) => Sampled(_outputs![i],
            closed: plan.items[i].closed, hole: plan.items[i].hole),
        growable: false);
    // New output buffers are not painted until the first nonzero frame.
    // Preserve the exact serialized snapshot during interruption and dt == 0.
    _canonicalD = sourceD;
    if (from != null) {
      _canonicalD = from.d;
      _cubics = from.cubics;
      _contours = null;
      _paint = from.paint;
    }
    _rest = null;
  }

  /// Animate from the actual visible shape, carrying forward spring velocity.
  /// The first icon is lazy and appears immediately rather than flying from zero.
  void morphTo(IconInput icon) {
    _checkAlive();
    if (_rest?.input == icon && !_animating) return;
    final target = _prepare(icon);
    if (_target == null ||
        _reduce ||
        target.cubics.isEmpty ||
        (_cubics?.isEmpty ?? false)) {
      set(icon);
      return;
    }
    _begin(target);
    clearControlledPair();
    _progress = 0;
    _spring.start();
    _animating = true;
    notifyListeners();
  }

  /// Freeze an exact, deterministic progress without starting a ticker.
  /// [from] pins a controlled pair; without it the first call captures the
  /// current displayed shape and subsequent calls reuse that pair.
  void seek(IconInput icon, double value, {IconInput? from}) {
    _checkAlive();
    _checkProgress(value);
    if (_target == null && from == null) {
      set(icon);
      return;
    }
    if (_seekTarget != icon || _seekFrom != from || _plan == null) {
      final target = _prepare(icon);
      final source = from == null ? null : _prepare(from);
      if (target.cubics.isEmpty || (source?.cubics.isEmpty ?? false)) {
        set(value == 0 && from != null ? from : icon);
        return;
      }
      _begin(target, from: source);
      _seekTarget = icon;
      _seekFrom = from;
    }
    _animating = false;
    _spring.v = 0;
    _render(value);
    notifyListeners();
  }

  /// Invalidate the controlled pair on every exit, including an iconless exit.
  void clearControlledPair() {
    _seekTarget = null;
    _seekFrom = null;
  }

  void _render(double value) {
    _progress = value;
    _spring.x = value;
    if (value == 1) {
      _snap(_target!);
      return;
    }
    if (value == 0 && _source != null) {
      _rest = _source;
      _canonicalD = _sourceD;
      _cubics = _source!.cubics;
      _paint = _source!.paint;
      _contours = null;
      return;
    }
    interpPolar(_plan!, value, _outputs!);
    _rest = null;
    _canonicalD = value == 0 ? _sourceD : null;
    _cubics = null;
    _paint = _plan!.items.any((item) => item.hole) ||
            _target!.paint == IconPaint.fill ||
            _source?.paint == IconPaint.fill ||
            _paint == IconPaint.fill
        ? IconPaint.fill
        : IconPaint.stroke;
    _contours = _flightContours;
  }

  /// Advance by a frame delta. Zero duration is a strict no-op, including during
  /// an interruption. Long pauses are capped by the spring's integrator.
  void advance(Duration elapsed) {
    _checkAlive();
    if (!_animating || elapsed <= Duration.zero) return;
    final dt = (elapsed.inMicroseconds / Duration.microsecondsPerSecond)
        .clamp(0.0, 0.064);
    if (_spring.step(dt)) {
      _snap(_target!);
    } else {
      _render(_spring.x);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _animating = false;
    _disposed = true;
    _plan = null;
    _outputs = null;
    super.dispose();
  }
}
