/// Correspondence, surjective matching and closed-form 2D Procrustes.
///
/// Closed loops search circular cuts, lines use a minimal-rotation tie-break,
/// and congruent multi-part icons share a similarity and rigid block transport.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'types.dart';

const double _lenWeight = 0.35;
const double _lambda = 0.05;
const double _globalEps = 5e-3;
const int _permMax = 8;

/// Enumeration budget shared with the filled-region planner.
// ignore: constant_identifier_names
const int SURJ_MAX = 100000;

class Similarity {
  const Similarity(
      {required this.theta, required this.sigma, required this.res});

  final double theta;
  final double sigma;
  final double res;
}

class Alignment extends Similarity {
  const Alignment({
    required this.ca,
    required this.cb,
    required this.a,
    required this.b,
    required super.theta,
    required super.sigma,
    required super.res,
  });

  final List<double> ca;
  final List<double> cb;
  final Float64List a;
  final Float64List b;
}

/// A centroid's offset from the global center and its endpoint correction.
class BlockTransport {
  const BlockTransport({required this.off, required this.drift});

  final List<double> off;
  final List<double> drift;
}

class PlanItem {
  PlanItem({
    required this.a,
    required this.aC,
    required this.bT,
    required this.bO,
    required this.ca,
    required this.cb,
    required this.theta,
    required this.lnSigma,
    required this.res,
    required this.closed,
    this.hole = false,
    this.half,
    this.block,
  });

  /// Source points with the chosen correspondence (a loop may change its cut).
  final Float64List a;

  /// Source centered on ca; target brought into the source similarity frame.
  final Float64List aC;
  final Float64List bT;

  /// Oriented raw target, used by linear interpolation and endpoint checks.
  final Float64List bO;
  List<double> ca;
  List<double> cb;
  double theta;
  double lnSigma;
  double res;
  bool closed;
  bool hole;

  /// 0: the residual collapses on [0, 1/2]; 1: grows on [1/2, 1].
  int? half;
  BlockTransport? block;
}

class MorphPlan {
  MorphPlan({required this.items, required this.n});

  final List<PlanItem> items;
  final int n;
}

void _checkCloud(Float64List p, String name) {
  if (p.isEmpty || p.length.isOdd) {
    throw ArgumentError.value(p.length, name, 'Expected nonempty x/y pairs');
  }
  for (var i = 0; i < p.length; i++) {
    if (!p[i].isFinite) {
      throw ArgumentError.value(p[i], name, 'Coordinates must be finite');
    }
  }
}

void _checkPair(Float64List a, Float64List b) {
  _checkCloud(a, 'a');
  _checkCloud(b, 'b');
  if (a.length != b.length) {
    throw ArgumentError(
        'morphicons: point clouds must have equal sample counts');
  }
}

void _checkCenter(List<double> c, String name) {
  if (c.length != 2 || !c[0].isFinite || !c[1].isFinite) {
    throw ArgumentError.value(c, name, 'Expected two finite coordinates');
  }
}

List<double> centroid(Float64List p) {
  _checkCloud(p, 'p');
  final n = p.length ~/ 2;
  var cx = 0.0;
  var cy = 0.0;
  for (var i = 0; i < n; i++) {
    cx += p[2 * i];
    cy += p[2 * i + 1];
  }
  return [cx / n, cy / n];
}

/// Length of the open polyline (no implied closing edge, as in the TS core).
double polyLen(Float64List p) {
  _checkCloud(p, 'p');
  var length = 0.0;
  for (var i = 2; i < p.length; i += 2) {
    length += _hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1]);
  }
  return length;
}

Float64List reversePts(Float64List p) {
  _checkCloud(p, 'p');
  final n = p.length ~/ 2;
  final out = Float64List(p.length);
  for (var i = 0; i < n; i++) {
    out[2 * i] = p[2 * (n - 1 - i)];
    out[2 * i + 1] = p[2 * (n - 1 - i) + 1];
  }
  return out;
}

/// Circular re-indexing: out[i] = p[(i + off) mod n].
Float64List rotatePts(Float64List p, int off) {
  _checkCloud(p, 'p');
  final n = p.length ~/ 2;
  final out = Float64List(p.length);
  for (var i = 0; i < n; i++) {
    final j = (i + off) % n;
    out[2 * i] = p[2 * j];
    out[2 * i + 1] = p[2 * j + 1];
  }
  return out;
}

// A scaled hypot avoids overflowing a finite centroid distance unnecessarily.
double _hypot(double x, double y) {
  x = x.abs();
  y = y.abs();
  final hi = math.max(x, y);
  if (hi == 0 || hi.isInfinite) return hi;
  final lo = math.min(x, y) / hi;
  return hi * math.sqrt(1 + lo * lo);
}

