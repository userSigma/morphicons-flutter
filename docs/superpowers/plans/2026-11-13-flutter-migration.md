# Flutter Migration Implementation Plan

**Goal:** Make this feature branch a native Flutter package preserving morphicons' geometry, region topology, and three lifecycle modes without a JavaScript runtime.

**Architecture:** A pure Dart core under `lib/src/core/` retains SVG lowering, anchored sampling, surjective matching, polar interpolation and springs. Flutter adds a ChangeNotifier controller, a ticker owned by the widget, and a CustomPainter. The existing TypeScript, website and historical spike remain untouched as migration references because the workspace already carries line-ending changes.

**Tech Stack:** Flutter SDK and Dart 3; Flutter SDK is the only runtime dependency; flutter_test is the test dependency. Work stays on feature/rewrite-to-flutter, with no commit or push.

## Design decisions

- Native port rather than a JS bridge: all supported Flutter targets use the same numerical pipeline.
- Root Flutter package plus standalone `example/` app rather than removing existing source: preserves the original implementation for parity inspection and user's existing work.
- `IconInput` is an Object accepted as a path string or `List<IconNode>`; `IconNode(tag, attrs)` is the typed Dart equivalent of a Lucide node tuple.
- `CubicPath(Float64List pts, {required bool closed})`, `Sampled(Float64List pts, {required bool closed, bool hole = false})`; all algorithm modules use these types.
- Public widget: `MorphIcon(icon:, from:, to:, progress:, controller:, size:, color:, strokeWidth:, absoluteStrokeWidth:, spring:, reducedMotion:, label:)`.
- `MorphController` exposes `morphTo`, `set`, `seek`, `progress`, canonical `d`, painting mode, animation state, and `advance(Duration)` for deterministic host-driven animation. It is usable independently of a widget.
- Spring presets are immutable `SpringConfig.snappy`, `.smooth`, `.bouncy`; reduced motion is the enum `ReducedMotion.never/user/always` (default never).
- The widget owns a Flutter ticker, starts it only while flying, respects TickerMode, and disposes owned resources. External controllers remain caller-owned.
- Controlled from/to wins over icon, first lazy icon snaps, dropping/re-entering a pair clears the cached pair, interruption starts at the exact visible cloud while retaining spring velocity.
- Canonical endpoint paths are preserved; the painter uses cubic commands at rest and sampled contours in flight. Labels use Semantics and decorative icons are excluded.
- Region normalization and planning retain fill-rule handling, stroke/fill mixing and disappearing holes; the painter uses nonzero fill, not stroke approximations.
- Existing web-only adapters remain in the reference implementation; native Canvas replaces DOM/mask targets.

## Task 1: Geometry port (independent lane)
- [ ] Create `test/core/geometry_test.dart` from SVG parse/normalize/resample/viewBox contracts and observe red before production code.
- [ ] Port `src/core/{types,parse,normalize,resample,serialize}.ts` into correspondingly named Dart files.
- [ ] Keep public function names (`parsePath`, `iconToCubics`, `fitIcon`, `resamplePath`, `resampleIcon`, `serialize`, `cubicsToPathD`). Optional numeric arguments use positional defaults.
- [ ] Run `flutter test test/core/geometry_test.dart` and format changed files.

## Task 2: Plan, interpolation and spring (independent lane)
- [ ] Create `test/core/plan_test.dart` and `test/core/spring_test.dart`, observe red.
- [ ] Port `src/core/{plan,interpolate,spring}.ts`, keeping `PlanItem`, `MorphPlan`, `buildPlan`, `makeItem`, `applyGlobal`, `allocOutputs`, `interpPolar`, `interpLinear` and helpers.
- [ ] Preserve theta=pi/2 for arrow rotation, menu minimal turns, exact endpoints, circular correspondence, block transport and greedy guards.
- [ ] Port spring with bounded semi-implicit substeps and interruption velocity clamp.
- [ ] Run focused tests and formatter.

## Task 3: Filled regions (independent lane)
- [ ] Create `test/core/region_test.dart`, observe red.
- [ ] Port paint helpers to `lib/src/core/region.dart`, normalizer to `lib/src/region/region.dart`, region plan to `lib/src/region/plan.dart`.
- [ ] Preserve distance-field union, marching squares, winding, holes, and source/destination sample counts.
- [ ] Run focused region tests (rings/discs, mixed stroke-fill and overlap union).

## Task 4: Flutter lifecycle and rendering
- [ ] Create controller and widget tests before implementation and record missing implementation failure.
- [ ] Implement `lib/src/flutter/morph_controller.dart`, `morph_icon.dart`, `morph_painter.dart`, plus `lib/morphicons.dart` and pure `lib/core.dart` exports.
- [ ] Test canonical settling, lazy mount, controlled precedence/re-entry, seek without ticks, interruptions, reduced motion, controller swap/disposal and semantics.
- [ ] Add dependency-free SVG markup adapter under `lib/src/adapters/` if the existing input adapter can be migrated without a DOM.

## Task 5: Example, docs and verification
- [ ] Create `example/pubspec.yaml`, `example/lib/main.dart`, and a web runner. Include preset selection, key pairs, slider and imperative controls.
- [ ] Update README and migration notes with complete Flutter snippets and explicit platform differences. Retain old documentation in `docs/typescript-reference.md`.
- [ ] Add Flutter ignores, Flutter CI and disable accidental npm publishing from this branch.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test example/lib`, `flutter analyze`, `flutter test`, `flutter build web --release` from example and inspect the built demo in the browser.
- [ ] Inspect diff and branch, record exact results and any platform gaps; no commit/push.
