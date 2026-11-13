import 'dart:math' as math;
import 'dart:typed_data';

import 'parse.dart';
import 'serialize.dart';
import 'types.dart';

/// Quarter-circle cubic control-point offset: (4/3) tan(pi/8).
final double KAPPA = (4 / 3) * math.tan(math.pi / 8);
const double _tau = 2 * math.pi;

class _Builder {
  _Builder(double x, double y)
      : pts = [x, y],
        cx = x,
        cy = y;

  final List<double> pts;
  double cx;
  double cy;

  void cubic(double x1, double y1, double x2, double y2, double x, double y) {
    final values = [x1, y1, x2, y2, x, y];
    if (values.any((v) => !v.isFinite)) {
      throw const FormatException(
          'morphicons: non-finite normalized coordinate');
    }
    pts.addAll(values);
    cx = x;
    cy = y;
  }

  void line(double x, double y) {
    if ((x - cx).abs() < 1e-12 && (y - cy).abs() < 1e-12) return;
    cubic(cx + (x - cx) / 3, cy + (y - cy) / 3, cx + (2 * (x - cx)) / 3,
        cy + (2 * (y - cy)) / 3, x, y);
  }

  void quad(double x1, double y1, double x, double y) {
    cubic(cx + (2 / 3) * (x1 - cx), cy + (2 / 3) * (y1 - cy),
        x + (2 / 3) * (x1 - x), y + (2 / 3) * (y1 - y), x, y);
  }

  // Endpoint -> center parametrization, SVG appendix F.6. Each slice is <=90deg.
  void arc(double rx0, double ry0, double rotDeg, double large, double sweep,
      double x, double y) {
    final x1 = cx;
    final y1 = cy;
    if ((x - x1).abs() < 1e-12 && (y - y1).abs() < 1e-12) return;
    var rx = rx0.abs();
    var ry = ry0.abs();
    if (rx < 1e-12 || ry < 1e-12) {
      line(x, y);
      return;
    }
    final phi = (rotDeg * math.pi) / 180;
    final cosP = math.cos(phi);
    final sinP = math.sin(phi);
    final hx = (x1 - x) / 2;
    final hy = (y1 - y) / 2;
    final x1p = cosP * hx + sinP * hy;
    final y1p = -sinP * hx + cosP * hy;
    final lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1) {
      final scale = math.sqrt(lam);
      rx *= scale;
      ry *= scale;
    }
    final rx2 = rx * rx;
    final ry2 = ry * ry;
    final xp2 = x1p * x1p;
    final yp2 = y1p * y1p;
    var rad = (rx2 * ry2 - rx2 * yp2 - ry2 * xp2) / (rx2 * yp2 + ry2 * xp2);
    if (rad < 0) rad = 0;
    final co = (large == sweep ? -1 : 1) * math.sqrt(rad);
    final cxp = (co * rx * y1p) / ry;
    final cyp = (-co * ry * x1p) / rx;
    final ccx = cosP * cxp - sinP * cyp + (x1 + x) / 2;
    final ccy = sinP * cxp + cosP * cyp + (y1 + y) / 2;
    final th1 = math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx);
    var dth = math.atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - th1;
    if (sweep == 0 && dth > 0) {
      dth -= _tau;
    } else if (sweep == 1 && dth < 0) {
      dth += _tau;
    }
    if (![ccx, ccy, th1, dth].every((v) => v.isFinite)) {
      throw const FormatException('morphicons: non-finite elliptical arc');
    }
    final slices = math.max(1, (dth.abs() / (math.pi / 2) - 1e-9).ceil());
    final delta = dth / slices;
    final alpha = (4 / 3) * math.tan(delta / 4);
    double ex(double t) =>
        ccx + rx * math.cos(t) * cosP - ry * math.sin(t) * sinP;
    double ey(double t) =>
        ccy + rx * math.cos(t) * sinP + ry * math.sin(t) * cosP;
    double dx(double t) => -rx * math.sin(t) * cosP - ry * math.cos(t) * sinP;
    double dy(double t) => -rx * math.sin(t) * sinP + ry * math.cos(t) * cosP;
    var t0 = th1;
    var p0x = x1;
    var p0y = y1;
    for (var s = 1; s <= slices; s++) {
      final t1 = th1 + delta * s;
      final p1x = s == slices ? x : ex(t1);
      final p1y = s == slices ? y : ey(t1);
      cubic(p0x + alpha * dx(t0), p0y + alpha * dy(t0), p1x - alpha * dx(t1),
          p1y - alpha * dy(t1), p1x, p1y);
      t0 = t1;
      p0x = p1x;
      p0y = p1y;
    }
  }

  CubicPath? finish(bool closed) {
    if (closed) line(pts[0], pts[1]);
    if (pts.length < 8) return null;
    return CubicPath(Float64List.fromList(pts), closed: closed);
  }
}

