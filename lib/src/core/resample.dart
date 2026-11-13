import 'dart:math' as math;
import 'dart:typed_data';

import 'normalize.dart';
import 'types.dart';

/// Angular discontinuity required for a segment joint to count as a corner.
const double CORNER_THRESHOLD = math.pi / 8;

// Symmetric half of the eight-point Gauss-Legendre rule on [-1, 1].
const _gx = [
  0.18343464249564978,
  0.525532409916329,
  0.7966664774136267,
  0.9602898564975363
];
const _gw = [
  0.362683783378362,
  0.31370664587788727,
  0.22238103445337448,
  0.10122853629037626
];

int _validatePath(CubicPath path) {
  final m = segCount(path);
  if (path.pts.any((v) => !v.isFinite)) {
    throw ArgumentError('morphicons: expected finite cubic coordinates');
  }
  return m;
}

void _validateThreshold(double threshold) {
  if (!threshold.isFinite || threshold < 0) {
    throw ArgumentError.value(threshold, 'threshold',
        'morphicons: expected nonnegative finite threshold');
  }
}

double _speed(Float64List p, int k, double t) {
  final i = 6 * k;
  final u = 1 - t;
  final c0 = 3 * u * u;
  final c1 = 6 * u * t;
  final c2 = 3 * t * t;
  final dx = c0 * (p[i + 2] - p[i]) +
      c1 * (p[i + 4] - p[i + 2]) +
      c2 * (p[i + 6] - p[i + 4]);
  final dy = c0 * (p[i + 3] - p[i + 1]) +
      c1 * (p[i + 5] - p[i + 3]) +
      c2 * (p[i + 7] - p[i + 5]);
  return math.sqrt(dx * dx + dy * dy);
}

double _segLen(Float64List p, int k, [double t1 = 1]) {
  final half = t1 / 2;
  var sum = 0.0;
  for (var j = 0; j < 4; j++) {
    sum += _gw[j] *
        (_speed(p, k, half + half * _gx[j]) +
            _speed(p, k, half - half * _gx[j]));
  }
  final length = sum * half;
  if (!length.isFinite) {
    throw ArgumentError('morphicons: non-finite cubic arc length');
  }
  return length;
}

void _point(Float64List p, int k, double t, Float64List out, int o) {
  final i = 6 * k;
  final u = 1 - t;
  final b0 = u * u * u;
  final b1 = 3 * u * u * t;
  final b2 = 3 * u * t * t;
  final b3 = t * t * t;
  out[o] = b0 * p[i] + b1 * p[i + 2] + b2 * p[i + 4] + b3 * p[i + 6];
  out[o + 1] = b0 * p[i + 1] + b1 * p[i + 3] + b2 * p[i + 5] + b3 * p[i + 7];
}

(double, double)? _tangent(Float64List p, int k, bool atEnd) {
  final i = 6 * k;
  final base = atEnd ? i + 6 : i;
  final sign = atEnd ? -1 : 1;
  for (final j in atEnd ? const [4, 2, 0] : const [2, 4, 6]) {
    final dx = sign * (p[i + j] - p[base]);
    final dy = sign * (p[i + j + 1] - p[base + 1]);
    if (dx * dx + dy * dy > 1e-18) return (dx, dy);
  }
  return null;
}

/// Segment boundaries with a tangent discontinuity, ignoring zero-length cubics.
/// Closed paths include the closing joint when that joint is a corner.
List<int> detectCorners(CubicPath path, [double threshold = CORNER_THRESHOLD]) {
  final m = _validatePath(path);
  _validateThreshold(threshold);
  final p = path.pts;
  final active = <int>[];
  for (var k = 0; k < m; k++) {
    if (_segLen(p, k) > 1e-9) active.add(k);
  }
  if (active.isEmpty) return [];
  final corners = <int>{};
  void test(int a, int b) {
    final u = _tangent(p, a, true);
    final v = _tangent(p, b, false);
    if (u == null || v == null) return;
    final angle =
        math.atan2(u.$1 * v.$2 - u.$2 * v.$1, u.$1 * v.$1 + u.$2 * v.$2).abs();
    if (angle > threshold) corners.add(b);
  }

  for (var j = 0; j + 1 < active.length; j++) {
    test(active[j], active[j + 1]);
  }
  if (path.closed && active.length > 1) test(active.last, active.first);
  return corners.toList()..sort();
}

/// Sum of per-cubic lengths computed with GL8 quadrature.
double arcLength(CubicPath path) {
  final m = _validatePath(path);
  var length = 0.0;
  for (var k = 0; k < m; k++) {
    length += _segLen(path.pts, k);
  }
  if (!length.isFinite) {
    throw ArgumentError('morphicons: non-finite path arc length');
  }
  return length;
}

// Safeguarded Newton inversion with a bisection bracket and exact speed.
double _invert(Float64List p, int k, double s, double length) {
  if (s <= 0) return 0;
  if (s >= length) return 1;
  var lo = 0.0;
  var hi = 1.0;
  var t = s / length;
  for (var iteration = 0; iteration < 12; iteration++) {
    final f = _segLen(p, k, t) - s;
    if (f.abs() < 1e-10 * length + 1e-14) break;
    if (f > 0) {
      hi = t;
    } else {
      lo = t;
    }
    final speed = _speed(p, k, t);
    var next = speed > 1e-12 ? t - f / speed : (lo + hi) / 2;
    if (!(next > lo && next < hi)) next = (lo + hi) / 2;
    t = next;
  }
  return t;
}