/// Optimal similarity minimizing sum |sigma R(theta) (a-ca) - (b-cb)|^2.
Similarity procrustes(
  Float64List a,
  Float64List b,
  List<double> ca,
  List<double> cb,
) {
  _checkPair(a, b);
  _checkCenter(ca, 'ca');
  _checkCenter(cb, 'cb');
  return _procrustes(a, b, ca, cb);
}

Similarity _procrustes(
  Float64List a,
  Float64List b,
  List<double> ca,
  List<double> cb,
) {
  final n = a.length ~/ 2;
  var sxx = 0.0;
  var sxy = 0.0;
  var syx = 0.0;
  var syy = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < n; i++) {
    final ax = a[2 * i] - ca[0];
    final ay = a[2 * i + 1] - ca[1];
    final bx = b[2 * i] - cb[0];
    final by = b[2 * i + 1] - cb[1];
    sxx += ax * bx;
    syy += ay * by;
    sxy += ax * by;
    syx += ay * bx;
    na += ax * ax + ay * ay;
    nb += bx * bx + by * by;
  }
  final theta = math.atan2(sxy - syx, sxx + syy);
  final num = math.cos(theta) * (sxx + syy) + math.sin(theta) * (sxy - syx);
  var sigma = na > 1e-12 ? num / na : 1.0;
  if (!(sigma > 1e-6)) sigma = 1e-6;
  final res2 = math.max(0.0, sigma * sigma * na - 2 * sigma * num + nb);
  final res = nb > 1e-12 ? math.sqrt(res2 / nb) : 0.0;
  return Similarity(theta: theta, sigma: sigma, res: res);
}

/// Searches traversal directions and the circular offsets of ONE closed cloud.
/// Regions pass allowReverse=false to preserve winding.
Alignment alignPair(
  Float64List a,
  Float64List b, [
  bool aClosed = false,
  bool bClosed = false,
  bool allowReverse = true,
  double lambda = _lambda,
]) {
  _checkPair(a, b);
  if (!lambda.isFinite || lambda < 0) {
    throw ArgumentError.value(
        lambda, 'lambda', 'Must be finite and nonnegative');
  }
  final ca = centroid(a);
  final cb = centroid(b);
  final varyA = aClosed && !bClosed;
  final base = varyA ? a : b;
  final offs = aClosed || bClosed ? base.length ~/ 2 : 1;
  var bestScore = double.infinity;
  var best = base;
  var sim = const Similarity(theta: 0, sigma: 1, res: 0);
  for (var dir = 0; dir < (allowReverse ? 2 : 1); dir++) {
    final walk = dir == 1 ? reversePts(base) : base;
    for (var off = 0; off < offs; off++) {
      final cand = off == 0 ? walk : rotatePts(walk, off);
      final s =
          varyA ? _procrustes(cand, b, ca, cb) : _procrustes(a, cand, ca, cb);
      final score = s.res + lambda * s.theta.abs() / math.pi;
      if (score < bestScore) {
        bestScore = score;
        best = cand;
        sim = s;
      }
    }
  }
  return Alignment(
    ca: ca,
    cb: cb,
    a: varyA ? best : a,
    b: varyA ? b : best,
    theta: sim.theta,
    sigma: sim.sigma,
    res: sim.res,
  );
}

/// dist(centroids) + 0.35 * |length difference| for every pair.
List<List<double>> costMatrix(List<Float64List> a, List<Float64List> b) {
  final cbs = b.map(centroid).toList();
  final lbs = b.map(polyLen).toList();
  return a.map((points) {
    final ca = centroid(points);
    final la = polyLen(points);
    return List<double>.generate(b.length, (j) {
      final cb = cbs[j];
      return _hypot(ca[0] - cb[0], ca[1] - cb[1]) +
          _lenWeight * (la - lbs[j]).abs();
    });
  }).toList();
}

