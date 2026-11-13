/// Allocation-free interpolation into caller-owned Float64List buffers.
///
/// P(t) = c(t) + sigma^t R(t theta) [(1-m) aC + m bT]. The global
/// hybrid carries the centroid around its shared global center; half-flight
/// holes clamp only m while continuing to ride that frame for the whole flight.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'plan.dart';

/// Allocate once when a plan changes, not once per output frame.
List<Float64List> allocOutputs(MorphPlan plan) => List<Float64List>.generate(
    plan.items.length, (_) => Float64List(2 * plan.n));

/// Natural-space interpolation, including spring extrapolation outside [0,1].
void interpPolar(MorphPlan plan, double t, List<Float64List> out) {
  if (!t.isFinite) {
    throw ArgumentError.value(t, 't', 'Progress must be finite');
  }
  for (var k = 0; k < plan.items.length; k++) {
    final it = plan.items[k];
    final o = out[k];
    final n = plan.n;
    final s = math.exp(it.lnSigma * t);
    final ang = it.theta * t;
    final cos = math.cos(ang) * s;
    final sin = math.sin(ang) * s;
    final block = it.block;
    double cx;
    double cy;
    if (block != null) {
      final ox = block.off[0];
      final oy = block.off[1];
      final dx = block.drift[0];
      final dy = block.drift[1];
      cx = it.ca[0] + dx * t + (ox * cos - oy * sin - ox);
      cy = it.ca[1] + dy * t + (ox * sin + oy * cos - oy);
    } else {
      cx = it.ca[0] + (it.cb[0] - it.ca[0]) * t;
      cy = it.ca[1] + (it.cb[1] - it.ca[1]) * t;
    }
    final half = it.half;
    final m = half == null ? t : math.min(1.0, math.max(0.0, 2 * t - half));
    for (var i = 0; i < n; i++) {
      final px = it.aC[2 * i] + (it.bT[2 * i] - it.aC[2 * i]) * m;
      final py = it.aC[2 * i + 1] + (it.bT[2 * i + 1] - it.aC[2 * i + 1]) * m;
      o[2 * i] = cx + px * cos - py * sin;
      o[2 * i + 1] = cy + px * sin + py * cos;
    }
  }
}

/// Raw coordinate lerp with the same correspondence, for comparison.
void interpLinear(MorphPlan plan, double t, List<Float64List> out) {
  if (!t.isFinite) {
    throw ArgumentError.value(t, 't', 'Progress must be finite');
  }
  for (var k = 0; k < plan.items.length; k++) {
    final it = plan.items[k];
    final o = out[k];
    for (var i = 0; i < plan.n; i++) {
      o[2 * i] = it.a[2 * i] + (it.bO[2 * i] - it.a[2 * i]) * t;
      o[2 * i + 1] = it.a[2 * i + 1] + (it.bO[2 * i + 1] - it.a[2 * i + 1]) * t;
    }
  }
}
