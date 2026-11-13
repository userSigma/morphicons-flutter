import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/src/core/plan.dart';
import 'package:morphicons/src/core/region.dart';
import 'package:morphicons/src/core/types.dart';
import 'package:morphicons/src/region/region.dart';

const crossRects = <IconNode>[
  IconNode('rect',
      {'x': 10, 'y': 4, 'width': 4, 'height': 16, 'fill': 'currentColor'}),
  IconNode('rect',
      {'x': 4, 'y': 10, 'width': 16, 'height': 4, 'fill': 'currentColor'}),
];
const crossOutline = <IconNode>[
  IconNode('path',
      {'d': 'M10 4h4v6h6v4h-6v6h-4v-6H4v-4h6z', 'fill': 'currentColor'}),
];
const ring = <IconNode>[
  IconNode('path', {
    'd':
        'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20zM12 6a6 6 0 1 1 0 12a6 6 0 1 1 0-12z',
    'fill-rule': 'evenodd',
    'fill': 'currentColor',
  }),
];
const disc = <IconNode>[
  IconNode('circle', {'cx': 12, 'cy': 12, 'r': 10, 'fill': 'currentColor'}),
];
const play = <IconNode>[
  IconNode('path', {'d': 'M7 4l13 8-13 8z', 'fill': 'currentColor'}),
];
const pause = <IconNode>[
  IconNode('rect',
      {'x': 5, 'y': 4, 'width': 5, 'height': 16, 'fill': 'currentColor'}),
  IconNode('rect',
      {'x': 14, 'y': 4, 'width': 5, 'height': 16, 'fill': 'currentColor'}),
];
const lucideX = <IconNode>[
  IconNode('path', {'d': 'M18 6 6 18'}),
  IconNode('path', {'d': 'm6 6 12 12'}),
];
List<IconNode> evenodd(String d) => [
      IconNode(
          'path', {'d': d, 'fill-rule': 'evenodd', 'fill': 'currentColor'}),
    ];
String circle(double x, double y, double r) =>
    'M$x ${y - r}a$r $r 0 1 0 0 ${2 * r}a$r $r 0 1 0 0 ${-2 * r}z';
String starPath(double outer, double inner, double turn) {
  final d = StringBuffer();
  for (var i = 0; i < 10; i++) {
    final a = turn + i * math.pi / 5 - math.pi / 2;
    final r = i.isOdd ? inner : outer;
    d.write(
        '${i == 0 ? 'M' : 'L'}${(12 + r * math.cos(a)).toStringAsFixed(4)} ${(12 + r * math.sin(a)).toStringAsFixed(4)}');
  }
  return '${d}Z';
}

// Independent rendering of the public plan contract, including borrowed frames.
List<Float64List> frameAt(MorphPlan plan, double t) => plan.items.map((it) {
      final scale = math.exp(it.lnSigma * t);
      final c = math.cos(it.theta * t) * scale;
      final s = math.sin(it.theta * t) * scale;
      double x, y;
      final block = it.block;
      if (block == null) {
        x = it.ca[0] + (it.cb[0] - it.ca[0]) * t;
        y = it.ca[1] + (it.cb[1] - it.ca[1]) * t;
      } else {
        final ox = block.off[0], oy = block.off[1];
        x = it.ca[0] + block.drift[0] * t + ox * c - oy * s - ox;
        y = it.ca[1] + block.drift[1] * t + ox * s + oy * c - oy;
      }
      final m = it.half == null ? t : (2 * t - it.half!).clamp(0.0, 1.0);
      final out = Float64List(2 * plan.n);
      for (var i = 0; i < out.length; i += 2) {
        final px = it.aC[i] + (it.bT[i] - it.aC[i]) * m;
        final py = it.aC[i + 1] + (it.bT[i + 1] - it.aC[i + 1]) * m;
        out[i] = x + px * c - py * s;
        out[i + 1] = y + px * s + py * c;
      }
      return out;
    }).toList();

