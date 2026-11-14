"""Network-free sync integration tests using real temporary bare Git remotes."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest import mock
import unittest
from urllib.error import HTTPError, URLError

from test_upstream_port import ROOT, RepoCase, commit_file, git, ledger_data, port

try:
    import upstream_sync as sync
except ModuleNotFoundError:
    sync = None

UPSTREAM_URL = "https://github.com/guillermolg00/morphicons.git"


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.prs = []
        self.issues = []
        self.fail = None

    def request(self, method, endpoint, data=None):
        self.calls.append((method, endpoint, data))
        if self.fail and self.fail in endpoint:
            raise port.PortError("GitHub API request failed; verify permissions and retry.")
        if endpoint.startswith("pulls?"):
            return self.prs.copy()
        if endpoint.startswith("issues?"):
            return self.issues.copy()
        if method == "POST" and endpoint in ("pulls", "issues"):
            result = dict(data, number=len(self.prs if endpoint == "pulls" else self.issues) + 1)
            (self.prs if endpoint == "pulls" else self.issues).append(result)
            return result
        if method == "PATCH":
            items = self.prs if endpoint.startswith("pulls/") else self.issues
            item = next(item for item in items if item["number"] == int(endpoint.split("/")[1]))
            item.update(data)
            return item
        if endpoint == "actions/workflows/ci.yml/dispatches":
            return None
        raise AssertionError((method, endpoint, data))


class UpstreamSyncTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.assertIsNotNone(sync, "scripts/upstream_sync.py must implement approved synchronization")
        self.origin = self.root / "origin.git"
        self.upstream = self.root / "upstream.git"
        git(self.root, "init", "--bare", str(self.origin))
        git(self.root, "init", "--bare", str(self.upstream))
        git(self.repo, "remote", "add", "origin", str(self.origin))
        git(self.repo, "remote", "add", "upstream", UPSTREAM_URL)
        git(self.repo, "config", "url." + self.upstream.as_posix() + ".insteadOf", UPSTREAM_URL)
        git(self.repo, "branch", "-m", "develop")
        git(self.repo, "push", "origin", "develop")
        git(self.repo, "push", "origin", self.baseline + ":refs/heads/upstream-main")
        git(self.repo, "push", str(self.upstream), self.baseline + ":refs/heads/main")
        self.author = self.root / "upstream-author"
        git(self.root, "clone", "--branch", "main", str(self.upstream), str(self.author))
        self.api = FakeAPI()
        self.env = {"GH_TOKEN": "secret-test-token", "GITHUB_REPOSITORY": "userSigma/morphicons-flutter"}
        self.git_env = mock.patch.dict(os.environ, {
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0"})
        self.git_env.start()
        self.addCleanup(self.git_env.stop)

    def run_sync(self, **kwargs):
        return sync.synchronize(self.repo, self.api, env=self.env, **kwargs)

    def upstream_change(self, name="upstream.txt", text="upstream change\n"):
        sha = commit_file(self.author, name, text)
        git(self.author, "push", "origin", "main")
        return sha

    def remote_sha(self, branch):
        return git(self.root, "--git-dir=" + str(self.origin), "rev-parse",
                   "refs/heads/" + branch, check=False).stdout.strip()

    def develop_again(self):
        git(self.repo, "checkout", "develop")

    def test_baseline_noop_does_not_create_branch_or_pr(self):
        before = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.run_sync(), self.baseline)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD").stdout.strip(), before)
        self.assertEqual(self.api.calls, [])
        self.assertNotEqual(git(self.root, "--git-dir=" + str(self.origin), "show-ref", "--verify",
                                "refs/heads/sync/upstream", check=False).returncode, 0)

    def test_new_upstream_merges_ledger_pending_and_dispatches(self):
        first = self.upstream_change()
        target = self.upstream_change("second.txt", "second\n")
        self.assertEqual(self.run_sync(), target)
        data = json.loads(self.ledger.read_text(encoding="utf-8"))
        self.assertEqual(data, {**ledger_data(target), "ported_commit": self.baseline,
                                "pending_commits": [first, target]})
        self.assertEqual(self.remote_sha("upstream-main"), target)
        self.assertEqual(self.remote_sha("sync/upstream"), git(self.repo, "rev-parse", "HEAD").stdout.strip())
        self.assertEqual(len(self.api.prs), 1)
        self.assertTrue(self.api.prs[0]["draft"])
        self.assertEqual(self.api.prs[0]["head"], "sync/upstream")
        self.assertEqual(self.api.prs[0]["base"], "develop")
        self.assertIn(("POST", "actions/workflows/ci.yml/dispatches", {"ref": "sync/upstream"}), self.api.calls)
        with self.assertRaisesRegex(port.PortError, "pending_commits"):
            port.check(self.repo)
        data["ported_commit"] = target
        data["pending_commits"] = []
        self.write_ledger(data)
        self.assertEqual(port.check(self.repo)["reference_commit"], target)

    def test_repeated_run_updates_one_pr_without_rewriting_branch(self):
        self.upstream_change()
        self.run_sync()
        first_sync = self.remote_sha("sync/upstream")
        self.develop_again()
        self.run_sync()
        self.assertEqual(len(self.api.prs), 1)
        self.assertEqual(self.remote_sha("sync/upstream"), first_sync)
        self.assertEqual(sum(method == "POST" and endpoint == "pulls" for method, endpoint, _ in self.api.calls), 1)
        self.assertTrue(any(method == "PATCH" and endpoint == "pulls/1" for method, endpoint, _ in self.api.calls))

    def test_existing_sync_builds_on_remote_and_merges_new_develop(self):
        first = self.upstream_change()
        self.run_sync()
        old_sync = self.remote_sha("sync/upstream")
        self.develop_again()
        develop = commit_file(self.repo, "flutter.txt", "Flutter independent change\n")
        git(self.repo, "push", "origin", "develop")
        target = self.upstream_change("second.txt", "second\n")
        self.run_sync()
        new_sync = self.remote_sha("sync/upstream")
        for ancestor in (old_sync, develop, target):
            self.assertEqual(git(self.repo, "merge-base", "--is-ancestor", ancestor, new_sync).returncode, 0)
        self.assertEqual(json.loads(self.ledger.read_text())["pending_commits"], [first, target])

    def test_conflict_aborts_only_owned_merge_and_updates_one_issue(self):
        commit_file(self.repo, "source.txt", "fork change\n")
        git(self.repo, "push", "origin", "develop")
        target = self.upstream_change("source.txt", "upstream incompatible\n")
        for _ in range(2):
            self.develop_again()
            with self.assertRaisesRegex(port.PortError, "conflict"):
                self.run_sync()
            self.assertNotEqual(git(self.repo, "rev-parse", "--verify", "MERGE_HEAD", check=False).returncode, 0)
            self.assertEqual(git(self.repo, "status", "--porcelain").stdout, "")
        self.assertEqual(self.remote_sha("upstream-main"), target)
        self.assertEqual(len(self.api.issues), 1)
        self.assertEqual(self.api.issues[0]["title"], "[upstream-sync] Manual integration required")
        self.assertIn(target, self.api.issues[0]["body"])
        self.assertIn("source.txt", self.api.issues[0]["body"])
        self.assertEqual(self.api.prs, [])

    def test_conflict_preserves_existing_remote_sync_branch(self):
        self.upstream_change()
        self.run_sync()
        old_sync = self.remote_sha("sync/upstream")
        self.develop_again()
        commit_file(self.repo, "source.txt", "fork change\n")
        git(self.repo, "push", "origin", "develop")
        self.upstream_change("source.txt", "upstream incompatible\n")
        with self.assertRaisesRegex(port.PortError, "conflict"):
            self.run_sync()
        self.assertEqual(self.remote_sha("sync/upstream"), old_sync)

    def test_divergent_mirror_is_reported_without_force_push(self):
        divergent = commit_file(self.repo, "fork-only.txt", "not upstream\n")
        git(self.repo, "push", "origin", divergent + ":refs/heads/upstream-main")
        self.upstream_change()
        with self.assertRaisesRegex(port.PortError, "rewritten|divergent"):
            self.run_sync()
        self.assertEqual(self.remote_sha("upstream-main"), divergent)
        self.assertEqual(self.api.calls, [])

    def test_rewritten_upstream_is_reported(self):
        target = self.upstream_change()
        self.run_sync()
        self.develop_again()
        # Fixture deliberately simulates upstream history replacement, never the bot.
        git(self.author, "push", "--force", "origin", self.baseline + ":refs/heads/main")
        with self.assertRaisesRegex(port.PortError, "rewritten|divergent"):
            self.run_sync()
        self.assertEqual(self.remote_sha("upstream-main"), target)

    def test_remote_push_failure_is_propagated(self):
        self.upstream_change()
        git(self.root, "--git-dir=" + str(self.origin), "config", "receive.denyNonFastForwards", "true")
        hook = self.origin / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        hook.chmod(0o755)
        with self.assertRaisesRegex(port.PortError, "push"):
            self.run_sync()
        self.assertEqual(self.api.calls, [])

    def test_api_and_dispatch_failures_are_propagated_and_retryable(self):
        self.upstream_change()
        self.api.fail = "pulls?"
        with self.assertRaisesRegex(port.PortError, "API"):
            self.run_sync()
        self.assertTrue(self.remote_sha("sync/upstream"))
        self.develop_again()
        self.api.fail = "dispatches"
        with self.assertRaisesRegex(port.PortError, "API"):
            self.run_sync()
        self.assertEqual(len(self.api.prs), 1)
        self.develop_again()
        self.api.fail = None
        self.run_sync()
        self.assertEqual(len(self.api.prs), 1)

    def test_dirty_or_wrong_branch_checkout_is_rejected_before_fetch(self):
        (self.repo / "untracked.txt").write_text("keep me", encoding="utf-8")
        with self.assertRaisesRegex(port.PortError, "clean"):
            self.run_sync()
        (self.repo / "untracked.txt").unlink()
        git(self.repo, "checkout", "--detach")
        with self.assertRaisesRegex(port.PortError, "develop"):
            self.run_sync()

    def test_preexisting_merge_is_not_aborted(self):
        head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        (self.repo / ".git/MERGE_HEAD").write_text(self.baseline + "\n", encoding="ascii")
        with self.assertRaisesRegex(port.PortError, "merge"):
            self.run_sync()
        self.assertTrue((self.repo / ".git/MERGE_HEAD").exists())
        self.assertEqual(git(self.repo, "rev-parse", "HEAD").stdout.strip(), head)

    def test_fixed_repository_upstream_and_token_are_required(self):
        for env in ({}, {**self.env, "GITHUB_REPOSITORY": "other/repo"}, {**self.env, "GH_TOKEN": ""}):
            with self.subTest(env=env), self.assertRaises(port.PortError):
                sync.synchronize(self.repo, self.api, env=env)
        git(self.repo, "config", "remote.upstream.url", str(self.upstream))
        with self.assertRaisesRegex(port.PortError, "upstream.*URL"):
            self.run_sync()

    def test_bot_identity_is_filled_when_missing(self):
        self.upstream_change()
        self.run_sync()
        self.assertEqual(git(self.repo, "config", "user.name").stdout.strip(), "github-actions[bot]")
        self.assertIn("github-actions[bot]", git(self.repo, "config", "user.email").stdout)

    def test_already_integrated_target_only_advances_mirror(self):
        target = self.upstream_change()
        git(self.repo, "fetch", "upstream", "main", "--no-tags")
        git(self.repo, "merge", "--no-ff", "--no-edit", target)
        self.write_ledger(ledger_data(target))
        git(self.repo, "add", "docs/upstream-sync.json")
        git(self.repo, "commit", "-m", "explicitly acknowledge port")
        git(self.repo, "push", "origin", "develop")
        before = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.run_sync(), target)
        self.assertEqual(self.remote_sha("upstream-main"), target)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD").stdout.strip(), before)
        self.assertEqual(git(self.repo, "symbolic-ref", "--short", "HEAD").stdout.strip(), "develop")
        self.assertEqual(self.api.calls, [])

    def test_missing_mirror_can_be_created_with_normal_push(self):
        git(self.root, "--git-dir=" + str(self.origin), "update-ref", "-d", "refs/heads/upstream-main")
        target = self.upstream_change()
        self.run_sync()
        self.assertEqual(self.remote_sha("upstream-main"), target)

    def test_sync_branch_push_failure_keeps_mirror_and_skips_pr(self):
        target = self.upstream_change()
        hook = self.origin / "hooks/pre-receive"
        hook.write_text('#!/bin/sh\nwhile read old new ref; do\n  if [ "$ref" = refs/heads/sync/upstream ]; then exit 1; fi\ndone\nexit 0\n', encoding="utf-8")
        hook.chmod(0o755)
        with self.assertRaisesRegex(port.PortError, "push.*sync/upstream"):
            self.run_sync()
        self.assertEqual(self.remote_sha("upstream-main"), target)
        self.assertEqual(self.api.calls, [])

    def test_conflict_issue_api_failure_preserves_rollback(self):
        commit_file(self.repo, "source.txt", "fork change\n")
        git(self.repo, "push", "origin", "develop")
        target = self.upstream_change("source.txt", "upstream incompatible\n")
        self.api.fail = "issues?"
        with self.assertRaisesRegex(port.PortError, "conflict.*issue.*failed"):
            self.run_sync()
        self.assertEqual(git(self.repo, "status", "--porcelain").stdout, "")
        self.assertNotEqual(git(self.repo, "rev-parse", "--verify", "MERGE_HEAD", check=False).returncode, 0)
        self.assertEqual(self.remote_sha("upstream-main"), target)

    def test_existing_human_identity_is_preserved(self):
        git(self.repo, "config", "user.name", "Existing Maintainer")
        git(self.repo, "config", "user.email", "maintainer@example.invalid")
        self.upstream_change()
        self.run_sync()
        self.assertEqual(git(self.repo, "config", "user.name").stdout.strip(), "Existing Maintainer")
        self.assertEqual(git(self.repo, "config", "user.email").stdout.strip(), "maintainer@example.invalid")

    def test_crlf_reference_preserves_upstream_semantic_edit(self):
        # The Flutter migration retained files in CRLF; upstream blobs use LF.
        # An EOL-only fork edit must not make every future source edit conflict.
        (self.repo / "source.txt").write_bytes(b"baseline\r\n")
        git(self.repo, "add", "source.txt")
        git(self.repo, "commit", "-m", "preserve Windows line endings")
        git(self.repo, "push", "origin", "develop")
        target = self.upstream_change("source.txt", "upstream semantic edit\n")
        self.assertEqual(self.run_sync(), target)
        self.assertEqual((self.repo / "source.txt").read_text(), "upstream semantic edit\n")
        self.assertEqual(self.api.issues, [])
        self.assertEqual(len(self.api.prs), 1)

    def test_malformed_ledger_fails_without_pr(self):
        self.upstream_change()
        self.write_ledger({})
        git(self.repo, "add", "docs/upstream-sync.json")
        git(self.repo, "commit", "-m", "malformed ledger")
        git(self.repo, "push", "origin", "develop")
        with self.assertRaisesRegex(port.PortError, "ledger"):
            self.run_sync()
        self.assertEqual(self.api.calls, [])


class GitHubBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(sync, "scripts/upstream_sync.py must provide fixed GitHub API boundary")

    def test_review_pr_preserves_maintainer_notes_across_retries(self):
        api = FakeAPI()
        sync._review_pr(api, "a" * 40, ["a" * 40])
        api.prs[0]["body"] += "\n\nMaintainer review: React-only; no Dart change."
        sync._review_pr(api, "b" * 40, ["a" * 40, "b" * 40])
        body = api.prs[0]["body"]
        self.assertIn("Maintainer review: React-only; no Dart change.", body)
        self.assertIn("b" * 40, body)
        self.assertEqual(body.count("<!-- upstream-sync:begin -->"), 1)
        self.assertEqual(body.count("<!-- upstream-sync:end -->"), 1)

    def test_review_pr_keeps_unmarked_legacy_description(self):
        api = FakeAPI()
        api.prs = [{"number": 3, "draft": True, "body": "Human classification: port parser fix."}]
        sync._review_pr(api, "a" * 40, ["a" * 40])
        self.assertIn("Human classification: port parser fix.", api.prs[0]["body"])
        self.assertIn("<!-- upstream-sync:begin -->", api.prs[0]["body"])

    def test_review_pr_malformed_bot_markers_leave_notes_unchanged(self):
        api = FakeAPI()
        notes = "<!-- upstream-sync:begin -->\nHuman classification: preserve this."
        api.prs = [{"number": 1, "draft": True, "body": notes}]
        with self.assertRaisesRegex(port.PortError, "markers"):
            sync._review_pr(api, "a" * 40, ["a" * 40])
        self.assertEqual(api.prs[0]["body"], notes)
        self.assertFalse(any(method == "PATCH" for method, _, _ in api.calls))

    def test_http_boundary_uses_fixed_repo_token_and_explicit_dispatch(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b""
        opener = mock.Mock(return_value=response)
        api = sync.GitHubAPI("super-secret", opener=opener)
        api.request("POST", "actions/workflows/ci.yml/dispatches", {"ref": "sync/upstream"})
        request = opener.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.github.com/repos/userSigma/morphicons-flutter/actions/workflows/ci.yml/dispatches")
        self.assertEqual(request.get_header("Authorization"), "Bearer super-secret")
        self.assertEqual(json.loads(request.data), {"ref": "sync/upstream"})

    def test_only_selected_endpoints_are_allowed(self):
        opener = mock.Mock()
        api = sync.GitHubAPI("secret", opener=opener)
        for endpoint in ("https://evil.invalid/", "../other", "contents/file", "pulls/1/merge", "issues/1/comments"):
            with self.subTest(endpoint=endpoint), self.assertRaises(port.PortError):
                api.request("POST", endpoint, {})
        opener.assert_not_called()

    def test_http_errors_do_not_output_token_or_server_body(self):
        token = "super-secret-token"
        for error in (HTTPError("https://example.invalid/" + token, 403, token, {}, io.BytesIO(token.encode())),
                      URLError(token), ValueError(token)):
            api = sync.GitHubAPI(token, opener=mock.Mock(side_effect=error))
            with self.subTest(error=error), self.assertRaises(port.PortError) as raised:
                api.request("POST", "actions/workflows/ci.yml/dispatches", {"ref": "sync/upstream"})
            self.assertNotIn(token, str(raised.exception))
            self.assertIn("GitHub", str(raised.exception))

    def test_http_error_response_is_closed(self):
        error = HTTPError("https://example.invalid/", 403, "denied", {}, io.BytesIO(b"private response"))
        error.close = mock.Mock(wraps=error.close)
        api = sync.GitHubAPI("secret", opener=mock.Mock(side_effect=error))
        with self.assertRaises(port.PortError):
            api.request("POST", "actions/workflows/ci.yml/dispatches", {"ref": "sync/upstream"})
        error.close.assert_called_once()

    def test_malformed_pr_creation_response_is_actionable(self):
        api = mock.Mock()
        api.request.side_effect = [[], None]
        with self.assertRaisesRegex(port.PortError, "GitHub.*number"):
            sync._review_pr(api, "a" * 40, [])

    def test_git_error_never_echoes_credential_bearing_stderr(self):
        result = subprocess.CompletedProcess([], 128, "", "fatal: https://secret-token@host.invalid")
        with mock.patch("check_upstream_port.subprocess.run", return_value=result):
            with self.assertRaises(port.PortError) as raised:
                port.Git(ROOT).run("push", "origin", "HEAD:refs/heads/sync/upstream")
        self.assertIn("push", str(raised.exception))
        self.assertNotIn("secret-token", str(raised.exception))

    def test_cli_errors_are_nonzero_without_credential_output(self):
        output, errors = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"GH_TOKEN": "do-not-print-me", "GITHUB_REPOSITORY": "wrong/repo"}), redirect_stdout(output), redirect_stderr(errors):
            self.assertEqual(sync.main([]), 1)
        self.assertNotIn("do-not-print-me", output.getvalue() + errors.getvalue())
        self.assertIn("GITHUB_REPOSITORY", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