// Exhaustive permutation with pruning up to 8!, otherwise sorted greedy.
List<int> _bestPermutation(List<List<double>> costs) {
  final n = costs.length;
  if (n > _permMax) {
    final pairs = <(double, int, int)>[
      for (var i = 0; i < n; i++)
        for (var j = 0; j < n; j++) (costs[i][j], i, j),
    ];
    pairs.sort((x, y) {
      final cost = x.$1.compareTo(y.$1);
      if (cost != 0) return cost;
      // JS Array.sort is stable: preserve insertion order for tied costs.
      final row = x.$2.compareTo(y.$2);
      return row != 0 ? row : x.$3.compareTo(y.$3);
    });
    final out = List<int>.filled(n, -1);
    final used = List<bool>.filled(n, false);
    for (final pair in pairs) {
      final i = pair.$2;
      final j = pair.$3;
      if (out[i] < 0 && !used[j]) {
        out[i] = j;
        used[j] = true;
      }
    }
    return out;
  }
  final idx = List<int>.generate(n, (i) => i);
  var best = List<int>.of(idx);
  var bestCost = double.infinity;
  void permute(int k, double acc) {
    if (acc >= bestCost) return;
    if (k == n) {
      bestCost = acc;
      best = List<int>.of(idx);
      return;
    }
    for (var i = k; i < n; i++) {
      final tmp = idx[k];
      idx[k] = idx[i];
      idx[i] = tmp;
      permute(k + 1, acc + costs[k][idx[k]]);
      idx[i] = idx[k];
      idx[k] = tmp;
    }
  }

  permute(0, 0);
  return best;
}

// Large side -> small side, exhaustive when S^B <= SURJ_MAX. Above the
// budget, repair greedy coverage by moving only rows with duplicate donors.
List<int> _bestSurjection(List<List<double>> costs) {
  final big = costs.length;
  final small = costs[0].length;
  if (math.pow(small, big) > SURJ_MAX) {
    final f = costs.map((row) {
      var m = 0;
      for (var j = 1; j < row.length; j++) {
        if (row[j] < row[m]) m = j;
      }
      return m;
    }).toList();
    final mult = List<int>.filled(small, 0);
    for (final s in f) {
      mult[s]++;
    }
    for (var s = 0; s < small; s++) {
      if (mult[s] > 0) continue;
      var bestIndex = -1;
      var bestCost = double.infinity;
      for (var i = 0; i < big; i++) {
        if (mult[f[i]] < 2) continue;
        final extra = costs[i][s] - costs[i][f[i]];
        if (extra < bestCost) {
          bestCost = extra;
          bestIndex = i;
        }
      }
      mult[f[bestIndex]]--;
      f[bestIndex] = s;
      mult[s]++;
    }
    return f;
  }
  List<int>? best;
  var bestCost = double.infinity;
  final f = List<int>.filled(big, 0);
  final mult = List<int>.filled(small, 0);
  void assign(int i, double acc, int covered) {
    if (acc >= bestCost || small - covered > big - i) return;
    if (i == big) {
      bestCost = acc;
      best = List<int>.of(f);
      return;
    }
    for (var s = 0; s < small; s++) {
      f[i] = s;
      mult[s]++;
      assign(i + 1, acc + costs[i][s], covered + (mult[s] == 1 ? 1 : 0));
      mult[s]--;
    }
  }

  assign(0, 0, 0);
  if (best == null) {
    throw StateError('morphicons: no valid surjection (B < S)');
  }
  return best!;
}

/// Applies a shared similarity when the concatenated clouds are congruent.
/// Centroids ride the global similarity rather than its straight-line chord.
void applyGlobal(List<PlanItem> items, int n) {
  if (n <= 0) throw ArgumentError.value(n, 'n', 'Must be positive');
  if (items.isEmpty) return;
  final ga = Float64List(2 * items.length * n);
  final gb = Float64List(ga.length);
  for (var k = 0; k < items.length; k++) {
    final it = items[k];
    if (it.a.length != 2 * n ||
        it.bO.length != 2 * n ||
        it.aC.length != 2 * n ||
        it.bT.length != 2 * n) {
      throw ArgumentError('morphicons: plan item sample counts differ');
    }
    ga.setAll(2 * n * k, it.a);
    gb.setAll(2 * n * k, it.bO);
  }
  final gca = centroid(ga);
  final g = procrustes(ga, gb, gca, centroid(gb));
  if (g.res >= _globalEps) return;
  final cos = math.cos(-g.theta);
  final sin = math.sin(-g.theta);
  final rc = math.cos(g.theta);
  final rs = math.sin(g.theta);
  for (final it in items) {
    var e2 = 0.0;
    var nb = 0.0;
    for (var i = 0; i < n; i++) {
      final bx = it.bO[2 * i] - it.cb[0];
      final by = it.bO[2 * i + 1] - it.cb[1];
      it.bT[2 * i] = (bx * cos - by * sin) / g.sigma;
      it.bT[2 * i + 1] = (bx * sin + by * cos) / g.sigma;
      final ex = g.sigma * (rc * it.aC[2 * i] - rs * it.aC[2 * i + 1]) - bx;
      final ey = g.sigma * (rs * it.aC[2 * i] + rc * it.aC[2 * i + 1]) - by;
      e2 += ex * ex + ey * ey;
      nb += bx * bx + by * by;
    }
    it.theta = g.theta;
    it.lnSigma = math.log(g.sigma);
    it.res = nb > 1e-12 ? math.sqrt(e2 / nb) : 0;
    // Match the interpolator's arithmetic so rotation deltas cancel exactly.
    final s1 = math.exp(it.lnSigma);
    final c1 = math.cos(it.theta) * s1;
    final n1 = math.sin(it.theta) * s1;
    final ox = it.ca[0] - gca[0];
    final oy = it.ca[1] - gca[1];
    final rx = ox * c1 - oy * n1 - ox;
    final ry = ox * n1 + oy * c1 - oy;
    it.block = BlockTransport(
      off: [ox, oy],
      drift: [it.cb[0] - it.ca[0] - rx, it.cb[1] - it.ca[1] - ry],
    );
  }
}

