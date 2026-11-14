# Keeping the Flutter fork in sync

## Branch contract

```text
guillermolg00/morphicons:main -> upstream-main -> sync/upstream -> develop -> main
feature/* -----------------------------------------------------> develop
```

- `upstream-main` is an exact, fast-forward-only mirror of the upstream default branch. It contains no Flutter patches and uses no upstream tags.
- `develop` is this fork's default integration branch. `main` remains the stable/release branch; merging development into it is a separate release decision.
- One persistent `sync/upstream` branch opens one draft PR into `develop`. Existing work and upstream ancestry are preserved with merge commits and ordinary pushes.
- `main` and `develop` require PRs and the successful `checks` status on an up-to-date base. Force pushes/deletion are disabled. Required approval count is zero for this single-maintainer repository; the maintainer still deliberately reviews and merges each PR.
- The migration feature branch is retained. There is no automatic package publication; keep the legacy npm workflow gated and Flutter `publish_to: none`.

## Automation

[The synchronization workflow](../.github/workflows/upstream-sync.yml) runs daily at 20:17 UTC (04:17 Asia/Shanghai) and can be dispatched manually on `develop`. The default branch must contain this workflow for scheduling and manual discovery; it currently is `develop`.

It fetches the fixed upstream repository, snapshots its main SHA, fast-forwards `upstream-main`, then checks whether `develop` already contains that commit. If so, the run is a successful no-op. Otherwise it merges development and the fixed upstream commit onto `sync/upstream`, updates the port ledger, and creates/updates one draft PR. It never merges that PR or marks a Dart port complete.

The synchronization job alone receives contents, pull-requests, issues and actions write permissions. Repository-default workflow permissions remain read-only. GitHub Actions must be allowed to create PRs in repository Settings -> Actions -> General. No PAT or extra secret is required: the job uses its short-lived `GITHUB_TOKEN` as `GH_TOKEN`.

A PR created with `GITHUB_TOKEN` does not automatically trigger another workflow. The script explicitly dispatches [CI](../.github/workflows/ci.yml) on the sync branch, so its exact commit receives the required `checks` result even while the PR is a draft. Pending Dart work intentionally makes that check fail. Ordinary maintainer pushes also trigger CI.

A mirror that diverges from upstream, an upstream history rewrite, a git push failure or an API failure stops the run with a visible failure. A merge conflict is aborted in the temporary runner checkout and creates/updates the issue `[upstream-sync] Manual integration required`; conflicting remote history is left intact.

## Two different synchronization states

[The ledger](upstream-sync.json) separates:

- `reference_commit`: upstream source reviewed/imported into the fork's ancestry.
- `ported_commit`: the upstream commit through which applicable changes have been ported to Dart and verified.
- `pending_commits`: upstream commits still requiring review/porting.

The bot advances `reference_commit`, retains `ported_commit`, and populates `pending_commits`. The CI gate accepts only equal reference/ported commits and an empty pending list. It also validates the exact repository identity, SHA syntax, commit ancestry and the merge-base with `origin/upstream-main`. Thus ordinary Flutter feature work may lag a newer mirror tip, while merging newer upstream history without updating the ledger is caught.

**The ledger is an acknowledgement gate, not proof of mathematical or semantic equivalence.** Review the implementation and tests before acknowledging. Branch protection, real regression tests and maintainer review supply the other controls.

## Completing a sync PR

1. Review all commits and changed paths listed in the draft PR. Put maintainer notes outside the `<!-- upstream-sync:begin -->` / `<!-- upstream-sync:end -->` block: the bot replaces only that block and preserves surrounding review text on later runs.
2. Classify each change in the PR description:
   - parser, normalization, sampling, matching, interpolation, spring, regions or SVG importer: port the applicable algorithm/test changes to Dart;
   - lifecycle/interruptions/progress: assess the shared contract and add Flutter regression tests;
   - React/Vue/Svelte/DOM-only behavior: retain the reference source and state the reason it is not applicable;
   - npm/site/tooling: review separately; preserve the fork's Flutter tooling and publication gates.
3. Write failing regression tests before behavior changes. For pipeline updates compare shared inputs in TS and Dart: raw geometry with explicit numeric tolerances, exact endpoints/canonical strings, rotation/spring state, hole topology, and frames at 0.25/0.50/0.75. Equivalent tie-breaks and rounded SVG output may need invariant-based comparisons instead of byte comparison. CI exports six centerline pairs from the current TypeScript source at five progress values and compares Dart raw coordinates within 1e-8; three spring presets with an interruption are compared within 1e-12. This bounded oracle is not complete coverage: regions, importers and lifecycle still need their regression/invariant suites and review.
4. After every pending commit is accounted for, set `ported_commit` equal to `reference_commit` and clear `pending_commits` in the ledger. Explain ported and non-applicable changes in the PR description; retain the originating SHAs.
5. Run the commands below, push the reviewed changes, mark the PR ready, and merge with a merge commit after `checks` succeeds. Keep the persistent sync branch so the next run can extend it without rewriting history.

```bash
git fetch --no-tags origin upstream-main:refs/remotes/origin/upstream-main
python -m unittest discover -s test/automation -p 'test_*.py' -v
python scripts/check_upstream_port.py
# Optional locally; required in CI. Node 24+ executes the retained TS reference.
node scripts/export-upstream-fixtures.mjs
export UPSTREAM_FIXTURES=.dart_tool/upstream-fixtures.json
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
dart format --output=none --set-exit-if-changed lib test/core test/flutter test/parity example/lib example/test
cd example
flutter pub get
flutter test --no-pub
flutter build web --release --no-pub
```

## Manual conflict recovery

Start from a clean working directory. Read the bot issue and exact target SHA. If `sync/upstream` already exists, work from it; otherwise create it from current `develop`.

```bash
git fetch --no-tags origin
git fetch --no-tags upstream main
git switch sync/upstream
git merge --no-ff origin/develop
git -c merge.renormalize=true -c core.autocrlf=input merge --no-ff upstream/main
```

For the first conflicting update, where the remote sync branch has not yet been created, replace `git switch sync/upstream` with `git switch -c sync/upstream origin/develop`. Resolve conflicts deliberately, especially the root README/agent guide and CI/publishing configuration. Retain both the upstream reference behavior and Flutter-specific configuration; do not globally select `ours` or `theirs`. Complete the ledger and test/review steps above, then push normally and create/update the draft PR into `develop`.

The next scheduled run also detects an existing manual branch. If upstream history was rewritten, investigate the old/new ancestry separately: the bot deliberately never resets or force-pushes the mirror.

## Local remote setup and release notes

Every new clone needs its own local upstream remote (repository-local Git configuration is not transferred by clone):

```bash
git remote add upstream https://github.com/guillermolg00/morphicons.git
git fetch --no-tags upstream
```

Use `flutter-v*` for future Flutter release tags and fetch upstream without `--tags`. A future release PR may move `develop` into `main`; changing the default branch afterward must retain the synchronization workflow there and its trusted `develop` checkout. Never use the GitHub Sync fork UI to replace the Flutter branches with upstream source.
