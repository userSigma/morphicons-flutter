// Visible-surface normalization: signed distance fields, marching squares,
// ring simplification and sharp-corner recovery. No renderer or dart:ui.
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/normalize.dart';
import '../core/plan.dart';
import '../core/region.dart';
import '../core/types.dart';
import 'plan.dart';

export '../core/region.dart' show IconPaint, isRegion, paintOf;
export 'plan.dart' show buildRegionPlan, resampleRegion;

class RegionOptions {
  const RegionOptions({this.strokeWidth = 2, this.cell = .125});
  final double strokeWidth;
  final double cell;
}

const _big = 1e9;
final _numericPrefix = RegExp(
  r'^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|[+-]?Infinity)',
);
double _num(Object? v, double fallback) {
  final x = v is num
      ? v.toDouble()
      : double.tryParse(
          _numericPrefix.firstMatch(v?.toString() ?? '')?[1] ?? '');
  return x != null && x.isFinite ? x : fallback;
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

class _Part {
  _Part(this.lines, this.closed, this.half, this.fill);
  final List<Float64List> lines;
  final List<bool> closed;
  final double half;
  // 0 = none, 1 = nonzero, 2 = evenodd.
  final int fill;
}

// Cubic flattening bounded by |B''|/(8*n*n), with maximum 128 steps.
({List<Float64List> lines, List<bool> closed}) _flatten(
    IconInput input, double tol) {
  final lines = <Float64List>[];
  final closed = <bool>[];
  for (final path in iconToCubics(input)) {
    final p = path.pts;
    if (p.isEmpty) continue;
    final out = <double>[p[0], p[1]];
    for (var i = 0; i + 7 < p.length; i += 6) {
      final x0 = p[i], y0 = p[i + 1];
      final x1 = p[i + 2], y1 = p[i + 3];
      final x2 = p[i + 4], y2 = p[i + 5];
      final x3 = p[i + 6], y3 = p[i + 7];
      final dd = math.max(
        _hypot(x0 - 2 * x1 + x2, y0 - 2 * y1 + y2),
        _hypot(x1 - 2 * x2 + x3, y1 - 2 * y2 + y3),
      );
      final k =
          math.min(128, math.max(1, math.sqrt(6 * dd / (8 * tol)).ceil()));
      for (var s = 1; s <= k; s++) {
        final t = s / k, u = 1 - t;
        out.addAll([
          u * u * u * x0 +
              3 * u * u * t * x1 +
              3 * u * t * t * x2 +
              t * t * t * x3,
          u * u * u * y0 +
              3 * u * u * t * y1 +
              3 * u * t * t * y2 +
              t * t * t * y3,
        ]);
      }
    }
    lines.add(Float64List.fromList(out));
    closed.add(path.closed);
  }
  return (lines: lines, closed: closed);
}

List<_Part> _partsOf(IconInput input, double width, double tol) {
  if (input is String) {
    final f = _flatten(input, tol);
    return [_Part(f.lines, f.closed, width / 2, 0)];
  }
  final fillIcon = paintOf(input) == IconPaint.fill;
  final parts = <_Part>[];
  for (final el in input as List<IconNode>) {
    final a = el.attrs;
    if (translucent(a)) continue;
    final strokeOn = fillIcon
        ? painted(a['stroke'])
        : a['stroke'] == null || painted(a['stroke']);
    final fillOn =
        fillIcon && (painted(a['fill']) || (a['fill'] == null && !strokeOn));
    if (!strokeOn && !fillOn) continue;
    final f = _flatten([el], tol);
    parts.add(_Part(
      f.lines,
      f.closed,
      strokeOn ? _num(a['stroke-width'], width) / 2 : 0,
      fillOn
          ? ((a['fill-rule'] ?? '').toString().trim() == 'evenodd' ? 2 : 1)
          : 0,
    ));
  }
  return parts;
}

class _Grid {
  const _Grid(this.x0, this.y0, this.h, this.nx, this.ny);
  final double x0, y0, h;
  final int nx, ny;
}

void _eachNear(_Grid g, double ax, double ay, double bx, double by, double r,
    void Function(int k, double x, double y) fn) {
  final i0 = math.max(0, ((math.min(ax, bx) - r - g.x0) / g.h).floor());
  final i1 = math.min(g.nx - 1, ((math.max(ax, bx) + r - g.x0) / g.h).ceil());
  final j0 = math.max(0, ((math.min(ay, by) - r - g.y0) / g.h).floor());
  final j1 = math.min(g.ny - 1, ((math.max(ay, by) + r - g.y0) / g.h).ceil());
  for (var j = j0; j <= j1; j++) {
    final y = g.y0 + j * g.h;
    for (var i = i0; i <= i1; i++) {
      fn(j * g.nx + i, g.x0 + i * g.h, y);
    }
  }
}

void _eachSeg(Float64List p, bool close,
    void Function(double ax, double ay, double bx, double by) fn) {
  final n = p.length ~/ 2;
  if (n == 1) fn(p[0], p[1], p[0], p[1]);
  for (var i = 0; i + 1 < n; i++) {
    fn(p[2 * i], p[2 * i + 1], p[2 * i + 2], p[2 * i + 3]);
  }
  if (close && n > 2) fn(p[2 * n - 2], p[2 * n - 1], p[0], p[1]);
}

// Union = pointwise minimum. Fill signs are accumulated per element, never
// across elements: overlapping evenodd elements still union, rather than XOR.
Float32List _field(List<_Part> parts, _Grid g) {
  final f = Float32List(g.nx * g.ny)..fillRange(0, g.nx * g.ny, _big);
  final band = 2 * g.h;
  Float32List? distance;
  for (final part in parts) {
    if (part.half > 0) {
      final r = part.half + band;
      for (var li = 0; li < part.lines.length; li++) {
        _eachSeg(part.lines[li], part.closed[li], (ax, ay, bx, by) {
          _eachNear(g, ax, ay, bx, by, r, (k, x, y) {
            final d = distSeg(x, y, ax, ay, bx, by) - part.half;
            if (d < f[k]) f[k] = d;
          });
        });
      }
    }
    if (part.fill != 0) {
      distance ??= Float32List(g.nx * g.ny);
      final d = distance..fillRange(0, g.nx * g.ny, _big);
      for (final p in part.lines) {
        _eachSeg(p, true, (ax, ay, bx, by) {
          _eachNear(g, ax, ay, bx, by, band, (k, x, y) {
            final v = distSeg(x, y, ax, ay, bx, by);
            if (v < d[k]) d[k] = v;
          });
        });
      }
      for (var j = 0; j < g.ny; j++) {
        final y = g.y0 + j * g.h;
        final cross = <(double, int)>[];
        for (final p in part.lines) {
          _eachSeg(p, true, (ax, ay, bx, by) {
            if ((ay <= y) != (by <= y)) {
              cross.add(
                  (ax + (y - ay) * (bx - ax) / (by - ay), by > ay ? 1 : -1));
            }
          });
        }
        cross.sort((u, v) => u.$1.compareTo(v.$1));
        var c = 0, wind = 0;
        for (var i = 0; i < g.nx; i++) {
          final x = g.x0 + i * g.h;
          while (c < cross.length && cross[c].$1 < x) {
            wind += cross[c++].$2;
          }
          final isIn = part.fill == 1 ? wind != 0 : (wind & 1) == 1;
          final k = j * g.nx + i;
          final v = isIn ? -d[k] : d[k];
          if (v < f[k]) f[k] = v;
        }
      }
    }
  }
  return f;
}

// Crossings keyed by grid edges; move them just off grid nodes so contours
// that meet on integer coordinates never share ambiguous nesting vertices.
List<Float64List> _trace(Float32List f, _Grid g) {
  final nx = g.nx, ny = g.ny, h = g.h, x0 = g.x0, y0 = g.y0;
  final pt = <int, (double, double)>{};
  int crossing(int key) {
    if (pt.containsKey(key)) return key;
    final node = key >> 1, i = (key >> 1) % nx;
    final j = (node - i) ~/ nx;
    final vertical = (key & 1) != 0;
    final other = vertical ? node + nx : node + 1;
    final fa = f[node];
    final t = (fa / (fa - f[other])).clamp(1e-5, 1 - 1e-5);
    pt[key] = vertical
        ? (x0 + i * h, y0 + (j + t) * h)
        : (x0 + (i + t) * h, y0 + j * h);
    return key;
  }

  final adj = <int, List<int>>{};
  void link(int a, int b) {
    final ka = crossing(a), kb = crossing(b);
    (adj[ka] ??= <int>[]).add(kb);
    (adj[kb] ??= <int>[]).add(ka);
  }

  for (var j = 0; j + 1 < ny; j++) {
    for (var i = 0; i + 1 < nx; i++) {
      final a = j * nx + i,
          b = j * nx + i + 1,
          c = (j + 1) * nx + i + 1,
          d = (j + 1) * nx + i;
      final ia = f[a] < 0, ib = f[b] < 0, ic = f[c] < 0, id = f[d] < 0;
      final top = 2 * a, right = 2 * b + 1, bottom = 2 * d, left = 2 * a + 1;
      final edges = <int>[];
      if (ia != ib) edges.add(top);
      if (ib != ic) edges.add(right);
      if (id != ic) edges.add(bottom);
      if (ia != id) edges.add(left);
      if (edges.length == 2) {
        link(edges[0], edges[1]);
      } else if (edges.length == 4) {
        final centre = (f[a] + f[b] + f[c] + f[d]) / 4 < 0;
        if (centre == ia) {
          link(top, right);
          link(bottom, left);
        } else {
          link(left, top);
          link(right, bottom);
        }
      }
    }
  }
  final loops = <Float64List>[], seen = <int>{};
  for (final start in adj.keys) {
    if (seen.contains(start)) continue;
    final ring = <double>[];
    var prev = -1, cur = start;
    while (!seen.contains(cur)) {
      seen.add(cur);
      final p = pt[cur]!;
      ring.addAll([p.$1, p.$2]);
      final nb = adj[cur]!;
      final next = nb[0] != prev ? nb[0] : nb[1];
      prev = cur;
      cur = next;
    }
    if (ring.length >= 6) loops.add(Float64List.fromList(ring));
  }
  return loops;
}

void _rdp(Float64List p, int i0, int i1, double tol, Uint8List keep) {
  final n = p.length ~/ 2;
  final ax = p[2 * (i0 % n)],
      ay = p[2 * (i0 % n) + 1],
      bx = p[2 * (i1 % n)],
      by = p[2 * (i1 % n) + 1];
  var worst = -1, wd = tol;
  for (var i = i0 + 1; i < i1; i++) {
    final d = distSeg(p[2 * (i % n)], p[2 * (i % n) + 1], ax, ay, bx, by);
    if (d > wd) {
      wd = d;
      worst = i;
    }
  }
  if (worst < 0) return;
  keep[worst % n] = 1;
  _rdp(p, i0, worst, tol, keep);
  _rdp(p, worst, i1, tol, keep);
}

Float64List _simplify(Float64List p, double tol) {
  final n = p.length ~/ 2;
  if (n < 4) return p;
  var far = 0, fd = -1.0;
  for (var i = 1; i < n; i++) {
    final d = _hypot(p[2 * i] - p[0], p[2 * i + 1] - p[1]);
    if (d > fd) {
      fd = d;
      far = i;
    }
  }
  final keep = Uint8List(n);
  keep[0] = 1;
  keep[far] = 1;
  _rdp(p, 0, far, tol, keep);
  _rdp(p, far, n, tol, keep);
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    if (keep[i] != 0) out.addAll([p[2 * i], p[2 * i + 1]]);
  }
  return Float64List.fromList(out);
}

