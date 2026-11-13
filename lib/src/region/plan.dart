// Filled contours retain winding and nesting throughout the polar flight.
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/normalize.dart';
import '../core/plan.dart';
import '../core/region.dart';
import '../core/resample.dart';
import '../core/types.dart';

const _thresholds = [math.pi / 4, math.pi / 3, math.pi / 2, math.pi];
const _fine = .3;
const _regionLambda = .3;
const _foldSlack = .1;
const _foldTries = 16;
const _skip = 1e6;
const _holeIou = .25;

bool _coarse(Float64List path, Float64List s) {
  final n = s.length ~/ 2;
  var j = 0;
  for (var v = 0; v < path.length; v += 6) {
    for (var k = 0;; k++) {
      if (k == n) return true;
      final a = (j + k) % n, b = (a + 1) % n;
      if (distSeg(path[v], path[v + 1], s[2 * a], s[2 * a + 1], s[2 * b],
              s[2 * b + 1]) <=
          _fine) {
        j = a;
        break;
      }
    }
  }
  return false;
}

/// Samples normalized regions at 64 points, or at 128 when needed for fidelity.
/// Explicit [n] fixes the sample count. All contours are closed and winding
/// determines their hole status; dense curves do not become anchored corners.
List<Sampled> resampleRegion(IconInput icon, [int? n]) {
  final paths = iconToCubics(icon);
  List<Sampled> at(int count) => paths.map((path) {
        Float64List? pts;
        for (final threshold in _thresholds) {
          try {
            pts = resamplePath(
                CubicPath(path.pts, closed: true), count, threshold);
            break;
          } on ArgumentError {
            // More corners than intervals: relax, up to pi (anchors none).
          } on StateError {
            // The resampler can report its corner budget as a state error.
          }
        }
        if (pts == null)
          throw StateError('morphicons: region contour could not be sampled');
        return Sampled(pts, closed: true, hole: signedArea(pts) < 0);
      }).toList();
  final samples = at(n ?? 64);
  if (n != null) return samples;
  for (var k = 0; k < paths.length; k++) {
    if (_coarse(paths[k].pts, samples[k].pts)) return at(128);
  }
  return samples;
}

// Detect a self-intersection in the midpoint residual blend, excluding
// adjacent edges and endpoint contact (same strict crossing as the source).
bool _folds(Float64List a, Float64List b) {
  final l = a.length, p = Float64List(a.length);
  for (var i = 0; i < l; i++) {
    p[i] = (a[i] + b[i]) / 2;
  }
  for (var i = 0; i < l; i += 2) {
    final ax = p[i],
        ay = p[i + 1],
        ux = p[(i + 2) % l] - p[i],
        uy = p[(i + 3) % l] - p[i + 1];
    for (var j = i + 4; j < l - (i != 0 ? 0 : 2); j += 2) {
      final cx = p[j],
          cy = p[j + 1],
          vx = p[(j + 2) % l] - p[j],
          vy = p[(j + 3) % l] - p[j + 1];
      final d1 = ux * (cy - ay) - uy * (cx - ax),
          d2 = ux * (cy + vy - ay) - uy * (cx + vx - ax);
      if (d1 * d2 >= 0) continue;
      final d3 = vx * (ay - cy) - vy * (ax - cx),
          d4 = vx * (ay + uy - cy) - vy * (ax + ux - cx);
      if (d3 * d4 < 0) return true;
    }
  }
  return false;
}