/// Minimum-cost permutation or surjection. Leftovers duplicate in place,
/// never collapsing a source to a point or creating a target from nothing.
List<List<int>> pairUp(List<Float64List> a, List<Float64List> b) {
  final p = a.length;
  final q = b.length;
  if (p == 0 || q == 0) {
    if (p == q) return <List<int>>[];
    throw ArgumentError('morphicons: icon has no subpaths');
  }
  final pairs = <List<int>>[];
  if (p == q) {
    final perm = _bestPermutation(costMatrix(a, b));
    for (var i = 0; i < p; i++) {
      pairs.add([i, perm[i]]);
    }
  } else if (p < q) {
    final f = _bestSurjection(costMatrix(b, a));
    for (var j = 0; j < q; j++) {
      pairs.add([f[j], j]);
    }
  } else {
    final f = _bestSurjection(costMatrix(a, b));
    for (var i = 0; i < p; i++) {
      pairs.add([i, f[i]]);
    }
  }
  return pairs;
}

PlanItem makeItem(
  Float64List a,
  Float64List b,
  bool aClosed,
  bool bClosed,
  bool allowReverse, [
  double lambda = _lambda,
]) {
  final al = alignPair(a, b, aClosed, bClosed, allowReverse, lambda);
  final n = a.length ~/ 2;
  final aC = Float64List(2 * n);
  final bT = Float64List(2 * n);
  final bO = Float64List(2 * n);
  final cos = math.cos(-al.theta);
  final sin = math.sin(-al.theta);
  for (var i = 0; i < n; i++) {
    aC[2 * i] = al.a[2 * i] - al.ca[0];
    aC[2 * i + 1] = al.a[2 * i + 1] - al.ca[1];
    final bx = al.b[2 * i] - al.cb[0];
    final by = al.b[2 * i + 1] - al.cb[1];
    bT[2 * i] = (bx * cos - by * sin) / al.sigma;
    bT[2 * i + 1] = (bx * sin + by * cos) / al.sigma;
    bO[2 * i] = al.b[2 * i];
    bO[2 * i + 1] = al.b[2 * i + 1];
  }
  return PlanItem(
    a: al.a,
    aC: aC,
    bT: bT,
    bO: bO,
    ca: al.ca,
    cb: al.cb,
    theta: al.theta,
    lnSigma: math.log(al.sigma),
    res: al.res,
    closed: aClosed && bClosed,
  );
}

/// Builds a cacheable morph plan, including plans from intermediate shapes.
/// Filled-region planning uses the same primitives but locks winding.
MorphPlan buildPlan(List<Sampled> srcSubs, List<Sampled> dstSubs) {
  if (srcSubs.isEmpty || dstSubs.isEmpty) {
    throw ArgumentError('morphicons: icon has no subpaths');
  }
  final a = srcSubs.map((s) => s.pts).toList();
  final b = dstSubs.map((s) => s.pts).toList();
  final length = a[0].length;
  for (final cloud in a) {
    _checkCloud(cloud, 'srcSubs');
    if (cloud.length != length) {
      throw ArgumentError(
          'morphicons: point clouds must have equal sample counts');
    }
  }
  for (final cloud in b) {
    _checkCloud(cloud, 'dstSubs');
    if (cloud.length != length) {
      throw ArgumentError(
          'morphicons: point clouds must have equal sample counts');
    }
  }
  final items = pairUp(a, b).map((pair) {
    final si = pair[0];
    final di = pair[1];
    return makeItem(a[si], b[di], srcSubs[si].closed, dstSubs[di].closed, true);
  }).toList();
  final n = length ~/ 2;
  if (items.length > 1) applyGlobal(items, n);
  return MorphPlan(items: items, n: n);
}
