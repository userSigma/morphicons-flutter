# Flutter migration

## Scope and layout

The current feature branch makes the repository root a Flutter package named `morphicons`. Its native implementation ports the geometry, surface planning, spring and binding lifecycle from the retained 2.0.2 TypeScript source; it does not delegate to JavaScript, a WebView or an SVG plugin. Runtime dependencies consist only of the Flutter SDK.

| Original responsibility | Flutter/Dart location |
| --- | --- |
| Parsing, cubic normalization, fitting and resampling | `lib/src/core/{parse,normalize,resample}.dart` |
| Surjective matching, Procrustes, closed correspondence, global frame | `lib/src/core/plan.dart` |
| Polar/linear interpolation, serialization, oscillator | `lib/src/core/{interpolate,serialize,spring}.dart` |
| Paint classification, SDF normalization, hole-aware region plans | `lib/src/core/region.dart`, `lib/src/region/` |
| SVG markup and transforms adapter | `lib/src/adapters/svg.dart`, opt-in `lib/adapters.dart` |
| Driver state, deterministic seeking and interruptions | `lib/src/flutter/morph_controller.dart` |
| Binding lifecycle, ticker, native canvas and semantics | `lib/src/flutter/morph_icon.dart` |
| Playground | `example/` (six platform runners) |
| Contracts | `test/core/`, `test/flutter/`, `example/test/` |

The original `src/`, JavaScript tests, `playground/`, `website/`, build scripts and npm metadata remain intact as references. The old README and agent guide are archived in `docs/typescript-reference.md` and `docs/typescript-agent-reference.md`. No existing worktree changes are reset. Flutter files are the active development path; keeping references is not a runtime dependency.

## Native API choices

- `IconInput` accepts an SVG path string or `List<IconNode>`. `IconNode` uses a typed `tag`/`attrs` object rather than JavaScript tuples.
- `MorphIcon` provides prop-driven, controlled (`from`, `to`, `progress`) and external-controller modes. Controlled pairs win over `icon`; a first icon on an empty mount is immediate.
- `MorphController` is a `ChangeNotifier` with `morphTo`, `set`, `seek`, `progress`, and explicit `advance`. It owns geometry state, not a platform timer. A mounted `MorphIcon` supplies the ticker, pauses with `TickerMode`, and stops at rest/unmount.
- Intermediate frames mutate preallocated point buffers and repaint a `CustomPainter`. At rest, native cubic paths retain exact curves. The raw-string `d` is canonical verbatim; an interruption retains the visible snapshot and spring velocity.
- `ReducedMotion.never` is the default. `.user` reads Flutter's `MediaQuery.disableAnimations`; `.always` snaps. An external controller is disposed by its caller.
- Painted SVG data is a monochrome surface. The widget color comes from the explicit color or `IconTheme`; semantics come from `label`.
- `core.dart` stays Flutter-independent. `region.dart` exposes region operations; the Flutter driver uses synchronous region generation. The former asynchronous loader, 100 ms fallback and browser chunk mechanics have no native counterpart.

## Intentionally platform-specific

DOM `PathEl`, CSS masks, HTML custom elements, SSR adoption and React/Vue/Svelte/Astro/React Native glue stay in the old reference implementation. Flutter paints to its own Canvas and uses widget semantics. No browser globals, React reconciliation shims or DOM scheduler are ported.

The SVG adapter is an importer for geometric icons, not a complete SVG renderer. It bakes nested transforms, inherits paint, skips hidden/definition nodes and fits viewBoxes. Text, raster images, masks, filters, stylesheet CSS and `<use>` are outside that import format; gradients and unsupported paint are reported as errors.

Inherited region limitations are retained: translucent paint and evenodd self-intersections are unsupported, sub-grid detail is approximate, exactly grid-aligned coincident fill seams can produce extra tiny contours, and a path consisting only of `M` has no visible stroke area. The tests use actual visible short segments for round-cap checks rather than inventing a point-stroke rule absent from the original.

## Tooling and validation

The development run uses Flutter 3.47.7 / Dart 3.13.5. The package declares Dart ≥ 3.3 / Flutter ≥ 3.19; CI runs the pinned development version. Generated platform runners require each platform's Flutter build prerequisites. A Web build does not imply that Android, iOS or desktop binaries were built on this machine.

Run the root analyzer and tests, example widget tests, formatter, and Web release build using the commands in the README. Test coverage includes parser commands/arcs, anchor and closed-shape invariants, matching oracles, rigid blocks, exact endpoints, spring formulas, fill rules/holes, SVG transforms, controller interruption, controlled lifecycle, semantics, motion policy, controller swaps and ticker cleanup. Visual verification should sample 0.25 / 0.50 / 0.75 as well as both endpoints.

The npm publishing workflow is gated behind `ENABLE_LEGACY_NPM_PUBLISH`. Pub publishing is disabled (`publish_to: none`); releasing the Dart package is a separate future decision. No commit, push, or registry publication is part of this migration task.