PlanItem _outerItem(Float64List a, Float64List b) {
  final n = a.length ~/ 2, k = n > 64 ? 2 : 1;
  Float64List half(Float64List p, int o) {
    if (k == 1) return p;
    return Float64List.fromList([
      for (var i = 0; i < p.length; i++)
        if ((i >> 1) % 2 == o) p[i],
    ]);
  }

  final source = half(a, 0), ca = centroid(half(a, 0));
  final bs = [half(b, 0), half(b, 1)],
      cbs = [centroid(half(b, 0)), centroid(half(b, 1))];
  final offsets = <(int, double)>[];
  for (var off = 0; off < n; off++) {
    final j = off % k;
    final s = procrustes(source, rotatePts(bs[j], (off - j) ~/ k), ca, cbs[j]);
    offsets.add((off, s.res + _regionLambda * s.theta.abs() / math.pi));
  }
  // Stable source ordering is significant when symmetry produces a tie.
  offsets.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  PlanItem? best;
  for (final candidate in offsets.take(_foldTries)) {
    if (candidate.$2 > offsets.first.$2 + _foldSlack) break;
    final it = makeItem(
        a, rotatePts(b, candidate.$1), false, false, false, _regionLambda);
    it.closed = true;
    best ??= it;
    if (!_folds(half(it.aC, 0), half(it.bT, 0))) return it;
  }
  return best!;
}

// Contour votes identify the containing outer. A hole's centroid can sit
// inside an unrelated island (e.g. camera lens inside its body's window).
int _parentOf(Float64List hole, List<Sampled> subs) {
  final n = hole.length ~/ 2;
  var best = -1, bestArea = double.infinity;
  for (var k = 0; k < subs.length; k++) {
    final s = subs[k];
    if (s.hole) continue;
    var votes = 0;
    for (final v in [0, n ~/ 3, 2 * n ~/ 3]) {
      if (inside(hole[2 * v], hole[2 * v + 1], s.pts)) votes++;
    }
    if (votes < 2) continue;
    final area = signedArea(s.pts).abs();
    if (area < bestArea) {
      bestArea = area;
      best = k;
    }
  }
  return best;
}

class _Frame {
  const _Frame(this.ca, this.cb, this.theta, this.lnSigma, this.block);
  _Frame.of(PlanItem item)
      : this(item.ca, item.cb, item.theta, item.lnSigma, item.block);
  final List<double> ca, cb;
  final double theta, lnSigma;
  final BlockTransport? block;
}

// Row-to-column assignment, optionally surjective. Holed columns have
// capacity one; plain outers can divide. Exhaustive with bounded fallback.
List<int> _assign(
    List<List<double>> costs, List<double> skip, List<bool> one, bool cover) {
  final l = costs.length, s = one.length;
  final f = List<int>.filled(l, -1), mult = List<int>.filled(s, 0);
  if (math.pow(s + 1, l) > SURJ_MAX) {
    final pairs = <(double, int, int)>[];
    for (var i = 0; i < l; i++) {
      for (var j = 0; j < s; j++) {
        if (costs[i][j] < double.infinity) pairs.add((costs[i][j], i, j));
      }
    }
    pairs.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      final row = a.$2.compareTo(b.$2);
      return row != 0 ? row : a.$3.compareTo(b.$3);
    });
    for (final p in pairs) {
      final i = p.$2, j = p.$3;
      if (f[i] < 0 && mult[j] == 0) {
        f[i] = j;
        mult[j] = 1;
      }
    }
    for (var i = 0; i < l; i++) {
      if (f[i] >= 0) continue;
      for (var j = 0; j < s; j++) {
        if (!one[j] && (f[i] < 0 || costs[i][j] < costs[i][f[i]])) f[i] = j;
      }
    }
    return f;
  }
  var best = List<int>.of(f), bc = double.infinity;
  void rec(int i, double acc, int covered) {
    if (acc >= bc || (cover && s - covered > l - i)) return;
    if (i == l) {
      bc = acc;
      best = List<int>.of(f);
      return;
    }
    for (var j = 0; j < s; j++) {
      if ((one[j] && mult[j] != 0) || !(costs[i][j] < double.infinity))
        continue;
      f[i] = j;
      mult[j]++;
      rec(i + 1, acc + costs[i][j], covered + (mult[j] == 1 ? 1 : 0));
      mult[j]--;
    }
    f[i] = -1;
    rec(i + 1, acc + skip[i], covered);
  }

  rec(0, 0, 0);
  return best;
}

