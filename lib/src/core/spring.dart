/// Physical spring settings. Presets retain the original oscillator constants.
class SpringConfig {
  const SpringConfig({required this.stiffness, required this.damping})
      : assert(stiffness >= 0 && stiffness < double.infinity),
        assert(damping >= 0 && damping < double.infinity);

  final double stiffness;
  final double damping;

  /// Approximately critically damped (zeta = 1.00).
  static const smooth = SpringConfig(stiffness: 170, damping: 26);

  /// Fast with subtle overshoot (zeta = 0.73).
  static const snappy = SpringConfig(stiffness: 420, damping: 30);

  /// Playful overshoot (zeta = 0.40).
  static const bouncy = SpringConfig(stiffness: 300, damping: 14);
}

/// Damped harmonic oscillator over progress x: 0 -> 1.
///
/// Semi-implicit Euler uses 1/240-second substeps, capped at 16 as in the
/// original. Interruptions reset progress while preserving bounded velocity.
class Spring {
  double x = 1;
  double v = 0;
  double k = 250;
  double c = 24;

  void config(double k, double c) {
    _checkCoefficient(k, 'k');
    _checkCoefficient(c, 'c');
    this.k = k;
    this.c = c;
  }

  /// Start or restart a flight, preserving velocity clamped to +/-14.
  void start() {
    if (!v.isFinite) {
      throw ArgumentError.value(v, 'v', 'Velocity must be finite');
    }
    x = 0;
    if (v > 14) v = 14;
    if (v < -14) v = -14;
  }

  /// Advance dt seconds. Settles when |1-x| < .001 and |v| < .02.
  /// A zero delta is valid and preserves state exactly.
  bool step(double dt) {
    if (!dt.isFinite || dt < 0) {
      throw ArgumentError.value(dt, 'dt', 'Must be finite and nonnegative');
    }
    _checkCoefficient(k, 'k');
    _checkCoefficient(c, 'c');
    if (!x.isFinite || !v.isFinite) {
      throw ArgumentError('morphicons: spring state must be finite');
    }
    const h = 1 / 240;
    // Branch before ceil so every finite dt, even a huge one, can be capped.
    final int steps;
    if (dt >= 16 * h) {
      steps = 16;
    } else {
      final count = (dt / h).ceil();
      steps = count < 1 ? 1 : count;
    }
    final s = dt / steps;
    for (var i = 0; i < steps; i++) {
      final a = k * (1 - x) - c * v;
      v += a * s;
      x += v * s;
    }
    return (1 - x).abs() < 0.001 && v.abs() < 0.02;
  }

  static void _checkCoefficient(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'Must be finite and nonnegative');
    }
  }
}