Float64List _recoverCorners(Float64List p, double h) {
  final n = p.length ~/ 2;
  if (n < 4) return p;
  double len(int k) {
    final a = k % n, b = (k + 1) % n;
    return _hypot(p[2 * b] - p[2 * a], p[2 * b + 1] - p[2 * a + 1]);
  }

  final long = <int>[];
  for (var k = 0; k < n; k++) {
    if (len(k) >= 2.5 * h) long.add(k);
  }
  if (long.length < 2) return p;
  final drop = Uint8List(n), moved = <int, (double, double)>{};
  for (var q = 0; q < long.length; q++) {
    final k1 = long[q], k2 = long[(q + 1) % long.length];
    final gap = (k2 - k1 - 1 + n) % n;
    if (gap < 1 || gap > 3) continue;
    var gl = 0.0;
    for (var s = 1; s <= gap; s++) {
      gl += len(k1 + s);
    }
    if (gl > 3 * h) continue;
    final a0 = k1 % n, a1 = (k1 + 1) % n, b0 = k2 % n, b1 = (k2 + 1) % n;
    final d1x = p[2 * a1] - p[2 * a0], d1y = p[2 * a1 + 1] - p[2 * a0 + 1];
    final d2x = p[2 * b1] - p[2 * b0], d2y = p[2 * b1 + 1] - p[2 * b0 + 1];
    final cr = d1x * d2y - d1y * d2x;
    final ang = math.atan2(cr, d1x * d2x + d1y * d2y).abs();
    if (ang < math.pi / 12) continue;
    final t = ((p[2 * b0] - p[2 * a0]) * d2y -
            (p[2 * b0 + 1] - p[2 * a0 + 1]) * d2x) /
        cr;
    final x = p[2 * a0] + t * d1x, y = p[2 * a0 + 1] + t * d1y;
    final mx = (p[2 * a1] + p[2 * b0]) / 2,
        my = (p[2 * a1 + 1] + p[2 * b0 + 1]) / 2;
    if (_hypot(x - mx, y - my) > 2 * h) continue;
    moved[a1] = (x, y);
    for (var s = 2; s <= gap + 1; s++) {
      drop[(k1 + s) % n] = 1;
    }
  }
  if (moved.isEmpty) return p;
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    if (drop[i] != 0) continue;
    final m = moved[i];
    out.addAll(m == null ? [p[2 * i], p[2 * i + 1]] : [m.$1, m.$2]);
  }
  return Float64List.fromList(out);
}