List<double> _carry(double x, double y, List<double> from, List<double> to,
    double theta, double s) {
  final c = math.cos(theta) * s,
      n = math.sin(theta) * s,
      dx = x - from[0],
      dy = y - from[1];
  return [to[0] + dx * c - dy * n, to[1] + dx * n + dy * c];
}

Float64List _dots(List<double> c, int n) {
  final d = Float64List(2 * n);
  for (var i = 0; i < 2 * n; i += 2) {
    d[i] = c[0];
    d[i + 1] = c[1];
  }
  return d;
}

// Borrow the outer's similarity (including global block transport). Choose
// only a circular cut; reversing a hole would change its nonzero meaning.
PlanItem _inFrame(Float64List a, Float64List b, _Frame f, bool hole,
    [int? half]) {
  final n = a.length ~/ 2, s = math.exp(f.lnSigma);
  final aC = Float64List(2 * n), bt = Float64List(2 * n);
  var nb = 0.0;
  for (var i = 0; i < 2 * n; i += 2) {
    aC[i] = a[i] - f.ca[0];
    aC[i + 1] = a[i + 1] - f.ca[1];
    final p = _carry(b[i], b[i + 1], f.cb, [0, 0], -f.theta, 1 / s);
    bt[i] = p[0];
    bt[i + 1] = p[1];
    final dx = b[i] - f.cb[0], dy = b[i + 1] - f.cb[1];
    nb += dx * dx + dy * dy;
  }
  var off = 0, be = double.infinity;
  for (var o = 0; o < n && be > 0; o++) {
    var e = 0.0;
    for (var i = 0; i < n && e < be; i++) {
      final j = (i + o) % n,
          dx = aC[2 * i] - bt[2 * j],
          dy = aC[2 * i + 1] - bt[2 * j + 1];
      e += dx * dx + dy * dy;
    }
    if (e < be) {
      be = e;
      off = o;
    }
  }
  return PlanItem(
    a: a,
    aC: aC,
    bT: rotatePts(bt, off),
    bO: rotatePts(b, off),
    ca: f.ca,
    cb: f.cb,
    theta: f.theta,
    lnSigma: f.lnSigma,
    res: nb > 1e-12 ? math.sqrt(s * s * be / nb) : 0,
    closed: true,
    hole: hole,
    half: half,
    block: f.block,
  );
}

// Collapse/grow on separate halves; move the collapse point with a weighted
// estimate of the outer's residual displacement, not merely its similarity.
PlanItem _vanishingHole(Float64List pts, PlanItem outer, bool grow) {
  final s = math.exp(outer.lnSigma), c = centroid(pts);
  var x = c[0], y = c[1], w = 0.0, dx = 0.0, dy = 0.0;
  final aC = outer.aC, bT = outer.bT, near = grow ? outer.bO : outer.a;
  for (var i = 0; i < aC.length; i += 2) {
    final ex = near[i] - x,
        ey = near[i + 1] - y,
        k = 1 / (ex * ex + ey * ey + 1e-9);
    w += k;
    dx += k * (bT[i] - aC[i]);
    dy += k * (bT[i + 1] - aC[i + 1]);
  }
  w = (grow ? -.5 : .5) / w;
  if (grow) {
    final p = _carry(x, y, outer.cb, outer.ca, -outer.theta, 1 / s);
    x = p[0];
    y = p[1];
  }
  x += w * dx;
  y += w * dy;
  final dot = _dots(
      grow ? [x, y] : _carry(x, y, outer.ca, outer.cb, outer.theta, s),
      pts.length ~/ 2);
  return grow
      ? _inFrame(dot, pts, _Frame.of(outer), true, 1)
      : _inFrame(pts, dot, _Frame.of(outer), true, 0);
}

double _weight(PlanItem it, double t) =>
    (2 * t - (it.half ?? t)).clamp(0.0, 1.0);
