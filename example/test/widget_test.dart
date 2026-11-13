import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/morphicons.dart';
import 'package:morphicons_example/main.dart';

void main() {
  testWidgets('demo animates, changes presets and scrubs deterministically',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MorphiconsApp());
    expect(find.text('morphicons'), findsOneWidget);
    expect(find.byType(MorphIcon), findsWidgets);
    await tester.tap(find.text('Morph forward'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Bouncy'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all eight pairs paint at quarter, half and three-quarter progress',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MorphiconsApp());
    const titles = [
      'Menu / Close',
      'Right / Down',
      'Plus / Close',
      'Close / Check',
      'Circle / Square',
      'Square / Diamond',
      'Sun / Moon',
      'Ring / Disc',
    ];
    const capture = bool.fromEnvironment('CAPTURE_VISUALS');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF101A19), BlendMode.src);
    final images = <ui.Image>[];
    for (var row = 0; row < titles.length; row++) {
      final card = find.text(titles[row]);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      for (var column = 0; column < 3; column++) {
        final value = (column + 1) / 4;
        tester.widget<Slider>(find.byType(Slider)).onChanged!(value);
        await tester.pump();
        final stage = find.byWidgetPredicate(
            (widget) => widget is MorphIcon && widget.controller != null);
        final controller = tester.widget<MorphIcon>(stage).controller!;
        expect(controller.progress, value);
        expect(controller.isAnimating, isFalse);
        expect(controller.d, isNot(contains('NaN')));
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.ensureVisible(stage);
          await tester.pump();
          final boundary = tester.renderObject<RenderRepaintBoundary>(find
              .descendant(of: stage, matching: find.byType(RepaintBoundary)));
          final image = await tester.runAsync(() => boundary.toImage());
          images.add(image!);
          final x = column * 220.0;
          final y = row * 170.0;
          canvas.drawImage(image, Offset(x + 46, y + 30), Paint());
          final text = (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 12))
                ..pushStyle(ui.TextStyle(color: const Color(0xFFD2F578)))
                ..addText('${titles[row]}  t=$value'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 210));
          canvas.drawParagraph(text, Offset(x + 12, y + 8));
          text.dispose();
        }
      }
    }
    final picture = recorder.endRecording();
    if (capture) {
      await tester.runAsync(() async {
        final image = await picture.toImage(660, 1360);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/verification/midframes.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    picture.dispose();
    for (final image in images) {
      image.dispose();
    }
  });

  testWidgets('demo fits a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MorphiconsApp());
    expect(tester.takeException(), isNull);
  });
}