/// Non-overlapping contours, oriented positive outside / negative in holes.
List<Float64List> regionContours(IconInput input,
    [RegionOptions options = const RegionOptions()]) {
  final h = options.cell;
  if (!h.isFinite || h <= 0)
    throw ArgumentError.value(h, 'cell', 'must be positive and finite');
  final parts = _partsOf(input, options.strokeWidth, .004);
  var minX = double.infinity,
      minY = double.infinity,
      maxX = double.negativeInfinity,
      maxY = double.negativeInfinity,
      pad = 0.0;
  for (final part in parts) {
    pad = math.max(pad, part.half);
    for (final p in part.lines) {
      for (var i = 0; i < p.length; i += 2) {
        minX = math.min(minX, p[i]);
        maxX = math.max(maxX, p[i]);
        minY = math.min(minY, p[i + 1]);
        maxY = math.max(maxY, p[i + 1]);
      }
    }
  }
  if (!(maxX >= minX)) return [];
  pad += 3 * h;
  final g = _Grid(
      minX - pad,
      minY - pad,
      h,
      ((maxX - minX + 2 * pad) / h).ceil() + 1,
      ((maxY - minY + 2 * pad) / h).ceil() + 1);
  final loops = _trace(_field(parts, g), g)
      .where((p) => signedArea(p).abs() > .01)
      .toList();
  return loops.map((l) {
    var depth = 0;
    for (final o in loops) {
      if (!identical(l, o) && inside(l[0], l[1], o)) depth++;
    }
    final hole = depth % 2 == 1;
    final oriented = (signedArea(l) > 0) == !hole ? l : reversePts(l);
    return _recoverCorners(_simplify(oriented, h * .08), h);
  }).toList();
}

