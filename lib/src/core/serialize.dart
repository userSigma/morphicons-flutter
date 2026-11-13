import 'dart:typed_data';

import 'types.dart';

// Math.round in JavaScript resolves half ties toward +infinity, whereas Dart's
// round resolves them away from zero. Compare the fractional part explicitly
// rather than floor(v + 0.5), which rounds some just-below-half values upward.
String _format(double value, double scale) {
  final scaled = value * scale;
  if (!scaled.isFinite) {
    throw ArgumentError.value(
        value, 'coordinate', 'morphicons: expected finite coordinate');
  }
  final base = scaled.floorToDouble();
  final rounded = (scaled - base >= 0.5 ? base + 1 : base) / scale;
  if (rounded == 0) return '0';
  return _numberString(rounded);
}

// Match JS's integer spelling and exponent thresholds for canonical SVG bytes.
String _numberString(double value) {
  final raw = value.toString();
  final e = raw.indexOf('e');
  if (e < 0) return raw.endsWith('.0') ? raw.substring(0, raw.length - 2) : raw;
  var mantissa = raw.substring(0, e);
  final exponent = int.parse(raw.substring(e + 1));
  if (mantissa.endsWith('.0'))
    mantissa = mantissa.substring(0, mantissa.length - 2);
  if (exponent < -6 || exponent >= 21) {
    return '${mantissa}e${exponent >= 0 ? '+' : ''}$exponent';
  }
  final negative = mantissa.startsWith('-');
  if (negative) mantissa = mantissa.substring(1);
  final dot = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final decimal = (dot < 0 ? digits.length : dot) + exponent;
  final String body;
  if (decimal <= 0) {
    body = '0.${'0' * -decimal}$digits';
  } else if (decimal >= digits.length) {
    body = '$digits${'0' * (decimal - digits.length)}';
  } else {
    body = '${digits.substring(0, decimal)}.${digits.substring(decimal)}';
  }
  return negative ? '-$body' : body;
}

/// Sampled subpaths to two-decimal M/L polylines, with optional closing flags.
String serialize(List<Float64List> subs, [List<bool>? closed]) {
  final d = StringBuffer();
  for (var k = 0; k < subs.length; k++) {
    final pts = subs[k];
    if (pts.length < 2 || pts.length.isOdd) {
      throw ArgumentError(
          'morphicons: invalid sampled point count ${pts.length}');
    }
    d.write('M${_format(pts[0], 100)} ${_format(pts[1], 100)}');
    for (var i = 2; i < pts.length; i += 2) {
      d.write('L${_format(pts[i], 100)} ${_format(pts[i + 1], 100)}');
    }
    if (closed != null && k < closed.length && closed[k]) d.write('Z');
  }
  return d.toString();
}

/// Canonical four-decimal cubic SVG output, stable against trig ulp drift.
String cubicsToPathD(List<CubicPath> paths) {
  final d = StringBuffer();
  for (final path in paths) {
    segCount(path);
    final pts = path.pts;
    d.write('M${_format(pts[0], 1e4)} ${_format(pts[1], 1e4)}');
    for (var i = 2; i < pts.length; i += 6) {
      d.write('C${_format(pts[i], 1e4)} ${_format(pts[i + 1], 1e4)} '
          '${_format(pts[i + 2], 1e4)} ${_format(pts[i + 3], 1e4)} '
          '${_format(pts[i + 4], 1e4)} ${_format(pts[i + 5], 1e4)}');
    }
    if (path.closed) d.write('Z');
  }
  return d.toString();
}