CubicPath? _lowerSubpath(RawSubpath raw) {
  final b = _Builder(raw.x0, raw.y0);
  for (final seg in raw.segs) {
    final s = seg.values;
    switch (seg.tag) {
      case 'L':
        b.line(s[0], s[1]);
      case 'C':
        b.cubic(s[0], s[1], s[2], s[3], s[4], s[5]);
      case 'Q':
        b.quad(s[0], s[1], s[2], s[3]);
      case 'A':
        b.arc(s[0], s[1], s[2], s[3], s[4], s[5], s[6]);
    }
  }
  return b.finish(raw.closed);
}

double _attrNum(IconNodeAttrs attrs, String key, [double fallback = 0]) {
  final value = attrs[key];
  if (value == null) return fallback;
  final double? x;
  if (value is num) {
    x = value.toDouble();
  } else if (value is String) {
    x = value.trim().isEmpty ? 0 : double.tryParse(value.trim());
  } else {
    x = null;
  }
  return x != null && x.isFinite ? x : fallback;
}

List<double> _parsePoints(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty) return [];
  final nums = <double>[];
  for (final token in s.split(RegExp(r'[\s,]+'))) {
    final number = double.tryParse(token);
    if (number == null || !number.isFinite) {
      throw FormatException('morphicons: invalid points: "$s"');
    }
    nums.add(number);
  }
  return nums;
}

CubicPath? _polyPath(List<double> nums, bool closed) {
  if (nums.length < 4) return null;
  final b = _Builder(nums[0], nums[1]);
  for (var i = 2; i + 1 < nums.length; i += 2) {
    b.line(nums[i], nums[i + 1]);
  }
  return b.finish(closed);
}

CubicPath? _ellipsePath(double cx, double cy, double rx, double ry) {
  if (rx < 1e-12 || ry < 1e-12) return null;
  final kx = KAPPA * rx;
  final ky = KAPPA * ry;
  final e = cx + rx;
  final w = cx - rx;
  final s = cy + ry;
  final n = cy - ry;
  final b = _Builder(e, cy);
  b.cubic(e, cy + ky, cx + kx, s, cx, s);
  b.cubic(cx - kx, s, w, cy + ky, w, cy);
  b.cubic(w, cy - ky, cx - kx, n, cx, n);
  b.cubic(cx + kx, n, e, cy - ky, e, cy);
  return b.finish(true);
}

CubicPath? _rectPath(IconNodeAttrs attrs) {
  final x = _attrNum(attrs, 'x');
  final y = _attrNum(attrs, 'y');
  final w = _attrNum(attrs, 'width');
  final h = _attrNum(attrs, 'height');
  if (w < 1e-12 || h < 1e-12) return null;
  var rx = _attrNum(attrs, 'rx', double.nan);
  var ry = _attrNum(attrs, 'ry', double.nan);
  if (rx.isNaN) rx = ry.isNaN ? 0 : ry;
  if (ry.isNaN) ry = rx;
  rx = math.min(math.max(rx, 0), w / 2);
  ry = math.min(math.max(ry, 0), h / 2);
  if (rx < 1e-12 || ry < 1e-12) {
    return _polyPath([x, y, x + w, y, x + w, y + h, x, y + h], true);
  }
  final xa = x + rx;
  final xb = x + w - rx;
  final xr = x + w;
  final ya = y + ry;
  final yb = y + h - ry;
  final yd = y + h;
  final kx = KAPPA * rx;
  final ky = KAPPA * ry;
  final b = _Builder(xa, y);
  b.line(xb, y);
  b.cubic(xb + kx, y, xr, ya - ky, xr, ya);
  b.line(xr, yb);
  b.cubic(xr, yb + ky, xb + kx, yd, xb, yd);
  b.line(xa, yd);
  b.cubic(xa - kx, yd, x, yb + ky, x, yb);
  b.line(x, ya);
  b.cubic(x, ya - ky, xa - kx, y, xa, y);
  return b.finish(true);
}

