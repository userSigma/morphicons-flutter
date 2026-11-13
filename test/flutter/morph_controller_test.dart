import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/morphicons.dart';

const menu = 'M4 6h16M4 12h16M4 18h16';
const close = 'M18 6 6 18M6 6l12 12';
const check = 'M20 6 9 17l-5-5';

void main() {
  test('lazy first icon snaps and preserves verbatim canonical d', () {
    final controller = MorphController();
    addTearDown(controller.dispose);
    expect(controller.d, '');
    controller.morphTo(menu);
    expect(controller.d, menu);
    expect(controller.isAnimating, isFalse);
  });

  test('morph settles exactly on canonical target with no live flight', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.morphTo(close);
    expect(controller.isAnimating, isTrue);
    for (var i = 0; i < 600 && controller.isAnimating; i++) {
      controller.advance(const Duration(milliseconds: 16));
      expect(controller.d, isNot(contains('NaN')));
    }
    expect(controller.isAnimating, isFalse);
    expect(controller.d, close);
    expect(controller.progress, 1);
    expect(controller.velocity, 0);
  });

  test('seek is deterministic and never schedules animation', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.seek(close, 0.4);
    final frozen = controller.d;
    controller.seek(close, 0.8);
    controller.progress = 0.4;
    expect(controller.d, frozen);
    expect(controller.isAnimating, isFalse);
    controller.advance(const Duration(seconds: 1));
    expect(controller.d, frozen);
    controller.seek(close, 0);
    expect(controller.d, menu);
    controller.seek(close, 1);
    expect(controller.d, close);
  });

  test('interrupting a flight preserves displayed geometry and velocity', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.morphTo(close);
    controller.advance(const Duration(milliseconds: 80));
    final visible = controller.d;
    final velocity = controller.velocity;
    controller.morphTo(check);
    controller.advance(Duration.zero);
    expect(controller.d, visible);
    expect(controller.velocity, velocity.clamp(-14, 14));
  });

  test('scrubbed shape is the source for a later imperative morph', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.seek(close, 0.25);
    final visible = controller.d;
    controller.morphTo(check);
    expect(controller.d, visible);
  });

  test('reduced motion policy is explicit and live', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.configure(userReducedMotion: true);
    controller.morphTo(close);
    expect(controller.isAnimating, isTrue);
    controller.configure(reducedMotion: ReducedMotion.user);
    expect(controller.d, close);
    expect(controller.isAnimating, isFalse);
    controller.morphTo(menu);
    expect(controller.d, menu);
    controller.configure(reducedMotion: ReducedMotion.never);
    controller.morphTo(close);
    expect(controller.isAnimating, isTrue);
    controller.configure(reducedMotion: ReducedMotion.always);
    expect(controller.isAnimating, isFalse);
  });

  test('invalid progress and invalid configuration leave the shape intact', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    expect(() => controller.seek(close, double.nan), throwsArgumentError);
    expect(() => controller.configure(strokeWidth: -1), throwsArgumentError);
    expect(() => controller.seek(close, -0.1), throwsArgumentError);
    expect(controller.d, menu);
  });

  test('consecutive morphs before the first frame preserve the initial shape',
      () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.morphTo(close);
    controller.morphTo(check);
    expect(controller.d, menu);
    controller.advance(const Duration(milliseconds: 16));
    expect(controller.d, isNot(contains('NaN')));
    expect(controller.isAnimating, isTrue);
  });

  test('live contour wrappers and numeric buffers are reused across frames',
      () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.morphTo(close);
    controller.advance(const Duration(milliseconds: 16));
    final contours = controller.contours;
    final points = contours!.first.pts;
    controller.advance(const Duration(milliseconds: 16));
    expect(identical(controller.contours, contours), isTrue);
    expect(identical(controller.contours!.first.pts, points), isTrue);
  });

  test('stroke width changes notify a resting painter', () {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.configure(strokeWidth: 3);
    expect(notifications, 1);
    expect(controller.d, menu);
  });

  test('fill and stroke morphs use closed filled contours', () {
    const disc = [
      IconNode('circle', {'cx': 12, 'cy': 12, 'r': 9, 'fill': 'currentColor'})
    ];
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    controller.seek(disc, 0.5);
    expect(controller.paint, IconPaint.fill);
    expect(controller.contours, isNotEmpty);
    expect(controller.contours!.every((path) => path.closed), isTrue);
    controller.seek(disc, 1);
    expect(controller.paint, IconPaint.fill);
  });
}
