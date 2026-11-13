import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/src/core/spring.dart';

void main() {
  test('spring defaults retain the parent controller contract', () {
    final spring = Spring();
    expect(spring.x, 1);
    expect(spring.v, 0);
    expect(spring.k, 250);
    expect(spring.c, 24);
    expect(spring.step(0), isTrue);
  });

  test('public presets use const named SpringConfig parameters', () {
    const custom = SpringConfig(stiffness: 210, damping: 20);
    expect(custom.stiffness, 210);
    expect(custom.damping, 20);
    expect(SpringConfig.smooth.stiffness, 170);
    expect(SpringConfig.smooth.damping, 26);
    expect(SpringConfig.snappy.stiffness, 420);
    expect(SpringConfig.snappy.damping, 30);
    expect(SpringConfig.bouncy.stiffness, 300);
    expect(SpringConfig.bouncy.damping, 14);
  });

  test('start preserves velocity and clamps interruptions to plus/minus 14',
      () {
    final spring = Spring();
    for (final v in [-30.0, -4.0, 0.0, 6.0, 40.0]) {
      spring.x = 0.8;
      spring.v = v;
      spring.start();
      expect(spring.x, 0);
      expect(spring.v, v.clamp(-14, 14));
    }
  });

  test('semi-implicit Euler matches the TypeScript substep formula', () {
    final spring = Spring();
    spring.config(420, 30);
    spring.start();
    var x = 0.0;
    var v = 0.0;
    for (final dt in [0.0, 1 / 240, 1 / 60, 1 / 30, 0.1]) {
      const h = 1 / 240;
      final steps = math.max(1, math.min(16, (dt / h).ceil()));
      final s = dt / steps;
      for (var i = 0; i < steps; i++) {
        final a = 420 * (1 - x) - 30 * v;
        v += a * s;
        x += v * s;
      }
      final settled = spring.step(dt);
      expect(spring.x, x);
      expect(spring.v, v);
      expect(settled, (1 - x).abs() < 0.001 && v.abs() < 0.02);
    }
  });

  for (final preset in [
    SpringConfig.smooth,
    SpringConfig.snappy,
    SpringConfig.bouncy
  ]) {
    test(
        'preset ${preset.stiffness}/${preset.damping} settles within 1.5 seconds',
        () {
      final spring = Spring();
      spring.config(preset.stiffness, preset.damping);
      spring.start();
      var elapsed = 0.0;
      var settled = false;
      while (elapsed < 5 && !settled) {
        settled = spring.step(1 / 60);
        elapsed += 1 / 60;
        expect(spring.x.isFinite, isTrue);
        expect(spring.v.isFinite, isTrue);
      }
      expect(settled, isTrue);
      expect(elapsed, lessThan(1.5));
      expect((1 - spring.x).abs(), lessThan(0.001));
      expect(spring.v.abs(), lessThan(0.02));
    });
  }

  test('bouncy spring overshoots naturally', () {
    final spring = Spring();
    spring.config(SpringConfig.bouncy.stiffness, SpringConfig.bouncy.damping);
    spring.start();
    var peak = 0.0;
    for (var i = 0; i < 120; i++) {
      spring.step(1 / 60);
      peak = math.max(peak, spring.x);
    }
    expect(peak, greaterThan(1.1));
  });

  test('zero delta preserves an interrupted flight exactly', () {
    final spring = Spring();
    spring.start();
    spring.step(1 / 60);
    final x = spring.x;
    final v = spring.v;
    expect(spring.step(0), isFalse);
    expect(spring.x, x);
    expect(spring.v, v);
  });

  test('negative or nonfinite dt is rejected atomically', () {
    final spring = Spring();
    spring.start();
    spring.step(1 / 60);
    final x = spring.x;
    final v = spring.v;
    for (final dt in [
      -0.1,
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      expect(() => spring.step(dt), throwsArgumentError);
      expect(spring.x, x);
      expect(spring.v, v);
    }
  });

  test('invalid physical parameters are rejected before configuration changes',
      () {
    final spring = Spring();
    for (final bad in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -1.0
    ]) {
      expect(() => spring.config(bad, 24), throwsArgumentError);
      expect(() => spring.config(250, bad), throwsArgumentError);
      expect(spring.k, 250);
      expect(spring.c, 24);
    }
    spring.config(0, 0);
    expect(spring.k, 0);
    expect(spring.c, 0);
  });

  test('mutable nonfinite controller state is detected before integration', () {
    final spring = Spring();
    spring.v = double.nan;
    expect(spring.start, throwsArgumentError);
    spring.v = 0;
    spring.x = double.nan;
    expect(() => spring.step(1 / 60), throwsArgumentError);
    spring.x = 0;
    spring.k = double.infinity;
    expect(() => spring.step(1 / 60), throwsArgumentError);
  });
}