/// SVG path data or basic SVG nodes -> normalized cubic subpaths.
List<CubicPath> iconToCubics(IconInput input) {
  final out = <CubicPath>[];
  void push(CubicPath? p) {
    if (p != null) out.add(p);
  }

  if (input is String) {
    for (final s in parsePath(input)) {
      push(_lowerSubpath(s));
    }
    return out;
  }
  if (input is! List<IconNode>) {
    throw ArgumentError.value(
        input, 'input', 'morphicons: expected a String or List<IconNode>');
  }
  for (final node in input) {
    final attrs = node.attrs;
    switch (node.tag) {
      case 'path':
        for (final s in parsePath((attrs['d'] ?? '').toString())) {
          push(_lowerSubpath(s));
        }
      case 'line':
        final b = _Builder(_attrNum(attrs, 'x1'), _attrNum(attrs, 'y1'));
        b.line(_attrNum(attrs, 'x2'), _attrNum(attrs, 'y2'));
        push(b.finish(false));
      case 'circle':
        final r = _attrNum(attrs, 'r');
        push(_ellipsePath(_attrNum(attrs, 'cx'), _attrNum(attrs, 'cy'), r, r));
      case 'ellipse':
        push(_ellipsePath(_attrNum(attrs, 'cx'), _attrNum(attrs, 'cy'),
            _attrNum(attrs, 'rx'), _attrNum(attrs, 'ry')));
      case 'rect':
        push(_rectPath(attrs));
      case 'polyline':
        push(_polyPath(_parsePoints(attrs['points']), false));
      case 'polygon':
        push(_polyPath(_parsePoints(attrs['points']), true));
      default:
        throw ArgumentError('morphicons: unsupported tag <${node.tag}>');
    }
  }
  return out;
}

/// Typed source SVG coordinate space, also accepted by [fitIcon].
class ViewBox {
  const ViewBox(this.minX, this.minY, this.width, this.height);

  final double minX;
  final double minY;
  final double width;
  final double height;
}

List<double> _parseViewBox(Object vb) {
  final List<double> values;
  if (vb is ViewBox) {
    values = [vb.minX, vb.minY, vb.width, vb.height];
  } else if (vb is num) {
    values = [0, 0, vb.toDouble(), vb.toDouble()];
  } else if (vb is String) {
    values = vb
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map((s) => double.tryParse(s) ?? double.nan)
        .toList();
  } else if (vb is List && vb.every((v) => v is num)) {
    values = vb.map((v) => (v as num).toDouble()).toList();
  } else {
    throw ArgumentError('morphicons: invalid viewBox "$vb"');
  }
  if (values.length != 4 ||
      !values.every((v) => v.isFinite) ||
      values[2] <= 0 ||
      values[3] <= 0) {
    throw ArgumentError('morphicons: invalid viewBox "$vb"');
  }
  return values;
}

/// Fits an icon into a common square grid with SVG xMidYMid meet semantics.
///
/// [viewBox] accepts a side length, SVG viewBox string or numeric four-item list.
String fitIcon(IconInput input, Object viewBox, [double grid = 24]) {
  if (!grid.isFinite || grid <= 0) {
    throw ArgumentError.value(
        grid, 'grid', 'morphicons: expected positive finite grid');
  }
  final v = _parseViewBox(viewBox);
  final minX = v[0];
  final minY = v[1];
  final w = v[2];
  final h = v[3];
  final scale = math.min(grid / w, grid / h);
  final tx = (grid - w * scale) / 2 - minX * scale;
  final ty = (grid - h * scale) / 2 - minY * scale;
  final paths = iconToCubics(input);
  for (final path in paths) {
    final pts = path.pts;
    for (var i = 0; i < pts.length; i += 2) {
      pts[i] = pts[i] * scale + tx;
      pts[i + 1] = pts[i + 1] * scale + ty;
    }
  }
  return cubicsToPathD(paths);
}
