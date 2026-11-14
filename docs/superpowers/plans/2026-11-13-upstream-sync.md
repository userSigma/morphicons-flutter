# Upstream Synchronization Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the isolated Python synchronization task; keep GitHub administration and workflow integration in the parent session. Track the checkboxes and verify remote postconditions before reporting completion.

**Goal:** Keep the fork's upstream history discoverable and mergeable while requiring an explicit, tested Dart port before upstream changes enter Flutter development.

**Architecture:** `upstream-main` is a fast-forward-only mirror of `guillermolg00/morphicons:main`. The persistent `sync/upstream` branch opens one draft PR into `develop`; merging upstream source never marks its Dart port complete. `develop` is the default integration branch and `main` remains the stable/release branch. The existing feature migration enters `develop` through a merge-commit PR.

**Tech Stack:** Git, GitHub REST/Actions, dependency-free Python unittest automation, existing Flutter/Dart CI. No registry publication or forced update is part of this change.

## Scope and file ownership

- Python task: `scripts/upstream_sync.py`, `scripts/check_upstream_port.py`, `test/automation/test_upstream_sync.py`, `test/automation/test_upstream_port.py`.
- Integration: `.github/workflows/ci.yml`, `.github/workflows/upstream-sync.yml`, `docs/upstream-sync.json`, `docs/upstream-sync.md`, and README navigation.
- Repository administration: upstream remote, upstream-main remote branch, merge migration PR, default branch, Actions PR permission, branch protection.

## Task 1: Verify state and access

- [x] Inspect local/remote branches and existing untracked paths without changing them.
- [x] Check selected GitHub repository admin/push permissions without printing credentials.
- [x] Fetch origin/upstream without importing upstream tags and capture the exact baseline SHA.
- [x] Preserve existing repository settings except the settings expressly needed by this plan.

## Task 2: Test automation before implementing

- [x] Write checker tests for valid baselines, malformed state, pending ports, stale reference markers and ancestry.
- [x] Observe RED, implement the checker, and observe GREEN.
- [x] Write real temporary-bare-repository tests for mirror fast-forward, no-op sync, pending ledger, repeated PR reuse, dispatch, merge conflict rollback and remote/API failure propagation.
- [x] Observe RED, implement the sync script, and observe GREEN.
- [x] Script uses only fixed repository identities, ordinary pushes, and draft PRs. Conflicts create/update an issue and fail. Upstream rewrites fail rather than replacing mirror history.

## Task 3: Configure ledger and workflows

- [x] Initialize ledger to `8c3e3c7cd717b2381f8f35cf6c245afd80d8d7df` for both reference and ported commits, with no pending commits.
- [x] Extend CI to develop, sync branches and workflow_dispatch; keep required check name `checks`.
- [x] Run automation tests and the port ledger gate before Flutter analysis/tests/build.
- [x] Add daily and manual trusted-develop synchronization workflow with contents/PR/issues/actions write permissions limited to that workflow.
- [x] Explicitly dispatch CI after GITHUB_TOKEN-generated PR updates; GitHub does not automatically emit another workflow run for these writes.
- [x] Document review classifications, port acknowledgement, conflict recovery, upstream rewrites, permissions and the fact that ledger approval is not numerical equivalence proof.

## Task 4: Apply remote topology

- [x] Push upstream/main to origin/upstream-main without forcing.
- [x] Open feature/rewrite-to-flutter -> develop PR and verify checks for its exact head.
- [x] Merge with a merge commit; retain the feature branch and ancestry.
- [ ] Push automation on its own configuration branch and integrate through a PR after checks.
- [ ] Verify develop remains default once the workflows exist there; keep main at its previous release baseline.
- [x] Protect main/develop against force pushes and deletion; require PRs, conversation resolution and successful `checks` on an up-to-date base. Zero mandatory approvals supports this single-maintainer repository while retaining the PR gate.
- [x] Enable Actions PR creation without broadening default read-only workflow permissions. Each write workflow declares its own minimum permissions.

## Task 5: Verify end to end

- [x] Run `python -m unittest discover -s test/automation -p 'test_*.py' -v` (42 tests passed locally).
- [x] Run `python scripts/check_upstream_port.py` with origin/upstream-main fetched.
- [ ] Run Flutter format, analyze, library tests, example tests and Web release build through the required CI.
- [ ] Dispatch upstream synchronization on develop; verify the baseline no-op succeeds and no duplicate PR is created.
- [ ] Read back default branch, branch protection, workflow permissions, remote SHAs and pull request outcomes.
- [ ] Report actual URLs and any unmet remote setting instead of assuming an API request took effect.