Float64List _blend(PlanItem it, double t) {
  final m = _weight(it, t);
  return Float64List.fromList([
    for (var i = 0; i < it.aC.length; i++) it.aC[i] + m * (it.bT[i] - it.aC[i]),
  ]);
}

int _strays(PlanItem hole, PlanItem outer, List<PlanItem> holes) {
  var k = 0;
  for (final t in [.25, .5, .75]) {
    if (_weight(hole, t) % 1 == 0) continue;
    final h = _blend(hole, t), o = _blend(outer, t);
    final others = holes
        .where((g) => !identical(g, hole))
        .map((g) => _blend(g, t))
        .toList();
    for (var i = 0; i < h.length; i += 2) {
      if (!inside(h[i], h[i + 1], o) ||
          others.any((p) => inside(h[i], h[i + 1], p))) k++;
    }
  }
  return k;
}

// A disappearing outer and all its holes share exactly one homothety.
List<PlanItem> _vanishingPiece(
    Float64List outer, List<Float64List> holes, bool grow) {
  final c = centroid(outer), dot = _dots(centroid(outer), outer.length ~/ 2);
  final frame = _Frame(c, c, 0, 0, null);
  final ps = [outer, ...holes];
  return [
    for (var k = 0; k < ps.length; k++)
      if (grow)
        _inFrame(dot, ps[k], frame, k > 0)
      else
        _inFrame(ps[k], dot, frame, k > 0),
  ];
}

double _vanishCost(Float64List p) =>
    costMatrix([p], [_dots(centroid(p), p.length ~/ 2)])[0][0];
List<double> _bbox(Float64List p) {
  final b = [p[0], p[1], p[0], p[1]];
  for (var i = 2; i < p.length; i += 2) {
    b[0] = math.min(b[0], p[i]);
    b[1] = math.min(b[1], p[i + 1]);
    b[2] = math.max(b[2], p[i]);
    b[3] = math.max(b[3], p[i + 1]);
  }
  return b;
}

List<List<double>> _holeCosts(
    List<Float64List> ha, List<Float64List> hb, PlanItem outer) {
  final s = math.exp(outer.lnSigma), costs = costMatrix(ha, hb);
  final inA = hb.map((h) {
    final q = Float64List(h.length);
    for (var i = 0; i < h.length; i += 2) {
      final p = _carry(h[i], h[i + 1], outer.cb, outer.ca, -outer.theta, 1 / s);
      q[i] = p[0];
      q[i + 1] = p[1];
    }
    return _bbox(q);
  }).toList();
  for (var i = 0; i < ha.length; i++) {
    final a = _bbox(ha[i]);
    for (var j = 0; j < inA.length; j++) {
      final b = inA[j],
          w = math.min(a[2], b[2]) - math.max(a[0], b[0]),
          v = math.min(a[3], b[3]) - math.max(a[1], b[1]);
      final inter = w > 0 && v > 0 ? w * v : 0.0;
      final union =
          (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter;
      if (!(inter >= _holeIou * union)) costs[i][j] = double.infinity;
    }
  }
  return costs;
}

class _Pieces {
  _Pieces(this.outers, this.holes);
  final List<Float64List> outers;
  final List<List<Float64List>> holes;
}

_Pieces _piecesOf(List<Sampled> subs) {
  final idx = [
    for (var k = 0; k < subs.length; k++)
      if (!subs[k].hole) k
  ];
  final holes = [for (final _ in idx) <Float64List>[]];
  for (final s in subs) {
    if (!s.hole) continue;
    var k = idx.indexOf(_parentOf(s.pts, subs));
    if (k < 0) {
      final h = centroid(s.pts);
      var bd = double.infinity;
      for (var m = 0; m < idx.length; m++) {
        final o = centroid(subs[idx[m]].pts),
            dx = o[0] - h[0],
            dy = o[1] - h[1];
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < bd) {
          bd = d;
          k = m;
        }
      }
    }
    if (k >= 0) holes[k].add(s.pts);
  }
  return _Pieces([for (final k in idx) subs[k].pts], holes);
}

