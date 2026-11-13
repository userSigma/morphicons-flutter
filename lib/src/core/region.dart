import 'dart:math' as math;
import 'dart:typed_data';

import 'types.dart';

/// How an icon is painted: historical stroke centerlines or a filled surface.
enum IconPaint { stroke, fill }

/// Marks one already-normalized, nonzero-wound region path.
const regionAttr = 'data-region';

/// Retains the source constant's spelling for callers porting region metadata.
// ignore: constant_identifier_names
const REGION_ATTR = regionAttr;

/// A paint attribute that is present and not `none`.
bool painted(Object? value) =>
    value != null && value.toString().trim().toLowerCase() != 'none';

IconPaint paintOf(IconInput input) {
  if (input is String) return IconPaint.stroke;
  for (final node in input as List<IconNode>) {
    if (painted(node.attrs['fill'])) return IconPaint.fill;
  }
  return IconPaint.stroke;
}

// SVG numeric attributes use parseFloat semantics (e.g. "0.2foo").
final _numericPrefix = RegExp(
  r'^[\s]*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|[+-]?Infinity)',
);
double _opacity(Object? v) {
  if (v is num) return v.toDouble();
  final m = _numericPrefix.firstMatch(v?.toString() ?? '');
  return m == null ? double.nan : double.tryParse(m[1]!) ?? double.nan;
}

/// Duotone backgrounds are omitted from the monochrome silhouette.
bool translucent(IconNodeAttrs attrs) =>
    _opacity(attrs['opacity']) < .5 || _opacity(attrs['fill-opacity']) < .5;

IconInput solid(IconInput input) => input is String ||
        paintOf(input) == IconPaint.stroke
    ? input
    : (input as List<IconNode>).where((el) => !translucent(el.attrs)).toList();

bool isRegion(IconInput input) =>
    input is List<IconNode> &&
    input.length == 1 &&
    input.first.attrs.containsKey(regionAttr);

/// Even-odd point containment of a closed point cloud.
bool inside(double px, double py, Float64List p) {
  final n = p.length ~/ 2;
  var c = false;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final yi = p[2 * i + 1], yj = p[2 * j + 1];
    if ((yi > py) != (yj > py) &&
        px < (p[2 * j] - p[2 * i]) * (py - yi) / (yj - yi) + p[2 * i]) {
      c = !c;
    }
  }
  return c;
}

double distSeg(
    double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  var t = l2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / l2 : 0.0;
  t = t.clamp(0.0, 1.0);
  final ex = px - ax - t * dx, ey = py - ay - t * dy;
  return math.sqrt(ex * ex + ey * ey);
}

/// Shoelace area in SVG axes (y down): outers positive, holes negative.
double signedArea(Float64List p) {
  final n = p.length ~/ 2;
  var a = 0.0;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    a += p[2 * j] * p[2 * i + 1] - p[2 * i] * p[2 * j + 1];
  }
  return a / 2;
}
