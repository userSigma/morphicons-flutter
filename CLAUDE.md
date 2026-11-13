# morphicons · Flutter branch

The root is now a native Flutter/Dart package. Read [README.md](README.md) for the public API; [docs/flutter-migration.md](docs/flutter-migration.md) maps the port and known differences. Mathematical explanations remain in [docs/how-it-works.md](docs/how-it-works.md).

## Working rules

- Keep `lib/src/core/` and `lib/src/region/` pure Dart: no Flutter, `dart:ui`, browser, or platform dependencies. Flutter state/painting belongs in `lib/src/flutter/`; format importers in `lib/src/adapters/`.
- Runtime dependencies remain limited to the Flutter SDK. Use typed numeric buffers for geometry and reuse interpolation output buffers across frames.
- Preserve exact endpoints, anchored corners, minimal rotation, surjective matching, coherent rigid-block transport, winding and holes. Tests in `test/core/` pin these contracts.
- Preserve lazy first-icon mount, controlled-pair precedence, clean controlled re-entry, exact interruption, deterministic seeking, explicit reduced-motion policy, caller ownership of external controllers, and ticker cleanup. Tests in `test/flutter/` pin these contracts.
- Keep user changes. The original TypeScript `src/`, tests, website and `spike/` are retained as migration references. For changes specifically to legacy TypeScript, load [docs/typescript-agent-reference.md](docs/typescript-agent-reference.md) and [docs/typescript-reference.md](docs/typescript-reference.md).
- Add a regression test first for behavioral changes. After changing geometry, run the tests and inspect the example at progress 0.25 / 0.50 / 0.75 for the key pairs listed in the README.

## Verification

From the root: `flutter pub get`, `flutter analyze`, `flutter test`, and `dart format --output=none --set-exit-if-changed lib test/core test/flutter example/lib example/test`.

From `example/`: `flutter pub get`, `flutter test`, `flutter build web --release`; use `flutter run -d chrome` for visual checks. Check actual command results before reporting success. Platform-specific builds require their host toolchains.

Legacy npm publication is gated by `ENABLE_LEGACY_NPM_PUBLISH == 'true'`; Flutter publication remains disabled by `publish_to: none`. Creating commits, pushing or publishing requires an explicit user request.
