import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/src/core/interpolate.dart';
import 'package:morphicons/src/core/plan.dart';
import 'package:morphicons/src/core/resample.dart';
import 'package:morphicons/src/core/types.dart';

Float64List pts(List<double> values) => Float64List.fromList(values);

Float64List line(double ax, double ay, double bx, double by, [int n = 64]) {
  final out = Float64List(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    out[2 * i] = ax + (bx - ax) * t;
    out[2 * i + 1] = ay + (by - ay) * t;
  }
  return out;
}

Float64List polyline(List<double> vertices, {int n = 64, bool closed = false}) {
  final count = vertices.length ~/ 2;
  final edges = closed ? count : count - 1;
  final out = Float64List(2 * n);
  for (var i = 0; i < n; i++) {
    final t = i / (closed ? n : n - 1) * edges;
    final edge = math.min(t.floor(), edges - 1);
    final u = t - edge;
    final next = (edge + 1) % count;
    out[2 * i] =
        vertices[2 * edge] + (vertices[2 * next] - vertices[2 * edge]) * u;
    out[2 * i + 1] = vertices[2 * edge + 1] +
        (vertices[2 * next + 1] - vertices[2 * edge + 1]) * u;
  }
  return out;
}

Sampled open(Float64List points) => Sampled(points, closed: false);
Sampled loop(Float64List points) => Sampled(points, closed: true);

List<Sampled> icon(String name) {
  switch (name) {
    case 'menu':
      return [
        for (final y in [6.0, 12.0, 18.0]) open(line(4, y, 20, y))
      ];
    case 'x':
      return [open(line(18, 6, 6, 18)), open(line(6, 6, 18, 18))];
    case 'plus':
      return [open(line(5, 12, 19, 12)), open(line(12, 5, 12, 19))];
    case 'arrow-right':
      return [
        open(line(5, 12, 19, 12)),
        open(polyline([12, 5, 19, 12, 12, 19]))
      ];
    case 'arrow-down':
      return [
        open(line(12, 5, 12, 19)),
        open(polyline([19, 12, 12, 19, 5, 12]))
      ];
    case 'check':
      return [
        open(polyline([20, 6, 9, 17, 4, 12]))
      ];
    default:
      throw ArgumentError(name);
  }
}

double maxDiff(Float64List a, Float64List b) {
  expect(a.length, b.length);
  var error = 0.0;
  for (var i = 0; i < a.length; i++) {
    error = math.max(error, (a[i] - b[i]).abs());
  }
  return error;
}

void endpoints(MorphPlan plan) {
  final out = allocOutputs(plan);
  for (final interpolate in [interpPolar, interpLinear]) {
    interpolate(plan, 0, out);
    for (var k = 0; k < plan.items.length; k++) {
      expect(maxDiff(out[k], plan.items[k].a), lessThan(1e-9));
    }
    interpolate(plan, 1, out);
    for (var k = 0; k < plan.items.length; k++) {
      expect(maxDiff(out[k], plan.items[k].bO), lessThan(1e-9));
    }
  }
}

double exhaustiveSurjection(List<List<double>> costs) {
  var best = double.infinity;
  final counts = List<int>.filled(costs[0].length, 0);
  void walk(int row, double cost) {
    if (row == costs.length) {
      if (counts.every((count) => count > 0)) best = math.min(best, cost);
      return;
    }
    for (var col = 0; col < counts.length; col++) {
      counts[col]++;
      walk(row + 1, cost + costs[row][col]);
      counts[col]--;
    }
  }

  walk(0, 0);
  return best;
}

