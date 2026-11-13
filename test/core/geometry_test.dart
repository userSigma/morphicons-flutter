import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/src/core/normalize.dart';
import 'package:morphicons/src/core/parse.dart';
import 'package:morphicons/src/core/resample.dart';
import 'package:morphicons/src/core/serialize.dart';
import 'package:morphicons/src/core/types.dart';

List<List<Object>> segments(String d) => [
      for (final s in parsePath(d).single.segs) [s.tag, ...s.values],
    ];

double distance(double x, double y) => math.sqrt(x * x + y * y);

bool hasPoint(Float64List pts, double x, double y) {
  for (var i = 0; i < pts.length; i += 2) {
    if (pts[i] == x && pts[i + 1] == y) return true;
  }
  return false;
}

void main() {
  group('SVG path parser', () {
    test('implicit line commands and relative accumulation', () {
      expect(segments('M1 1 2 2 3 3'), [
        ['L', 2, 2],
        ['L', 3, 3],
      ]);
      expect(segments('m1 1 2 2'), [
        ['L', 3, 3]
      ]);
      expect(segments('M12 5l7 7-7 7'), [
        ['L', 19, 12],
        ['L', 12, 19],
      ]);
      expect(segments('M1 2H5V7h2v3'), [
        ['L', 5, 2],
        ['L', 5, 7],
        ['L', 7, 7],
        ['L', 7, 10],
      ]);
    });

    test('cubic and quadratic reflections reset across other commands', () {
      expect(
          segments('M0 0C0 1 1 1 1 0S2 -1 2 0')[1], ['C', 1, -1, 2, -1, 2, 0]);
      expect(segments('M0 0S2 2 4 0').single, ['C', 0, 0, 2, 2, 4, 0]);
      expect(segments('M0 0Q1 1 2 0T4 0')[1], ['Q', 3, -1, 4, 0]);
      expect(
          segments('M1 2c1 2 3 4 5 6s1 2 3 4')[1], ['C', 8, 10, 7, 10, 9, 12]);
      expect(segments('M1 1q1 2 3 4t5 6')[1], ['Q', 6, 7, 9, 11]);
      expect(segments('M0 0Q1 1 2 0L3 0T4 0')[2], ['Q', 3, 0, 4, 0]);
    });

    test('packed arc flags, scientific notation and compact decimals', () {
      expect(segments('M0 0a5 5 0 015 5'), segments('M0 0a5 5 0 0 1 5 5'));
      expect(segments('M0 0a5 5 0 015 5').single, ['A', 5, 5, 0, 0, 1, 5, 5]);
      final raw = parsePath('M1e1 -2E-1L.5.25').single;
      expect(raw.x0, 10);
      expect(raw.y0, -0.2);
      expect(raw.segs.single.values, [0.5, 0.25]);
    });

    test('close resets current point and later drawing opens a new subpath',
        () {
      final paths = parsePath('M0 0h2zl1 1');
      expect(paths, hasLength(2));
      expect(paths.first.closed, isTrue);
      expect(paths.last.x0, 0);
      expect(paths.last.y0, 0);
      expect(paths.last.segs.single.values, [1, 1]);
      expect(parsePath('M4 6h16M4 12h16M4 18h16'), hasLength(3));
      expect(parsePath('M5 5'), isEmpty);
      expect(parsePath('M5 5Z'), isEmpty);
      expect(parsePath(''), isEmpty);
    });

    test('malformed input terminates with a deterministic FormatException', () {
      for (final bad in [
        'L1 1',
        'M1',
        'M0 0A5 5 0 2 0 1 1',
        'M0 0K1 1',
        'M0 0L',
        'M0 0Z1',
        'M0 0L1e 0',
        'M0 0L1e999 0',
        'M0 0C1 2 3',
        'M0 0A1 1 0 01',
        'Z',
      ]) {
        expect(() => parsePath(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('normalization', () {
    test('line controls and GL8 length are exact', () {
      final p = iconToCubics('M0 0L3 4').single;
      expect(segCount(p), 1);
      expect(p.pts, [0, 0, 1, 4 / 3, 2, 8 / 3, 3, 4]);
      expect(arcLength(p), closeTo(5, 1e-12));
    });

    test('quadratic degree elevation preserves the curve', () {
      final p = iconToCubics('M0 0Q1 1 2 0').single;
      expect(p.pts[2], closeTo(2 / 3, 1e-12));
      expect(p.pts[4], closeTo(4 / 3, 1e-12));
      for (final t in [0.25, 0.5, 0.75]) {
        final u = 1 - t;
        final bx = 3 * u * u * t * p.pts[2] +
            3 * u * t * t * p.pts[4] +
            t * t * t * p.pts[6];
        final by = 3 * u * u * t * p.pts[3] +
            3 * u * t * t * p.pts[5] +
            t * t * t * p.pts[7];
        expect(bx, closeTo(2 * u * t + 2 * t * t, 1e-12));
        expect(by, closeTo(2 * u * t, 1e-12));
      }
    });

    test('circle is four smooth closed cubics at faithful radius', () {
      final p = iconToCubics([
        const IconNode('circle', {'cx': 12, 'cy': 12, 'r': 10}),
      ]).single;
      expect(KAPPA, closeTo(0.5523, 0.00005));
      expect(p.closed, isTrue);
      expect(segCount(p), 4);
      expect(arcLength(p), closeTo(20 * math.pi, 0.05));
      expect(detectCorners(p), isEmpty);
      final pts = resamplePath(p);
      for (var i = 0; i < pts.length; i += 2) {
        expect(distance(pts[i] - 12, pts[i + 1] - 12), closeTo(10, 0.005));
      }
    });

    test('arcs follow SVG F.6 radius correction and degeneracies', () {
      final quarter = iconToCubics('M0 0A5 5 0 0 1 5 5').single;
      expect(segCount(quarter), 1);
      expect(quarter.pts.sublist(6), [5, 5]);
      expect(arcLength(quarter), closeTo(math.pi * 2.5, 0.005));
      final half = iconToCubics('M0 0A1 1 0 0 0 4 0').single;
      expect(segCount(half), 2);
      expect(arcLength(half), closeTo(math.pi * 2, 0.005));
      expect(arcLength(iconToCubics('M0 0A0 5 0 0 1 4 0').single),
          closeTo(4, 1e-9));
      expect(iconToCubics('M0 0A5 5 0 1 1 0 0'), isEmpty);
      for (final flags in ['0 0', '0 1', '1 0', '1 1']) {
        final p = iconToCubics('M2 3A-5 -8 37 $flags 9 7').single;
        expect(p.pts.every((v) => v.isFinite), isTrue);
        expect(p.pts.sublist(p.pts.length - 2), [9, 7]);
      }
    });

    test('all basic nodes lower with topology and numeric attribute fallback',
        () {
      final paths = iconToCubics([
        const IconNode('line', {'x1': 0, 'y1': 0, 'x2': '3', 'y2': '4'}),
        const IconNode('path', {'d': 'M4 6h16'}),
        const IconNode('ellipse', {'cx': 4, 'cy': 3, 'rx': 2, 'ry': 1}),
        const IconNode('rect', {'width': 8, 'height': 8}),
        const IconNode('polygon', {'points': '0,0 4,0 4,4'}),
        const IconNode('polyline', {'points': '0 0\n4 0\t4 4'}),
        const IconNode('line', {'x1': null, 'y1': 'bad', 'x2': 1}),
      ]);
      expect(paths.map((p) => p.closed),
          [false, false, true, true, true, false, false]);
      expect(arcLength(paths.first), closeTo(5, 1e-12));
      expect(segCount(paths[2]), 4);
      expect(detectCorners(paths[3]), [0, 1, 2, 3]);
      expect(segCount(paths[4]), 3);
      expect(arcLength(paths[4]), closeTo(8 + math.sqrt(32), 1e-9));
      expect(segCount(paths[5]), 2);
    });

    test('rounded rect copies missing radius and clamps to side lengths', () {
      final a = iconToCubics([
        const IconNode('rect', {'width': 18, 'height': 18, 'rx': 2})
      ]).single;
      final b = iconToCubics([
        const IconNode('rect', {'width': 18, 'height': 18, 'ry': 2})
      ]).single;
      expect(a.pts, b.pts);
      expect(detectCorners(a), isEmpty);
      expect(arcLength(a), closeTo(56 + 4 * math.pi, 0.05));
      final c = iconToCubics([
        const IconNode('rect', {'width': 4, 'height': 2, 'rx': 999})
      ]).single;
      expect(segCount(c), 4);
      expect(detectCorners(c), isEmpty);
    });

    test('degenerate primitives disappear and runtime inputs are checked', () {
      expect(
          iconToCubics([
            const IconNode('line', {}),
            const IconNode('circle', {'r': 0}),
            const IconNode('ellipse', {'rx': -1, 'ry': 2}),
            const IconNode('rect', {'width': -1, 'height': 2}),
            const IconNode('polyline', {'points': ''}),
          ]),
          isEmpty);
      for (final input in [
        42,
        {'d': 'M0 0L1 1'},
        <Object>['path']
      ]) {
        expect(() => iconToCubics(input), throwsArgumentError);
      }
      expect(() => iconToCubics([const IconNode('text', {})]),
          throwsArgumentError);
      expect(
          () => iconToCubics([
                const IconNode('polygon', {'points': '0 x'})
              ]),
          throwsFormatException);
    });
  });

  group('anchored arc-length resampling', () {
    test('open zigzag pins endpoints and all corners bit-exactly', () {
      final p = iconToCubics('M0 0h4v4h4v-4').single;
      expect(detectCorners(p), [1, 2, 3]);
      final pts = resamplePath(p);
      expect(pts, hasLength(128));
      for (final xy in [
        (0.0, 0.0),
        (4.0, 0.0),
        (4.0, 4.0),
        (8.0, 4.0),
        (8.0, 0.0)
      ]) {
        expect(hasPoint(pts, xy.$1, xy.$2), isTrue);
      }
      expect(() => resamplePath(p, 4), throwsArgumentError);
    });

    test('circle chords are equidistant without a duplicated endpoint', () {
      final p = iconToCubics([
        const IconNode('circle', {'r': 10})
      ]).single;
      final pts = resamplePath(p);
      final gaps = [
        for (var i = 0; i < 64; i++)
          distance(pts[2 * ((i + 1) % 64)] - pts[2 * i],
              pts[2 * ((i + 1) % 64) + 1] - pts[2 * i + 1]),
      ];
      final mean = gaps.reduce((a, b) => a + b) / gaps.length;
      for (final g in gaps) {
        expect(g, closeTo(mean, mean * 0.005));
      }
      expect(pts.sublist(0, 2), isNot(pts.sublist(126)));
    });

    test('closed square sampling is intrinsic to corners, not the M point', () {
      final a = resamplePath(iconToCubics('M2 2H22V22H2Z').single);
      final b = resamplePath(iconToCubics('M12 2H22V22H2V2Z').single);
      for (var i = 0; i < 64; i++) {
        expect(b[2 * i], closeTo(a[2 * ((i + 16) % 64)], 1e-10));
        expect(b[2 * i + 1], closeTo(a[2 * ((i + 16) % 64) + 1], 1e-10));
      }
      for (final xy in [(2.0, 2.0), (22.0, 2.0), (22.0, 22.0), (2.0, 22.0)]) {
        expect(hasPoint(b, xy.$1, xy.$2), isTrue);
      }
    });

    test('zero-length cubics and point paths fill without NaN', () {
      for (final pts in [
        <double>[5, 5],
        <double>[5, 5, 5, 5, 5, 5, 5, 5]
      ]) {
        final p = CubicPath(Float64List.fromList(pts), closed: false);
        expect(resamplePath(p, 8), List<double>.filled(16, 5));
      }
      final mixed = iconToCubics('M0 0C0 0 0 0 0 0L4 0L4 4').single;
      expect(detectCorners(mixed), [2]);
      expect(resamplePath(mixed, 8).every((v) => v.isFinite), isTrue);
    });

    test('validates sample counts, cubic chains and finite thresholds', () {
      final p = iconToCubics('M0 0L1 1').single;
      for (final n in [0, 1, -1]) {
        expect(() => resamplePath(p, n), throwsArgumentError);
      }
      expect(() => resamplePath(p, 8, double.nan), throwsArgumentError);
      expect(() => resamplePath(CubicPath(Float64List(0), closed: false)),
          throwsArgumentError);
      expect(() => resamplePath(CubicPath(Float64List(4), closed: false)),
          throwsArgumentError);
      expect(
          () => resamplePath(
              CubicPath(Float64List.fromList([double.nan, 0]), closed: false)),
          throwsArgumentError);
      expect(
          resampleIcon([
            const IconNode('path', {'d': 'M0 0L1 1'}),
            const IconNode('circle', {'r': 2})
          ], 8)
              .map((s) => (s.pts.length, s.closed, s.hole)),
          [(16, false, false), (16, true, false)]);
    });
  });

  group('serialization and fitting', () {
    test('flight format uses JS-compatible negative half rounding and Z flags',
        () {
      expect(
          serialize([
            Float64List.fromList([-0.125, -0.005, 1.125, 2])
          ], [
            true
          ]),
          'M-0.12 0L1.13 2Z');
      expect(
          serialize([
            Float64List.fromList([0, 0, 1, 1])
          ]),
          'M0 0L1 1');
      expect(serialize([]), '');
    });

    test('canonical output is four-decimal stable with exact JS half rounding',
        () {
      final p = CubicPath(
          Float64List.fromList([-0.00005, 0, -0.12345, 1, 2, 3, 4, 5]),
          closed: true);
      expect(cubicsToPathD([p]), 'M0 0C-0.1234 1 2 3 4 5Z');
      final eye = iconToCubics(
          'M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0');
      final d = cubicsToPathD(eye);
      final nudged = [
        for (final p in eye)
          CubicPath(
              Float64List.fromList(
                  [for (final v in p.pts) v * (1 + 2.220446049250313e-16)]),
              closed: p.closed),
      ];
      expect(cubicsToPathD(nudged), d);
      expect(RegExp(r'\d\.\d{5,}').hasMatch(d), isFalse);
    });

    test('canonical round trips respect the half quantization-step bound', () {
      for (final d in [
        'M20 6 9 17l-5-5',
        'M0 0C0 1 1 1 1 0S2 -1 2 0',
        'M0 0A5 5 0 0 1 5 5',
        'M0 0h4v4h-4z'
      ]) {
        final a = iconToCubics(d);
        final b = iconToCubics(cubicsToPathD(a));
        expect(b, hasLength(a.length));
        for (var j = 0; j < a.length; j++) {
          expect(b[j].closed, a[j].closed);
          for (var i = 0; i < a[j].pts.length; i++) {
            expect(b[j].pts[i], closeTo(a[j].pts[i], 5e-5));
          }
        }
      }
    });

    test('viewBox number, string and numeric tuple are equivalent', () {
      const d = 'M0 0L32 32';
      final a = fitIcon(d, 32);
      expect(fitIcon(d, '0 0 32 32'), a);
      expect(fitIcon(d, '0,0,32,32'), a);
      expect(fitIcon(d, [0, 0, 32, 32]), a);
      expect(fitIcon(d, const ViewBox(0, 0, 32, 32)), a);
      expect(iconToCubics(a).single.pts.sublist(6), [24, 24]);
      expect(
          iconToCubics(fitIcon('M100 0L148 24', [100, 0, 48, 24])).single.pts,
          [0, 6, 8, 10, 16, 14, 24, 18]);
      expect(iconToCubics(fitIcon(d, 32, 48)).single.pts.sublist(6), [48, 48]);
    });

    test('invalid viewBoxes, grids and output coordinates throw clearly', () {
      for (final vb in [
        '0 0 24',
        '0 0 0 24',
        'a b c d',
        0,
        -24,
        double.infinity,
        [0, 0, 24, double.infinity],
        Object()
      ]) {
        expect(() => fitIcon('M0 0L1 1', vb), throwsArgumentError);
      }
      for (final grid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => fitIcon('M0 0L1 1', 24, grid), throwsArgumentError);
      }
      expect(
          () => serialize([
                Float64List.fromList([double.nan, 0])
              ]),
          throwsArgumentError);
      expect(() => serialize([Float64List(3)]), throwsArgumentError);
    });
  });
}
