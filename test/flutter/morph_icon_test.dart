import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/morphicons.dart';

const menu = 'M4 6h16M4 12h16M4 18h16';
const close = 'M18 6 6 18M6 6l12 12';
const check = 'M20 6 9 17l-5-5';

Widget host(Widget child, {bool reduced = false, bool ticker = true}) =>
    MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(enabled: ticker, child: Center(child: child))));

void main() {
  testWidgets('an iconless mount is lazy; first icon does not fly',
      (tester) async {
    final controller = MorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(MorphIcon(controller: controller)));
    expect(controller.d, '');
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: menu)));
    expect(controller.d, menu);
    expect(controller.isAnimating, isFalse);
  });

  testWidgets('prop updates fly, settle and unmount without leaking a ticker',
      (tester) async {
    final controller = MorphController();
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: menu)));
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: close)));
    expect(controller.isAnimating, isTrue);
    await tester.pumpAndSettle();
    expect(controller.d, close);
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: menu)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(controller.isDisposed, isFalse);
  });

  testWidgets(
      'controlled pair wins, exits cleanly and re-enters like a new mount',
      (tester) async {
    final controller = MorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(MorphIcon(
        controller: controller,
        icon: check,
        from: menu,
        to: close,
        progress: 0.4)));
    final controlled = controller.d;
    await tester.pumpWidget(host(MorphIcon(
        controller: controller,
        icon: close,
        from: menu,
        to: close,
        progress: 0.4)));
    expect(controller.d, controlled);
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: check)));
    await tester.pumpAndSettle();
    expect(controller.d, check);
    await tester.pumpWidget(host(MorphIcon(
        controller: controller,
        icon: check,
        from: menu,
        to: close,
        progress: 0.4)));
    expect(controller.d, controlled);
    expect(controller.isAnimating, isFalse);
  });

  testWidgets('labels expose image semantics and decoration stays excluded',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester
        .pumpWidget(host(const MorphIcon(icon: menu, label: 'Open menu')));
    expect(find.bySemanticsLabel('Open menu'), findsOneWidget);
    await tester.pumpWidget(host(const MorphIcon(icon: menu)));
    expect(find.bySemanticsLabel('Open menu'), findsNothing);
    expect(tester.getSize(find.byType(CustomPaint).last), const Size(24, 24));
    handle.dispose();
  });

  testWidgets('OS motion preference only applies in user policy',
      (tester) async {
    final controller = MorphController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        host(MorphIcon(controller: controller, icon: menu), reduced: true));
    await tester.pumpWidget(
        host(MorphIcon(controller: controller, icon: close), reduced: true));
    expect(controller.isAnimating, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(
        MorphIcon(
            controller: controller,
            icon: menu,
            reducedMotion: ReducedMotion.user),
        reduced: true));
    expect(controller.isAnimating, isFalse);
    expect(controller.d, menu);
  });

  testWidgets('swapping external controllers detaches old listeners',
      (tester) async {
    final a = MorphController(icon: menu);
    final b = MorphController(icon: close);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await tester.pumpWidget(host(MorphIcon(controller: a)));
    await tester.pumpWidget(host(MorphIcon(controller: b)));
    a.morphTo(check);
    expect(b.d, close);
    expect(b.isAnimating, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated rebuilds do not restart an active flight',
      (tester) async {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: menu)));
    await tester
        .pumpWidget(host(MorphIcon(controller: controller, icon: close)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    final progress = controller.progress;
    expect(progress, greaterThan(0));
    await tester.pumpWidget(host(
        MorphIcon(controller: controller, icon: close, color: Colors.red)));
    expect(controller.progress, progress);
    await tester.pumpAndSettle();
    expect(controller.d, close);
  });

  testWidgets('absolute width also reaches stroke-to-fill region generation',
      (tester) async {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(MorphIcon(
        controller: controller,
        size: 96,
        strokeWidth: 2,
        absoluteStrokeWidth: true)));
    expect(controller.strokeWidth, 0.5);
  });

  testWidgets('TickerMode pauses animation and resumes without a time jump',
      (tester) async {
    final controller = MorphController(icon: menu);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(MorphIcon(controller: controller)));
    controller.morphTo(close);
    await tester.pump(const Duration(milliseconds: 32));
    await tester
        .pumpWidget(host(MorphIcon(controller: controller), ticker: false));
    final frozen = controller.d;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.d, frozen);
    await tester.pumpWidget(host(MorphIcon(controller: controller)));
    await tester.pumpAndSettle();
    expect(controller.d, close);
  });
}