/// Samples [n] points by arc length, pinning all corners bit-exactly.
///
/// Open paths include both endpoints. Closed paths distribute [n] intervals
/// around the loop with no duplicate endpoint; only corners, not an arbitrary
/// moveto point, anchor the sampling. The planner resolves circular indexing.
Float64List resamplePath(CubicPath path,
    [int n = 64, double cornerThreshold = math.pi / 8]) {
  if (n < 2) {
    throw ArgumentError.value(
        n, 'n', 'morphicons: expected at least 2 samples');
  }
  final m = _validatePath(path);
  _validateThreshold(cornerThreshold);
  final p = path.pts;
  final out = Float64List(2 * n);
  Float64List fill() {
    for (var i = 0; i < n; i++) {
      out[2 * i] = p[0];
      out[2 * i + 1] = p[1];
    }
    return out;
  }

  if (m < 1) return fill();
  final lengths = List<double>.filled(m, 0);
  var length = 0.0;
  for (var k = 0; k < m; k++) {
    lengths[k] = _segLen(p, k);
    length += lengths[k];
  }
  if (!length.isFinite) {
    throw ArgumentError('morphicons: non-finite path arc length');
  }
  if (length < 1e-12) return fill();

  final corners = detectCorners(path, cornerThreshold);
  final List<int> anchors;
  if (path.closed) {
    anchors = corners.isNotEmpty ? corners : [0];
  } else {
    anchors = {0, ...corners, m}.toList()..sort();
  }
  final runs = <(int, int)>[];
  if (path.closed) {
    for (var j = 0; j < anchors.length; j++) {
      runs.add((
        anchors[j],
        j + 1 < anchors.length ? anchors[j + 1] : anchors[0] + m
      ));
    }
  } else {
    for (var j = 0; j + 1 < anchors.length; j++) {
      runs.add((anchors[j], anchors[j + 1]));
    }
  }
  final runLengths = <double>[];
  for (final run in runs) {
    var sum = 0.0;
    for (var k = run.$1; k < run.$2; k++) {
      sum += lengths[k % m];
    }
    runLengths.add(sum);
  }
  final intervals = path.closed ? n : n - 1;
  if (runs.length > intervals) {
    throw ArgumentError('morphicons: N=$n too small (${runs.length} runs)');
  }

  // Largest-remainder allocation with min-one intervals and deterministic ties.
  final sum = runLengths.fold(0.0, (a, b) => a + b);
  final total = sum == 0 ? 1 : sum;
  final ideal = runLengths.map((v) => intervals * v / total).toList();
  final counts = ideal.map((v) => math.max(1, v.floor())).toList();
  var remaining = intervals - counts.fold(0, (a, b) => a + b);
  if (remaining > 0) {
    final order = [
      for (var i = 0; i < ideal.length; i++)
        (((ideal[i] - ideal[i].floor()) * 1e9).round(), i),
    ]..sort((a, b) {
        final fractional = b.$1.compareTo(a.$1);
        return fractional != 0 ? fractional : a.$2.compareTo(b.$2);
      });
    for (var j = 0; j < remaining; j++) {
      counts[order[j % counts.length].$2]++;
    }
  }
  while (remaining < 0) {
    var biggest = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[biggest]) biggest = i;
    }
    if (counts[biggest] <= 1) break;
    counts[biggest]--;
    remaining++;
  }

  var written = 0;
  for (var r = 0; r < runs.length; r++) {
    final (k0, k1) = runs[r];
    final count = counts[r];
    final runLength = runLengths[r];
    final vi = 6 * (k0 % m);
    out[2 * written] = p[vi];
    out[2 * written + 1] = p[vi + 1];
    written++;
    var seg = k0;
    var accumulated = 0.0;
    for (var j = 1; j < count; j++) {
      final target = runLength * j / count;
      while (seg < k1 - 1 && accumulated + lengths[seg % m] < target) {
        accumulated += lengths[seg % m];
        seg++;
      }
      final k = seg % m;
      final segmentLength = lengths[k];
      final t = segmentLength > 1e-12
          ? _invert(p, k, target - accumulated, segmentLength)
          : 0.0;
      _point(p, k, t, out, 2 * written);
      written++;
    }
  }
  if (!path.closed) {
    out[2 * written] = p[6 * m];
    out[2 * written + 1] = p[6 * m + 1];
  }
  return out;
}

/// Complete input pipeline preserving each subpath's open/closed topology.
List<Sampled> resampleIcon(IconInput input, [int n = 64]) {
  if (n < 2) {
    throw ArgumentError.value(
        n, 'n', 'morphicons: expected at least 2 samples');
  }
  return [
    for (final path in iconToCubics(input))
      Sampled(resamplePath(path, n), closed: path.closed),
  ];
}
