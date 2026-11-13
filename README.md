# morphicons · Flutter

Native, interruptible morphing between **any stroked or filled SVG icons**. Pure Dart geometry, Flutter `CustomPainter`, emergent rotations and spring physics. No JavaScript bridge, WebView, SVG rendering package, or third-party runtime dependencies.

This branch migrates morphicons 2.0.2 to a Flutter package. The original TypeScript sources, bindings and website remain as references; the previous API is preserved in [the TypeScript reference](docs/typescript-reference.md). The Flutter implementation lives in `lib/` and the runnable motion lab in `example/`.

## Install

Requires Flutter ≥ 3.19 and Dart ≥ 3.3. Add the local checkout to your Flutter app:

```yaml
dependencies:
  flutter:
    sdk: flutter
  morphicons:
    path: ../morphicons-flutter
```

The package is currently a local development package (`publish_to: none`). Android, iOS, Web, Windows, macOS and Linux example runners are included. Native builds require each platform's normal Flutter toolchain.

## Usage

```dart
import 'package:morphicons/morphicons.dart';

const menu = 'M4 6h16M4 12h16M4 18h16';
const close = 'M18 6 6 18M6 6l12 12';

// Change icon with your widget's state; the first icon mounts at rest.
MorphIcon(
  icon: isOpen ? close : menu,
  size: 28,
  color: Colors.teal,
  spring: SpringConfig.snappy,
  label: isOpen ? 'Close menu' : 'Open menu',
)
```

A raw SVG `d` string is stroked. For icon packs or filled/mixed artwork, pass immutable node data. Accepted tags: `path`, `line`, `polyline`, `polygon`, `rect`, `circle`, `ellipse`.

```dart
const filledCircle = [
  IconNode('circle', {
    'cx': 12, 'cy': 12, 'r': 9, 'fill': 'currentColor',
  }),
];

MorphIcon(icon: filledCircle, color: Colors.teal)
```

Geometry is monochrome: `color` paints the icon; source fill/stroke values determine the visible surface rather than retaining separate colors. The default coordinate grid is 24 × 24. Use `fitIcon(icon, '0 0 512 512')` for off-grid artwork.

### Controlled progress

```dart
MorphIcon(from: menu, to: close, progress: dragProgress)
```

`progress` must be finite and in `[0, 1]`; scrubbing is deterministic. With both `from` and `to`, the pair takes precedence over `icon`. Leaving controlled mode hands the current geometry back to `icon`; re-entering starts from the explicit `from` again.

### Imperative control

```dart
final morph = MorphController(icon: menu);

// Put this in build. Dispose morph from your State.dispose().
MorphIcon(controller: morph, color: Colors.teal)

morph.morphTo(close);                 // carries velocity through interruptions
morph.set(menu);                      // exact canonical shape, no animation
morph.seek(close, 0.5, from: menu);    // frozen, deterministic progress
morph.progress = 0.75;               // scrubs the active pair
```

An iconless controller is lazy: its first `set`, `morphTo`, prop or controlled pair establishes the initial shape without a flight. `MorphIcon` owns and disposes its internal controller; an external controller stays caller-owned. The widget advances its controller through a Flutter ticker only while flying. A standalone controller can be clocked explicitly with `advance(Duration)`.

`MorphController` is a `Listenable`; inspect `d`, `progress`, `velocity`, `paint`, and `isAnimating`. A raw string snaps back to its **verbatim** `d` at rest. Mid-flight interruption preserves the currently displayed shape, including a zero-time next frame.

### Rendering and accessibility

- `size: 24`, `strokeWidth: 2`, round caps and joins; color follows `IconTheme` unless specified.
- `absoluteStrokeWidth: true` keeps stroke thickness in logical pixels while resizing.
- `label` creates image semantics. Without it the icon is decorative.
- `reducedMotion: ReducedMotion.never` (default), `.user` (follows `MediaQuery.disableAnimations`) or `.always` (jumps to target). Policy changes apply to the same update as the icon.
- `spring`: `SpringConfig.smooth`, `.snappy`, `.bouncy`, or `SpringConfig(stiffness: 250, damping: 24)`.
- `TickerMode` pauses hidden animations. Painting uses isolated repaints, not a widget rebuild per animation frame.

### SVG markup adapter

```dart
import 'package:morphicons/adapters.dart';

final icon = svgToIcon(svgMarkup);
```

The opt-in adapter extracts geometry, inherited paint, inline paint styles and nested transforms, and fits the SVG viewBox to the 24-grid. It skips definitions and hidden nodes. It is a geometry importer, not a full SVG/CSS engine: text, images, masks, filters, `<use>` references and CSS stylesheets are not rendered. Unsupported paint such as gradients produces an error instead of a misleading approximation. Never call it on every animation frame.

## Core and regions

`package:morphicons/core.dart` exposes the Flutter-independent pipeline: `iconToCubics` → `resampleIcon` → `buildPlan` → `allocOutputs` / `interpPolar` → `serialize`, plus `Spring`. It imports neither Flutter nor `dart:ui`.

The port preserves SVG elliptical arc normalization (F.6), GL8 arc-length sampling, exact anchored corners, intrinsic closed-path sampling, surjective subpath matching, Procrustes fitting with the minimal-rotation tie-break, circular correspondence, and coherent global block transport. Endpoints are exact; unequal subpath counts duplicate rather than collapse.

`package:morphicons/region.dart` exposes filled/mixed surface normalization and topology-aware planning. Signed-distance fields and marching squares turn visible fills and round strokes into consistently wound contours; holes share their parent's motion and open/close through split residual interpolation. This is synchronous Dart code (not the former asynchronous JS chunk loader).

Known inherited geometry limits: translucent paint and evenodd self-intersections are unsupported; sub-cell details are grid approximations, and exactly grid-aligned coincident fill seams may produce tiny extra contours. DOM masks, SSR and framework-specific bindings remain in the TypeScript reference rather than being emulated in Flutter.

## Run and verify

```bash
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter run -d chrome        # or windows / android / ios / macos / linux
flutter test
flutter build web --release
```

The motion lab covers menu ↔ close, right ↔ down, plus ↔ close, close ↔ check, circle ↔ square, square ↔ diamond, sun ↔ moon, and filled ring ↔ disc. Scrub at 0.25 / 0.50 / 0.75 and interrupt flights to inspect intermediate geometry.

CI analyzes and tests the package and example, checks Dart formatting, and builds the Web example. Legacy npm publication is opt-in through the `ENABLE_LEGACY_NPM_PUBLISH` repository variable; this branch does not publish either package automatically.

See [migration notes](docs/flutter-migration.md), [the algorithm explanations](docs/how-it-works.md), and [the implementation plan](docs/superpowers/plans/2026-11-13-flutter-migration.md). The original MIT license is retained.