String _fmt(double v) {
  // Math.round in the source breaks negative half ties toward +infinity.
  final n = (v * 1000 + .5).floor() / 1000;
  return n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
}

/// Canonical region with round stroke caps/joins and per-element fill rules.
List<IconNode> toRegion(IconInput input,
    [RegionOptions options = const RegionOptions()]) {
  if (isRegion(input)) return input as List<IconNode>;
  final d = StringBuffer();
  for (final p in regionContours(input, options)) {
    d.write('M${_fmt(p[0])} ${_fmt(p[1])}');
    for (var i = 2; i < p.length; i += 2) {
      d.write('L${_fmt(p[i])} ${_fmt(p[i + 1])}');
    }
    d.write('Z');
  }
  if (d.isEmpty) throw StateError('morphicons: icon has no visible surface');
  return [
    IconNode('path', {
      'd': d.toString(),
      'fill': 'currentColor',
      'stroke': 'none',
      'fill-rule': 'nonzero',
      regionAttr: '1',
    })
  ];
}

// Expando is the Dart weak identity cache. The content LRU shares forms rebuilt
// on each render and string inputs; keeping it bounded avoids retaining icons.
final _forms = Expando<Map<double, List<IconNode>>>('region forms');
final _byContent = LinkedHashMap<String, List<IconNode>>();
final _samples = Expando<List<Sampled>>('region samples');
final _plans = Expando<Expando<MorphPlan>>('region plans');
String _content(IconInput icon) => icon is String
    ? icon
    : jsonEncode([
        for (final node in icon as List<IconNode>) [node.tag, node.attrs],
      ]);

