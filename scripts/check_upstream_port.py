#!/usr/bin/env python3
"""Gate the recorded upstream review state, not semantic Dart/TypeScript equivalence.

Run from the repository root after fetching origin/upstream-main. A normal Flutter
PR may lag that mirror: only the upstream history already integrated in HEAD must
be acknowledged. Humans update ported_commit and clear pending_commits after review.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

UPSTREAM_REPOSITORY = "guillermolg00/morphicons"
UPSTREAM_BRANCH = "main"
LEDGER_PATH = "docs/upstream-sync.json"
MIRROR_REF = "refs/remotes/origin/upstream-main"
SHA_PATTERN = re.compile(r"[0-9a-fA-F]{40}\Z")
LEDGER_FIELDS = {"schema_version", "upstream_repository", "upstream_branch",
                 "reference_commit", "ported_commit", "pending_commits"}


class PortError(RuntimeError):
    """An actionable ledger or Git precondition failure."""


class Git:
    """Small captured-output Git boundary; command failures never expose credentials."""

    def __init__(self, root: Path):
        self.root = Path(root)

    def run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        try:
            result = subprocess.run(["git", *args], cwd=self.root, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as exc:
            raise PortError("Git could not start; install Git and verify the checkout path.") from exc
        if check and result.returncode:
            # Git stderr may echo a credential-bearing configured remote URL.
            raise PortError(f"git {' '.join(args)} failed (exit {result.returncode}); "
                            "check repository state, remote access and branch protection.")
        return result

    def commit(self, ref: str) -> str:
        result = self.run("rev-parse", "--verify", ref + "^{commit}", check=False)
        if result.returncode:
            raise PortError(f"{ref} must resolve to a real Git commit.")
        return result.stdout.strip()

    def is_ancestor(self, older: str, newer: str) -> bool:
        result = self.run("merge-base", "--is-ancestor", older, newer, check=False)
        if result.returncode not in (0, 1):
            raise PortError("Git ancestry check failed; fetch complete commit history.")
        return result.returncode == 0


def load_ledger(path: Path) -> dict:
    """Validate the deliberately small, versioned ledger without adding fields."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise PortError(f"Read valid JSON ledger at {LEDGER_PATH} before running this command.") from exc
    if not isinstance(data, dict) or set(data) != LEDGER_FIELDS:
        raise PortError("ledger must contain exactly the six schema_version=1 fields.")
    if type(data["schema_version"]) is not int or data["schema_version"] != 1:
        raise PortError("ledger schema_version must be integer 1.")
    if data["upstream_repository"] != UPSTREAM_REPOSITORY:
        raise PortError(f"ledger upstream_repository must be {UPSTREAM_REPOSITORY}.")
    if data["upstream_branch"] != UPSTREAM_BRANCH:
        raise PortError("ledger upstream_branch must be main.")
    for field in ("reference_commit", "ported_commit"):
        if not isinstance(data[field], str) or not SHA_PATTERN.fullmatch(data[field]):
            raise PortError(f"ledger {field} must be a full 40-hex commit SHA.")
    pending = data["pending_commits"]
    if not isinstance(pending, list) or any(
            not isinstance(sha, str) or not SHA_PATTERN.fullmatch(sha) for sha in pending):
        raise PortError("ledger pending_commits must be an array of full 40-hex SHAs.")
    if len({sha.lower() for sha in pending}) != len(pending):
        raise PortError("ledger pending_commits must not contain duplicate SHAs.")
    return data


def check(root: Path = Path.cwd()) -> dict:
    """Validate acknowledgement and ancestry; this is a state gate only."""
    root = Path(root)
    data = load_ledger(root / LEDGER_PATH)
    if data["pending_commits"]:
        raise PortError("ledger pending_commits is nonempty; review and explicitly acknowledge the Dart port.")
    if data["reference_commit"].lower() != data["ported_commit"].lower():
        raise PortError("ledger ported_commit must equal reference_commit after explicit review.")
    git = Git(root)
    reference = git.commit(data["reference_commit"])
    if not git.is_ancestor(reference, "HEAD"):
        raise PortError("ledger reference_commit must be an ancestor of HEAD.")
    mirror = git.run("rev-parse", "--verify", MIRROR_REF + "^{commit}", check=False)
    if mirror.returncode:
        raise PortError("First fetch origin upstream-main into refs/remotes/origin/upstream-main.")
    merge_base = git.run("merge-base", "HEAD", MIRROR_REF).stdout.strip()
    if reference != merge_base:
        raise PortError("ledger reference_commit differs from merge-base HEAD origin/upstream-main; "
                        "record and review all integrated upstream changes.")
    return data


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    try:
        check(Path.cwd())
    except PortError as exc:
        print(f"Upstream port check failed: {exc}", file=sys.stderr)
        return 1
    print("Upstream acknowledgement state is consistent (not a semantic equivalence proof).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
