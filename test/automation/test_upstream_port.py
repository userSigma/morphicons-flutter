"""Real Git fixtures for the upstream acknowledgement state gate (no network)."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
try:
    import check_upstream_port as port
except ModuleNotFoundError:
    port = None


def git(path, *args, check=True):
    env = os.environ.copy()
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_TERMINAL_PROMPT="0", GIT_AUTHOR_NAME="Test Author",
               GIT_AUTHOR_EMAIL="test@example.invalid", GIT_COMMITTER_NAME="Test Author",
               GIT_COMMITTER_EMAIL="test@example.invalid")
    result = subprocess.run(["git", "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false",
                             *args], cwd=path, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise AssertionError(f"fixture git {args}: {result.stderr}")
    return result


def commit_file(path, name, contents, message="fixture change"):
    target = path / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents, encoding="utf-8", newline="\n")
    git(path, "add", name)
    git(path, "commit", "-m", message)
    return git(path, "rev-parse", "HEAD").stdout.strip()


def ledger_data(sha):
    return {"schema_version": 1, "upstream_repository": "guillermolg00/morphicons",
            "upstream_branch": "main", "reference_commit": sha,
            "ported_commit": sha, "pending_commits": []}


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="upstream-automation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "work"
        self.repo.mkdir()
        git(self.repo, "init", "--initial-branch=main")
        self.baseline = commit_file(self.repo, "source.txt", "baseline\n")
        self.ledger = self.repo / "docs/upstream-sync.json"
        self.write_ledger(ledger_data(self.baseline))
        git(self.repo, "add", "docs/upstream-sync.json")
        git(self.repo, "commit", "-m", "record reviewed upstream")
        git(self.repo, "update-ref", "refs/remotes/origin/upstream-main", self.baseline)

    def write_ledger(self, data):
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        self.ledger.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


class UpstreamPortTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.assertIsNotNone(port, "scripts/check_upstream_port.py must implement the state gate")

    def test_baseline_is_acknowledged(self):
        self.assertEqual(port.check(self.repo)["reference_commit"], self.baseline)

    def test_pending_commits_require_explicit_acknowledgement(self):
        data = ledger_data(self.baseline)
        data["pending_commits"] = [self.baseline]
        self.write_ledger(data)
        with self.assertRaisesRegex(port.PortError, "pending_commits"):
            port.check(self.repo)

    def test_reference_and_ported_must_match(self):
        data = ledger_data(self.baseline)
        data["ported_commit"] = "f" * 40
        self.write_ledger(data)
        with self.assertRaisesRegex(port.PortError, "ported_commit"):
            port.check(self.repo)

    def test_malformed_ledger_schema_and_shas(self):
        cases = [[], {}, {**ledger_data(self.baseline), "schema_version": True},
                 {**ledger_data(self.baseline), "upstream_repository": "other/repo"},
                 {**ledger_data(self.baseline), "upstream_branch": "develop"},
                 {**ledger_data(self.baseline), "reference_commit": "abc"},
                 {**ledger_data(self.baseline), "ported_commit": 7},
                 {**ledger_data(self.baseline), "pending_commits": ""},
                 {**ledger_data(self.baseline), "pending_commits": ["not-sha"]},
                 {**ledger_data(self.baseline), "extra": True}]
        for data in cases:
            with self.subTest(data=data):
                self.write_ledger(data)
                with self.assertRaises(port.PortError):
                    port.check(self.repo)
        self.ledger.write_text("{bad json", encoding="utf-8")
        with self.assertRaisesRegex(port.PortError, "JSON"):
            port.check(self.repo)

    def test_missing_ledger_is_actionable(self):
        self.ledger.unlink()
        with self.assertRaisesRegex(port.PortError, "docs/upstream-sync.json"):
            port.check(self.repo)

    def test_reference_must_be_real_commit(self):
        self.write_ledger(ledger_data("f" * 40))
        with self.assertRaisesRegex(port.PortError, "commit"):
            port.check(self.repo)

    def test_reference_must_be_ancestor_of_head(self):
        later = commit_file(self.repo, "later.txt", "later\n")
        git(self.repo, "checkout", "--detach", self.baseline)
        self.write_ledger(ledger_data(later))
        with self.assertRaisesRegex(port.PortError, "ancestor"):
            port.check(self.repo)

    def test_mirror_is_required(self):
        git(self.repo, "update-ref", "-d", "refs/remotes/origin/upstream-main")
        with self.assertRaisesRegex(port.PortError, "fetch.*upstream-main"):
            port.check(self.repo)

    def test_normal_flutter_change_may_lag_latest_mirror(self):
        old_head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        git(self.repo, "checkout", "--detach", self.baseline)
        later = commit_file(self.repo, "upstream.txt", "new upstream\n")
        git(self.repo, "update-ref", "refs/remotes/origin/upstream-main", later)
        git(self.repo, "checkout", "--detach", old_head)
        self.assertEqual(port.check(self.repo)["reference_commit"], self.baseline)

    def test_upstream_merge_without_ledger_update_is_detected(self):
        later = commit_file(self.repo, "upstream.txt", "new upstream\n")
        git(self.repo, "update-ref", "refs/remotes/origin/upstream-main", later)
        with self.assertRaisesRegex(port.PortError, "merge-base"):
            port.check(self.repo)

    def test_cli_reports_state_gate_failure(self):
        self.write_ledger({})
        result = subprocess.run([sys.executable, str(ROOT / "scripts/check_upstream_port.py")],
                                cwd=self.repo, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ledger", result.stderr)


if __name__ == "__main__":
    unittest.main()