List<IconNode> regionOf(IconInput icon, double strokeWidth) {
  if (isRegion(icon)) return icon as List<IconNode>;
  final width = paintOf(icon) == IconPaint.fill &&
          !(icon as List<IconNode>).any((el) =>
              painted(el.attrs['stroke']) && el.attrs['stroke-width'] == null)
      ? 0.0
      : strokeWidth;
  var byWidth = icon is String ? null : _forms[icon];
  final cached = byWidth?[width];
  if (cached != null) return cached;
  final key = '$width|${_content(icon)}';
  final r = _byContent.remove(key) ??
      toRegion(icon, RegionOptions(strokeWidth: strokeWidth));
  _byContent[key] = r;
  if (_byContent.length > 64) _byContent.remove(_byContent.keys.first);
  if (icon is! String) {
    byWidth ??= <double, List<IconNode>>{};
    _forms[icon] = byWidth;
    byWidth[width] = r;
  }
  return r;
}

List<Sampled> _sampledOf(List<IconNode> region) =>
    _samples[region] ??= resampleRegion(region);

MorphPlan regionPlan(IconInput a, IconInput b, [double strokeWidth = 2]) {
  final source = regionOf(a, strokeWidth), target = regionOf(b, strokeWidth);
  final inner = _plans[source] ??= Expando<MorphPlan>('region targets');
  return inner[target] ??=
      buildRegionPlan(_sampledOf(source), _sampledOf(target));
}

/// Interruption from region samples or from a stroke centerline path string.
MorphPlan regionPlanFrom(Object from, IconInput target,
    [double strokeWidth = 2]) {
  final a = from is String
      ? resampleRegion(regionOf(from, strokeWidth))
      : from as List<Sampled>;
  return buildRegionPlan(a, _sampledOf(regionOf(target, strokeWidth)));
}