Float64List _doubled(Float64List p) {
  final m = p.length, q = Float64List(2 * p.length);
  for (var i = 0; i < m; i += 2) {
    final j = (i + 2) % m;
    q[2 * i] = p[i];
    q[2 * i + 1] = p[i + 1];
    q[2 * i + 2] = (p[i] + p[j]) / 2;
    q[2 * i + 3] = (p[i + 1] + p[j + 1]) / 2;
  }
  return q;
}

/// Match outers only to outers (holed pieces never duplicate), and holes
/// one-to-one only to overlapping holes of the paired outer. Unmatched pieces
/// and holes collapse/grow while preserving their parent's nesting.
MorphPlan buildRegionPlan(List<Sampled> from, List<Sampled> to) {
  if (from.isEmpty || to.isEmpty)
    throw StateError('morphicons: region has no outer contour');
  final n = math.max(from.first.pts.length, to.first.pts.length) ~/ 2;
  List<Sampled> fit(List<Sampled> s) => s.first.pts.length ~/ 2 < n
      ? s
          .map((c) => Sampled(_doubled(c.pts), closed: c.closed, hole: c.hole))
          .toList()
      : s;
  final a = _piecesOf(fit(from)), b = _piecesOf(fit(to));
  if (a.outers.isEmpty || b.outers.isEmpty)
    throw StateError('morphicons: region has no outer contour');
  final p = a.outers.length, q = b.outers.length;
  final large = p < q ? b : a, small = p < q ? a : b;
  List<List<int>> pairs;
  if (p == q || small.holes.every((h) => h.isEmpty)) {
    pairs = pairUp(a.outers, b.outers);
  } else {
    final f = _assign(
        costMatrix(large.outers, small.outers),
        large.outers.map((o) => _skip + _vanishCost(o)).toList(),
        small.holes.map((h) => h.isNotEmpty).toList(),
        true);
    pairs = [
      for (var l = 0; l < f.length; l++) p < q ? [f[l], l] : [l, f[l]]
    ];
  }
  final items = <PlanItem>[];
  var partial = false;
  for (final pair in pairs) {
    final i = pair[0], j = pair[1];
    if (i < 0 || j < 0) {
      partial = true;
      items.addAll(i < 0
          ? _vanishingPiece(b.outers[j], b.holes[j], true)
          : _vanishingPiece(a.outers[i], a.holes[i], false));
      continue;
    }
    final it = _outerItem(a.outers[i], b.outers[j]);
    it.hole = false;
    items.add(it);
    final ha = a.holes[i], hb = b.holes[j];
    final f = _assign(_holeCosts(ha, hb, it), ha.map((_) => _skip).toList(),
        hb.map((_) => true).toList(), false);
    final holes = [
      for (var k = 0; k < ha.length; k++)
        f[k] < 0
            ? _vanishingHole(ha[k], it, false)
            : _inFrame(ha[k], hb[f[k]], _Frame.of(it), true)
    ];
    for (var k = 0; k < hb.length; k++) {
      if (!f.contains(k)) holes.add(_vanishingHole(hb[k], it, true));
    }
    for (var k = 0; k < holes.length; k++) {
      final h = holes[k];
      if (h.half != null) {
        partial = true;
        continue;
      }
      final c = _strays(h, it, holes);
      if (c == 0) continue;
      holes.replaceRange(k, k + 1,
          [_vanishingHole(h.a, it, false), _vanishingHole(h.bO, it, true)]);
      if (_strays(holes[k], it, holes) + _strays(holes[k + 1], it, holes) >=
          c) {
        holes.replaceRange(k, k + 2, [h]);
      }
    }
    items.addAll(holes);
  }
  if (items.length > 1 && !partial) applyGlobal(items, n);
  return MorphPlan(items: items, n: n);
}