int windingAt(List<Float64List> contours, double x, double y) {
  var w = 0;
  for (final p in contours) {
    final n = p.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final yi = p[2 * i + 1], yj = p[2 * j + 1];
      if ((yj <= y) != (yi <= y)) {
        final xc = p[2 * j] + (y - yj) * (p[2 * i] - p[2 * j]) / (yi - yj);
        if (xc > x) w += yi > yj ? 1 : -1;
      }
    }
  }
  return w;
}

void neverNegative(MorphPlan p) {
  for (var t = 0.0; t <= 1; t += .125) {
    final f = frameAt(p, t);
    for (var y = .37; y < 24; y += .5) {
      for (var x = .61; x < 24; x += .5) {
        expect(windingAt(f, x, y), greaterThanOrEqualTo(0),
            reason: 'negative winding at ($x,$y), t=$t');
      }
    }
  }
}

void endsAs(MorphPlan p, IconInput target) {
  final end = frameAt(p, 1);
  final expected =
      resampleRegion(toRegion(target), p.n).map((s) => s.pts).toList();
  for (var y = .37; y < 24; y += .5) {
    for (var x = .61; x < 24; x += .5) {
      expect(windingAt(end, x, y) != 0, windingAt(expected, x, y) != 0);
    }
  }
}

void main() {
  group('paint helpers', () {
    test('paint and solid preserve historical strokes and omit duotone fills',
        () {
      expect(paintOf('M0 0h4'), IconPaint.stroke);
      expect(paintOf(lucideX), IconPaint.stroke);
      expect(paintOf(disc), IconPaint.fill);
      expect(painted(null), isFalse);
      expect(painted(' NONE '), isFalse);
      expect(painted('currentColor'), isTrue);
      expect(translucent({'opacity': '.2'}), isTrue);
      expect(translucent({'fill-opacity': '.4foo'}), isTrue);
      expect(translucent({'opacity': '.5'}), isFalse);
      final duotone = [
        const IconNode('path',
            {'d': 'M4 4h16v16H4z', 'opacity': '.2', 'fill': 'currentColor'}),
        const IconNode('path', {'d': 'M8 8h8v8H8z', 'fill': 'currentColor'}),
      ];
      expect((solid(duotone) as List<IconNode>).length, 1);
      expect(identical(solid(lucideX), lucideX), isTrue);
      expect(signedArea(regionContours(duotone).single), closeTo(64, .001));
    });
    test('point helpers cover zero segments, concavity and winding', () {
      final p = Float64List.fromList([0, 0, 4, 0, 4, 4, 0, 4]);
      expect(inside(2, 2, p), isTrue);
      expect(inside(5, 2, p), isFalse);
      expect(signedArea(p), 16);
      expect(distSeg(3, 4, 0, 0, 0, 0), 5);
      expect(distSeg(3, 4, 0, 0, 6, 0), 4);
    });
  });
  group('normalization', () {
    test('overlapping rectangles equal one outline with recovered corners', () {
      expect(toRegion(crossRects).single.attrs['d'],
          toRegion(crossOutline).single.attrs['d']);
      final c = regionContours(crossRects).single;
      expect(c.length, 24);
      expect(signedArea(c), closeTo(112, .001));
    });
    test('evenodd, nonzero, opposite winding and per-element union', () {
      final a = regionContours(ring).map(signedArea).toList()..sort();
      expect(a.length, 2);
      expect(a.first, closeTo(-math.pi * 36, .5));
      expect(a.last, closeTo(math.pi * 100, .5));
      // Off-grid inner boundary avoids the source SDF's zero-width grid seam.
      const same = 'M2 2h20v20H2zM6.04 6.04h12v12H6.04z';
      expect(regionContours(evenodd(same)).length, 2);
      expect(
          regionContours([
            const IconNode('path', {'d': same, 'fill': 'currentColor'})
          ]).length,
          1);
      final cs = regionContours([
        const IconNode('path', {
          'd': 'M3 3h12v12H3z',
          'fill-rule': 'evenodd',
          'fill': 'currentColor'
        }),
        const IconNode('path', {
          'd': 'M9 9h12v12H9z',
          'fill-rule': 'evenodd',
          'fill': 'currentColor'
        }),
      ]);
      expect(windingAt(cs, 12, 12), 1);
    });
    test('touching hole tips remain positive outer islands', () {
      final lens = [
        const IconNode('path', {
          'fill': 'currentColor',
          'd':
              'm12 10l-.94 2.06L9 13l2.06.94L12 16l.94-2.06L15 13l-2.06-.94zM12 8a5 5 0 0 0-5 5a5 5 0 0 0 5 5a5 5 0 0 0 5-5a5 5 0 0 0-5-5m0 8a3 3 0 0 1-3-3a3 3 0 0 1 3-3a3 3 0 0 1 3 3a3 3 0 0 1-3 3',
        })
      ];
      final cs = regionContours(lens);
      for (var y = .37; y < 24; y += .5) {
        for (var x = .61; x < 24; x += .5) {
          expect(windingAt(cs, x, y), greaterThanOrEqualTo(0));
        }
      }
      expect(windingAt(cs, 12.01, 13.01), 1);
    });
    test('whole-unit junctions never double or negatively wind', () {
      final screen = [
        const IconNode('path', {
          'fill': 'currentColor',
          'd':
              'M13 15a1 1 0 1 0-2 0zM6 6V5H5v1zm12 0h1V5h-1zm0 9v1h1v-1zM6 15H5v1h1zM4 3V2a1 1 0 0 0-1 1zm16 0h1a1 1 0 0 0-1-1zm0 3v1a1 1 0 0 0 1-1zM4 6H3a1 1 0 0 0 1 1zm0 8a1 1 0 1 0 0 2zm16 2a1 1 0 1 0 0-2zm-8-1h-1v3h2v-3zM6 6v1h12V5H6zm12 0h-1v9h2V6zm0 9v-1H6v2h12zM6 15h1V6H5v9zM4 3v1h16V2H4zm16 0h-1v3h2V3zm0 3V5H4v2h16zM4 6h1V3H3v3zm9.5 13.5h-1a.5.5 0 0 1-.5.5v2a2.5 2.5 0 0 0 2.5-2.5zM12 21v-1a.5.5 0 0 1-.5-.5h-2A2.5 2.5 0 0 0 12 22zm-1.5-1.5h1a.5.5 0 0 1 .5-.5v-2a2.5 2.5 0 0 0-2.5 2.5zM12 18v1a.5.5 0 0 1 .5.5h2A2.5 2.5 0 0 0 12 17zm-8-3v1h16v-2H4z',
        })
      ];
      final cs = regionContours(screen);
      for (var y = .05; y < 24; y += .1) {
        for (var x = .07; x < 24; x += .1) {
          expect(windingAt(cs, x, y), inInclusiveRange(0, 1));
        }
      }
    });
    test('round caps and joins union crossing strokes', () {
      final cs = regionContours(lucideX);
      expect(cs.length, 1);
      expect(signedArea(cs.single), inExclusiveRange(68, 72));
      final dot = regionContours([
        const IconNode('path', {'d': 'M12 12h.01', 'stroke-width': 4})
      ]);
      expect(signedArea(dot.single), closeTo(math.pi * 4, .15));
    });
    test('mixed fill/stroke unions painted surfaces at inherited width', () {
      final mixed = [
        ...disc,
        const IconNode('path',
            {'d': 'M12 2v-2', 'fill': 'none', 'stroke': 'currentColor'}),
      ];
      final cs = regionContours(mixed);
      expect(cs.length, 1);
      expect(signedArea(cs.single), greaterThan(math.pi * 100));
      final wallet = [
        const IconNode('path',
            {'d': 'M3 7h18v13H3z', 'fill': 'none', 'stroke': 'currentColor'}),
        const IconNode(
            'circle', {'cx': 16.5, 'cy': 13.5, 'r': 1, 'fill': 'currentColor'}),
      ];
      expect(identical(regionOf(wallet, 2), regionOf(wallet, 6)), isFalse);
      expect(identical(regionOf(wallet, 2), regionOf(wallet, 2)), isTrue);
      expect(identical(regionOf(ring, 2), regionOf(ring, 6)), isTrue);
    });
    test('regions are idempotent, content-cached and plans reused', () {
      final a = toRegion(disc);
      expect(isRegion(a), isTrue);
      expect(identical(toRegion(a), a), isTrue);
      expect(a.single.attrs['fill-rule'], 'nonzero');
      final copy = disc.map((el) => IconNode(el.tag, {...el.attrs})).toList();
      expect(identical(regionOf(disc, 2), regionOf(copy, 2)), isTrue);
      expect(identical(regionPlan(disc, play), regionPlan(copy, play)), isTrue);
    });
    test('empty visible surface has an explicit diagnostic', () {
      expect(() => toRegion(<IconNode>[]), throwsA(isA<StateError>()));
    });
  });
  group('topology-aware plans', () {
    test('equivalent cross constructions stay stationary', () {
      final p = regionPlan(crossRects, crossOutline);
      final a = frameAt(p, 0);
      for (final t in [.25, .5, .75, 1.0]) {
        final f = frameAt(p, t);
        for (var k = 0; k < f.length; k++) {
          for (var i = 0; i < f[k].length; i++) {
            expect(f[k][i], closeTo(a[k][i], 1e-9));
          }
        }
      }
    });
    test('ring to disc closes only its hole on the first half', () {
      final p = regionPlan(ring, disc);
      final k = p.items.indexWhere((it) => it.hole);
      expect(p.items.where((it) => it.hole).length, 1);
      expect(p.items[k].half, 0);
      final a = [0.0, .25, .5, 1.0]
          .map((t) => signedArea(frameAt(p, t)[k]).abs())
          .toList();
      expect(a[0], greaterThan(100));
      expect(a[1], inExclusiveRange(0, a[0]));
      expect(a[2], lessThan(1e-9));
      expect(a[3], lessThan(1e-9));
      neverNegative(p);
      endsAs(p, disc);
    });
    test('disc to ring grows its hole on the second half', () {
      final p = regionPlan(disc, ring);
      final k = p.items.indexWhere((it) => it.hole);
      expect(p.items[k].half, 1);
      expect(signedArea(frameAt(p, .5)[k]).abs(), lessThan(1e-9));
      neverNegative(p);
      endsAs(p, ring);
    });
    test('play to pause divides an unholed contour', () {
      final p = regionPlan(play, pause);
      expect(p.items.length, 2);
      expect(p.items.every((it) => !it.hole && it.closed), isTrue);
      neverNegative(p);
      endsAs(p, pause);
    });
    test('holed pieces never duplicate and disappearing pieces retain holes',
        () {
      final two = evenodd(
          '${circle(6, 12, 5)}${circle(6, 12, 2.5)}${circle(18, 12, 5)}${circle(18, 12, 2.5)}');
      final one = evenodd('${circle(6, 12, 5)}${circle(6, 12, 2.5)}');
      for (final pair in [
        [two, one],
        [one, two]
      ]) {
        final p = regionPlan(pair[0], pair[1]);
        neverNegative(p);
        endsAs(p, pair[1]);
      }
      final bell = [
        const IconNode(
            'circle', {'cx': 12, 'cy': 11, 'r': 8, 'fill': 'currentColor'}),
        const IconNode(
            'circle', {'cx': 12, 'cy': 21.5, 'r': 1.5, 'fill': 'currentColor'}),
      ];
      for (final pair in [
        [bell, ring],
        [ring, bell]
      ]) {
        final p = regionPlan(pair[0], pair[1]);
        neverNegative(p);
        endsAs(p, pair[1]);
      }
    });
    test('turned star-ring hole borrows its outer similarity and winding', () {
      List<IconNode> star(double turn) =>
          evenodd('${starPath(11, 5, turn)}${starPath(8, 3.4, turn)}');
      for (final turn in [math.pi / 5, .3]) {
        final p = regionPlan(star(0), star(turn));
        final outer = p.items.firstWhere((it) => !it.hole);
        final hole = p.items.firstWhere((it) => it.hole);
        expect(hole.theta, outer.theta);
        expect(hole.lnSigma, outer.lnSigma);
        neverNegative(p);
        endsAs(p, star(turn));
        for (final t in [0.0, .25, .5, .75, 1.0]) {
          final f = frameAt(p, t);
          for (var k = 0; k < f.length; k++) {
            expect(p.items[k].hole ? -signedArea(f[k]) : signedArea(f[k]),
                greaterThanOrEqualTo(-1e-9));
          }
        }
      }
    });
    test('holes uncovered by outer residual blend close and open separately',
        () {
      final webcam = [
        ...evenodd('${circle(12, 10, 8)}${circle(12, 10, 7)}'),
        const IconNode('rect', {
          'x': 11.5,
          'y': 17.5,
          'width': 1,
          'height': 3,
          'fill': 'currentColor'
        }),
        const IconNode('rect', {
          'x': 3,
          'y': 19.5,
          'width': 18,
          'height': 1.5,
          'fill': 'currentColor'
        }),
      ];
      final target = evenodd('${circle(12, 12, 9)}${circle(12, 12, 7.5)}');
      for (final pair in [
        [webcam, target],
        [target, webcam]
      ]) {
        final p = regionPlan(pair[0], pair[1]);
        expect(p.items.where((it) => it.hole).map((it) => it.half).toList(),
            [0, 1]);
        neverNegative(p);
        endsAs(p, pair[1]);
      }
    });
    test('large hole assignment uses bounded greedy fallback', () {
      List<IconNode> grid(bool shift) {
        final d = StringBuffer('M1 1h22v22H1z');
        for (var k = 0; k < 9; k++) {
          final x = 4 + (k % 3) * 8 + (shift ? .05 : 0);
          final y = 4 + (k ~/ 3) * 8;
          d.write(circle(x.toDouble(), y.toDouble(), 1));
        }
        return evenodd(d.toString());
      }

      final p = regionPlan(grid(false), grid(true));
      expect(p.items.where((it) => it.hole).length, 9);
      expect(p.items.every((it) => it.half == null), isTrue);
      neverNegative(p);
      endsAs(p, grid(true));
    });
    test('nonoverlapping holes close then open without sweeping', () {
      final top = evenodd('M3 3h18v18H3zM5 5h14v2H5z');
      final side = evenodd('M3 3h18v18H3zM5 10h2v9H5z');
      final p = regionPlan(top, side);
      final halves = p.items
          .where((it) => it.hole)
          .map((it) => it.half)
          .toList()
        ..sort((a, b) => a!.compareTo(b!));
      expect(halves, [0, 1]);
      neverNegative(p);
      endsAs(p, side);
    });
    test('hole parent is determined by contour rather than centroid island',
        () {
      List<IconNode> camera(double w, double lens) => [
            ...evenodd('M2 5h20v15H2z${circle(12, 12.5, w)}'),
            IconNode('circle',
                {'cx': 12, 'cy': 12.5, 'r': lens, 'fill': 'currentColor'}),
          ];
      final p = regionPlan(camera(6, 3.5), camera(5, 2.5));
      final hole = p.items.firstWhere((it) => it.hole);
      final outers = p.items.where((it) => !it.hole).toList()
        ..sort(
            (a, b) => signedArea(b.a).abs().compareTo(signedArea(a.a).abs()));
      expect(hole.ca, outers.first.ca);
      neverNegative(p);
      endsAs(p, camera(5, 2.5));
    });
    test('vanishing holes follow residual deformation', () {
      final slab = evenodd('M3 3h15v14H3zM8 12h5v4H8z');
      final arch = evenodd('M4 2h14v18h-4V9H8v11H4z');
      for (final pair in [
        [slab, arch],
        [arch, slab]
      ]) {
        final p = regionPlan(pair[0], pair[1]);
        neverNegative(p);
        endsAs(p, pair[1]);
      }
    });
    test('matched holes split if they sweep over a closing hole', () {
      final two = evenodd('M3 3h18v18H3zM5 5h7v14H5zM13 5h2v14h-2z');
      final one = evenodd('M3 3h18v18H3zM5 5h14v14H5z');
      for (final pair in [
        [two, one],
        [one, two]
      ]) {
        final p = regionPlan(pair[0], pair[1]);
        expect(p.items.any((it) => it.hole && it.half == null), isFalse);
        neverNegative(p);
        endsAs(p, pair[1]);
      }
    });
    test('best circular cut that folds falls back to a simple outer', () {
      // Heroicons plus-20-solid after the source adapter's viewBox transform.
      final plus = [
        const IconNode('path', {
          'fill': 'currentColor',
          'd':
              'M12.9 5.7C12.9 5.2029 12.4971 4.8 12 4.8C11.5029 4.8 11.1 5.2029 11.1 5.7C11.1 7.5 11.1 9.3 11.1 11.1C9.3 11.1 7.5 11.1 5.7 11.1C5.2029 11.1 4.8 11.5029 4.8 12C4.8 12.4971 5.2029 12.9 5.7 12.9C7.5 12.9 9.3 12.9 11.1 12.9C11.1 14.7 11.1 16.5 11.1 18.3C11.1 18.7971 11.5029 19.2 12 19.2C12.4971 19.2 12.9 18.7971 12.9 18.3C12.9 16.5 12.9 14.7 12.9 12.9C14.7 12.9 16.5 12.9 18.3 12.9C18.7971 12.9 19.2 12.4971 19.2 12C19.2 11.5029 18.7971 11.1 18.3 11.1C16.5 11.1 14.7 11.1 12.9 11.1C12.9 9.3 12.9 7.5 12.9 5.7Z',
        })
      ];
      final arrow = [
        const IconNode('path', {
          'fill': 'none',
          'stroke': 'currentColor',
          'stroke-width': 1.5,
          'd': 'M12 19.5v-15m0 0l-6.75 6.75M12 4.5l6.75 6.75',
        })
      ];
      final p = regionPlan(plus, arrow);
      neverNegative(p);
      endsAs(p, arrow);
    });
    test('adaptive 128 sampling and mixed-density endpoint preservation', () {
      final d = StringBuffer();
      for (var k = 0; k < 96; k++) {
        final a = k * math.pi / 48, r = k % 4 < 2 ? 10 : 8;
        d.write(
            '${k == 0 ? 'M' : 'L'}${(12 + r * math.cos(a)).toStringAsFixed(3)} ${(12 + r * math.sin(a)).toStringAsFixed(3)}');
      }
      d.write('Z');
      final gear = [
        IconNode('path', {'d': d.toString(), 'fill': 'currentColor'})
      ];
      expect(resampleRegion(toRegion(gear)).first.pts.length, 256);
      final p = regionPlan(play, gear);
      expect(p.n, 128);
      final base = resampleRegion(toRegion(play)).single.pts;
      final start = frameAt(p, 0).single;
      for (var i = 0; i < 256; i += 4) {
        expect(start[i], closeTo(base[i ~/ 2], 1e-9));
        expect(start[i + 1], closeTo(base[i ~/ 2 + 1], 1e-9));
      }
    });
    test('stroke interruptions support strings and sampled regions', () {
      for (final from in <Object>[
        'M4 6h16M4 12h16',
        resampleRegion(toRegion(ring))
      ]) {
        final p = regionPlanFrom(from, pause);
        for (final t in [0.0, .5, 1.0, 1.2]) {
          expect(
              frameAt(p, t).expand((p) => p).every((v) => v.isFinite), isTrue);
        }
        final end = frameAt(p, 1);
        for (var k = 0; k < end.length; k++) {
          for (var i = 0; i < end[k].length; i++) {
            expect(end[k][i], closeTo(p.items[k].bO[i], 1e-9));
          }
        }
      }
    });
  });
}