void main() {
  group('point math and Procrustes', () {
    test('centroid, open polyline length, reversal and circular indexing', () {
      final a = pts([0, 0, 3, 0, 3, 4]);
      expect(centroid(a), [2, 4 / 3]);
      expect(polyLen(a), 7);
      expect(reversePts(a), [3, 4, 3, 0, 0, 0]);
      expect(rotatePts(a, 1), [3, 0, 3, 4, 0, 0]);
      expect(a, [0, 0, 3, 0, 3, 4]);
    });

    test('known similarity recovers rotation, scale and zero residual', () {
      final a = pts([-2, -1, 3, 0, 1, 4]);
      final b = Float64List(a.length);
      for (var i = 0; i < a.length; i += 2) {
        b[i] = 7 - 2 * a[i + 1];
        b[i + 1] = 9 + 2 * a[i];
      }
      final s = procrustes(a, b, centroid(a), centroid(b));
      expect(s.theta, closeTo(math.pi / 2, 1e-12));
      expect(s.sigma, closeTo(2, 1e-12));
      expect(s.res, lessThan(1e-7));
    });

    test('zero-energy clouds preserve the original finite floor behavior', () {
      final a = pts([2, 2, 2, 2]);
      final b = pts([5, 5, 5, 5]);
      final s = procrustes(a, b, centroid(a), centroid(b));
      expect(s.sigma, 1);
      expect(s.res, 0);
      final collapsed = procrustes(line(-1, 0, 1, 0, 2), b, [0, 0], [5, 5]);
      expect(collapsed.sigma, 1e-6);
      expect(collapsed.res, 0);
    });

    test('lambda chooses 45 degree rather than 135 degree reversal', () {
      final a = line(4, 6, 20, 6);
      final b = line(18, 6, 6, 18);
      final aligned = alignPair(a, b);
      expect(aligned.theta.abs(), closeTo(math.pi / 4, 1e-12));
      expect(aligned.res, lessThan(1e-7));
      final locked = alignPair(a, b, false, false, false);
      expect(locked.theta.abs(), closeTo(3 * math.pi / 4, 1e-12));
      expect(identical(locked.a, a), isTrue);
      expect(identical(locked.b, b), isTrue);
    });

    test('closed correspondence searches circular offsets and directions', () {
      final a = polyline([2, 2, 22, 2, 22, 22, 2, 22], closed: true);
      final b = reversePts(rotatePts(a, 11));
      final aligned = alignPair(a, b, true, true);
      expect(aligned.theta.abs(), lessThan(1e-7));
      expect(aligned.res, lessThan(1e-7));
      expect(maxDiff(aligned.a, aligned.b), lessThan(1e-9));
    });

    test('closed source to open target varies source, not open target', () {
      final a = polyline([0, 0, 5, 0, 6, 3, 0, 4], n: 16, closed: true);
      final b = rotatePts(a, 3);
      final aligned = alignPair(a, b, true, false);
      expect(identical(aligned.b, b), isTrue);
      expect(maxDiff(aligned.a, b), lessThan(1e-9));
      expect(aligned.theta.abs(), lessThan(1e-7));
    });

    test('square to diamond rotates 45 degrees with sqrt(1/2) scale', () {
      final a = loop(polyline([2, 2, 22, 2, 22, 22, 2, 22], closed: true));
      final b = loop(polyline([12, 2, 22, 12, 12, 22, 2, 12], closed: true));
      final plan = buildPlan([a], [b]);
      final it = plan.items.single;
      expect(it.theta.abs(), closeTo(math.pi / 4, 1e-7));
      expect(math.exp(it.lnSigma), closeTo(math.sqrt(0.5), 1e-7));
      expect(it.res, lessThan(1e-7));
      expect(it.closed, isTrue);
      endpoints(plan);
    });
  });

  group('matching', () {
    test('cost is centroid distance plus 0.35 times length difference', () {
      final a = line(-1, 0, 1, 0, 2);
      final b = line(1, 4, 5, 4, 2);
      expect(costMatrix([a], [b]).single.single, closeTo(5.7, 1e-12));
    });

    test('small balanced clouds receive the minimum permutation', () {
      final a = [
        pts([0, 0]),
        pts([2, 0]),
        pts([10, 0])
      ];
      final b = [
        pts([10, 0]),
        pts([0, 0]),
        pts([2, 0])
      ];
      expect(pairUp(a, b), [
        [0, 1],
        [1, 2],
        [2, 0]
      ]);
    });

    test('small surjection matches brute-force optimum in both directions', () {
      final a = [
        pts([0, 0]),
        pts([1, 0]),
        pts([9, 0]),
        pts([10, 0])
      ];
      final b = [
        pts([0, 0]),
        pts([5, 0]),
        pts([10, 0])
      ];
      final costs = costMatrix(a, b);
      for (final swap in [false, true]) {
        final pairs = swap ? pairUp(b, a) : pairUp(a, b);
        expect(pairs.length, 4);
        final targets = <int>{};
        var total = 0.0;
        for (final pair in pairs) {
          final i = pair[swap ? 1 : 0];
          final j = pair[swap ? 0 : 1];
          total += costs[i][j];
          targets.add(j);
        }
        expect(targets.length, 3);
        expect(total, exhaustiveSurjection(costs));
      }
    });

    test('greedy 12 to 3 repairs coverage using multiplicity donors', () {
      final a = [
        for (var i = 0; i < 12; i++) pts([i / 100, 0])
      ];
      final b = [
        pts([0, 0]),
        pts([50, 0]),
        pts([100, 0])
      ];
      final pairs = pairUp(a, b);
      expect(pairs.length, 12);
      expect(pairs.map((pair) => pair[0]).toSet().length, 12);
      expect(pairs.map((pair) => pair[1]).toSet().length, 3);
      expect(pairUp(b, a).map((pair) => pair[0]).toSet().length, 3);
    });

    test('greedy 9 to 9 pairs each translated path with its twin', () {
      final a = [for (var i = 0; i < 9; i++) line(i * 20, 0, i * 20 + 2, 0)];
      final b = [
        for (var i = 0; i < 9; i++) line(i * 20 + 2, 3, i * 20 + 4, 3)
      ];
      expect(pairUp(a, b), [
        for (var i = 0; i < 9; i++) [i, i]
      ]);
      final plan = buildPlan(a.map(open).toList(), b.map(open).toList());
      for (final it in plan.items) {
        expect(it.cb[0] - it.ca[0], closeTo(2, 1e-9));
        expect(it.cb[1] - it.ca[1], closeTo(3, 1e-9));
      }
    });

    test('menu to x is surjective with minimal rotations and no hybrid', () {
      final plan = buildPlan(icon('menu'), icon('x'));
      expect(plan.items.length, 3);
      expect(plan.items.map((it) => it.theta.sign).toSet().length, 2);
      for (final it in plan.items) {
        expect(it.theta.abs(), closeTo(math.pi / 4, 1e-7));
        expect(it.res, lessThan(1e-7));
        expect(it.block, isNull);
      }
    });

    test('plus to x recovers 45 degrees and the original scale', () {
      final plan = buildPlan(icon('plus'), icon('x'));
      for (final it in plan.items) {
        expect(it.theta.abs(), closeTo(math.pi / 4, 1e-7));
        expect(math.exp(it.lnSigma), closeTo(1.2122, 0.005));
        expect(it.res, lessThan(1e-7));
      }
    });
  });

  group('global hybrid and interpolation', () {
    test('arrow block shares rotation and keeps cross-part distances rigid',
        () {
      final plan = buildPlan(icon('arrow-right'), icon('arrow-down'));
      expect(plan.items.length, 2);
      expect(plan.items[0].theta, closeTo(plan.items[1].theta, 1e-7));
      for (final it in plan.items) {
        expect(it.theta.abs(), closeTo(math.pi / 2, 1e-7));
        expect(math.exp(it.lnSigma), closeTo(1, 1e-7));
        expect(it.res, lessThan(1e-6));
        expect(it.block, isNotNull);
      }
      final out = allocOutputs(plan);
      List<double> distances() => [
            for (final i in [0, plan.n ~/ 2, plan.n - 1])
              for (final j in [0, plan.n ~/ 2, plan.n - 1])
                math.sqrt(math.pow(out[0][2 * i] - out[1][2 * j], 2) +
                    math.pow(out[0][2 * i + 1] - out[1][2 * j + 1], 2)),
          ];
      interpPolar(plan, 0, out);
      final initial = distances();
      for (final t in [0.25, 0.5, 0.75]) {
        interpPolar(plan, t, out);
        final current = distances();
        for (var i = 0; i < current.length; i++) {
          expect(current[i], closeTo(initial[i], 1e-6));
        }
      }
      endpoints(plan);
    });

    for (final names in [
      ['menu', 'x'],
      ['x', 'check'],
      ['check', 'plus'],
      ['arrow-right', 'arrow-down'],
    ]) {
      test(
          '${names[0]} to ${names[1]} has exact endpoints and reuses output buffers',
          () {
        final plan = buildPlan(icon(names[0]), icon(names[1]));
        endpoints(plan);
        final out = allocOutputs(plan);
        final refs = List<Float64List>.of(out);
        final source = [
          for (final it in plan.items) Float64List.fromList(it.a)
        ];
        for (final t in [-0.1, 0.25, 0.5, 0.75, 1.1]) {
          interpPolar(plan, t, out);
          for (var k = 0; k < out.length; k++) {
            expect(identical(out[k], refs[k]), isTrue);
            expect(out[k].every((v) => v.isFinite), isTrue);
            expect(maxDiff(plan.items[k].a, source[k]), 0);
          }
        }
      });
    }

    test('closed to open flies open and preserves endpoints', () {
      final source = loop(polyline([2, 2, 22, 2, 22, 22, 2, 22], closed: true));
      final plan = buildPlan([source], icon('check'));
      expect(plan.items.single.closed, isFalse);
      endpoints(plan);
    });

    test('linear mode is raw coordinate lerp, distinct from polar rotation',
        () {
      final plan =
          buildPlan([open(line(-1, 0, 1, 0, 2))], [open(line(0, -1, 0, 1, 2))]);
      final out = allocOutputs(plan);
      interpLinear(plan, 0.5, out);
      expect(out.single, [-0.5, -0.5, 0.5, 0.5]);
      interpPolar(plan, 0.5, out);
      expect(out.single[0], closeTo(-math.sqrt(0.5), 1e-12));
      expect(out.single[1], closeTo(-math.sqrt(0.5), 1e-12));
    });

    test('half-flight holes clamp residual blend but keep riding the frame',
        () {
      final it = PlanItem(
        a: pts([-2, 0, 2, 0]),
        aC: pts([-2, 0, 2, 0]),
        bT: pts([0, 0, 0, 0]),
        bO: pts([10, 0, 10, 0]),
        ca: [0, 0],
        cb: [10, 0],
        theta: 0,
        lnSigma: 0,
        res: 0,
        closed: true,
        hole: true,
        half: 0,
      );
      final plan = MorphPlan(items: [it], n: 2);
      final out = allocOutputs(plan);
      interpPolar(plan, 0.25, out);
      expect(out.single, [1.5, 0, 3.5, 0]);
      interpPolar(plan, 0.75, out);
      expect(out.single, [7.5, 0, 7.5, 0]);
      it.half = 1;
      it.aC.setAll(0, [0, 0, 0, 0]);
      it.bT.setAll(0, [-2, 0, 2, 0]);
      interpPolar(plan, 0.25, out);
      expect(out.single, [2.5, 0, 2.5, 0]);
      interpPolar(plan, 0.75, out);
      expect(out.single, [6.5, 0, 8.5, 0]);
    });

    test('region metadata and borrowed frames remain mutable', () {
      final it = makeItem(
          line(0, 0, 1, 0, 2), line(0, 1, 1, 1, 2), false, false, false);
      it.ca = [4, 5];
      it.cb = [6, 7];
      it.theta = 0.4;
      it.lnSigma = 0.3;
      it.res = 0.2;
      it.closed = true;
      it.hole = true;
      it.half = 1;
      it.block = const BlockTransport(off: [1, 2], drift: [3, 4]);
      expect(it.ca, [4, 5]);
      expect(it.cb, [6, 7]);
      expect(it.block!.off, [1, 2]);
      expect(it.hole, isTrue);
    });

    test('interruption replans from the exact intermediate samples', () {
      var plan = buildPlan(icon('menu'), icon('x'));
      var out = allocOutputs(plan);
      for (final next in ['check', 'plus', 'arrow-right', 'x']) {
        interpPolar(plan, 0.45, out);
        final source = [
          for (var k = 0; k < out.length; k++)
            Sampled(Float64List.fromList(out[k]), closed: plan.items[k].closed)
        ];
        plan = buildPlan(source, icon(next));
        out = allocOutputs(plan);
        interpPolar(plan, 0, out);
        for (var k = 0; k < out.length; k++) {
          expect(maxDiff(out[k], plan.items[k].a), lessThan(1e-9));
          expect(out[k].every((v) => v.isFinite), isTrue);
        }
      }
      endpoints(plan);
    });
  });

  group('real SVG sampling integration', () {
    const paths = {
      'menu': 'M4 6h16M4 12h16M4 18h16',
      'x': 'M18 6 6 18M6 6l12 12',
      'plus': 'M5 12h14M12 5v14',
      'arrow-right': 'M5 12h14M12 5l7 7-7 7',
      'arrow-down': 'M12 5v14M19 12l-7 7-7-7',
      'check': 'M20 6 9 17l-5-5',
    };

    test('all 36 original Lucide pairs have exact finite reusable frames', () {
      for (final a in paths.values) {
        for (final b in paths.values) {
          final plan = buildPlan(resampleIcon(a), resampleIcon(b));
          endpoints(plan);
          final out = allocOutputs(plan);
          for (final t in [-0.1, 0.25, 0.5, 0.75, 1.1]) {
            interpPolar(plan, t, out);
            for (final cloud in out) {
              expect(cloud.every((v) => v.isFinite), isTrue);
            }
          }
        }
      }
    });

    test('intrinsic square sampling removes an arbitrary mid-edge moveto', () {
      final plan = buildPlan(
        resampleIcon('M2 2H22V22H2Z'),
        resampleIcon('M12 2H22V22H2V2Z'),
      );
      final it = plan.items.single;
      expect(it.closed, isTrue);
      expect(it.theta.abs(), lessThan(1e-7));
      expect(math.exp(it.lnSigma), closeTo(1, 1e-7));
      expect(it.res, lessThan(1e-6));
      endpoints(plan);
    });

    test('translated and scaled circle contours choose minimal rotation', () {
      final a = resampleIcon(const [
        IconNode('circle', {'cx': 6, 'cy': 6, 'r': 4})
      ]);
      final b = resampleIcon(const [
        IconNode('circle', {'cx': 16, 'cy': 16, 'r': 8})
      ]);
      final plan = buildPlan(a, b);
      expect(plan.items.single.theta.abs(), lessThan(1e-7));
      expect(math.exp(plan.items.single.lnSigma), closeTo(2, 1e-6));
      expect(plan.items.single.res, lessThan(1e-6));
      endpoints(plan);
    });

    test('real arrow pair retains 90 degree rigid global block transport', () {
      final plan = buildPlan(
        resampleIcon(paths['arrow-right']!),
        resampleIcon(paths['arrow-down']!),
      );
      for (final it in plan.items) {
        expect(it.theta.abs(), closeTo(math.pi / 2, 1e-7));
        expect(it.theta, closeTo(plan.items.first.theta, 1e-7));
        expect(it.block, isNotNull);
      }
      final out = allocOutputs(plan);
      final source = [for (final it in plan.items) it.a];
      for (final t in [0.25, 0.5, 0.75]) {
        interpPolar(plan, t, out);
        for (final i in [0, plan.n ~/ 2, plan.n - 1]) {
          for (final j in [0, plan.n ~/ 2, plan.n - 1]) {
            double distance(List<Float64List> clouds) {
              final x = clouds[0][2 * i] - clouds[1][2 * j];
              final y = clouds[0][2 * i + 1] - clouds[1][2 * j + 1];
              return math.sqrt(x * x + y * y);
            }

            expect(distance(out), closeTo(distance(source), 1e-6));
          }
        }
      }
    });
  });

  group('validation', () {
    test(
        'empty icons, invalid point clouds and mismatched samples are rejected',
        () {
      expect(() => buildPlan([], icon('menu')), throwsArgumentError);
      expect(() => buildPlan(icon('menu'), []), throwsArgumentError);
      expect(
          () => buildPlan([
                open(pts([0, 0]))
              ], [
                open(pts([0, 0, 1, 1]))
              ]),
          throwsArgumentError);
      expect(() => alignPair(pts([0, double.nan]), pts([0, 0])),
          throwsArgumentError);
      expect(() => centroid(pts([])), throwsArgumentError);
      expect(() => centroid(pts([0, 1, 2])), throwsArgumentError);
    });

    test('nonfinite progress and lambda are rejected before mutating output',
        () {
      final plan = buildPlan(icon('menu'), icon('x'));
      final out = allocOutputs(plan);
      interpPolar(plan, 0.3, out);
      final before = Float64List.fromList(out[0]);
      for (final t in [double.nan, double.infinity, double.negativeInfinity]) {
        expect(() => interpPolar(plan, t, out), throwsArgumentError);
        expect(() => interpLinear(plan, t, out), throwsArgumentError);
      }
      expect(out[0], before);
      expect(
          () => alignPair(line(0, 0, 1, 1), line(0, 0, 1, 1), false, false,
              true, double.nan),
          throwsArgumentError);
    });
  });
}
