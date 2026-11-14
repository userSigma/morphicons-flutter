#!/usr/bin/env python3
"""Integrate fixed upstream history into one persistent draft review branch.

Run only on a trusted, clean develop checkout with full Git history. GH_TOKEN
needs contents/pull-requests/issues/actions write permissions in the selected
fork. The upstream remote must already name UPSTREAM_URL. This command does not
configure remotes, force-push, auto-resolve conflicts, merge PRs, or claim that
TypeScript changes have been ported to Dart. It records review state only.

The working checkout becomes detached while preparing the persistent remote
sync/upstream branch; existing local branches are never reset or rewritten.
Serialize workflow runs to avoid concurrent PR/issue creation. A failed API or
CI dispatch can be retried from a fresh develop checkout without losing history.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

from check_upstream_port import Git, LEDGER_PATH, MIRROR_REF, PortError, load_ledger

REPOSITORY = "userSigma/morphicons-flutter"
UPSTREAM_URL = "https://github.com/guillermolg00/morphicons.git"
API_ROOT = "https://api.github.com/repos/" + REPOSITORY + "/"
BASE_BRANCH = "develop"
SYNC_BRANCH = "sync/upstream"
ISSUE_TITLE = "[upstream-sync] Manual integration required"
DISPATCH_ENDPOINT = "actions/workflows/ci.yml/dispatches"


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHubAPI:
    """Injectable urllib boundary restricted to selected fork review endpoints."""

    def __init__(self, token: str, opener=None):
        self._token = token
        self._open = opener if opener is not None else build_opener(_NoRedirect()).open

    def request(self, method: str, endpoint: str, data=None):
        allowed = ((method == "GET" and re.fullmatch(r"(?:pulls|issues)\?[a-zA-Z0-9_%=&:+./-]+", endpoint))
                   or (method == "POST" and endpoint in ("pulls", "issues", DISPATCH_ENDPOINT))
                   or (method == "PATCH" and re.fullmatch(r"(?:pulls|issues)/[1-9][0-9]*", endpoint)))
        if not allowed:
            raise PortError("GitHub endpoint/method is outside the fixed review API allowlist.")
        request = Request(API_ROOT + endpoint, method=method,
                          data=None if data is None else json.dumps(data).encode("utf-8"),
                          headers={"Authorization": "Bearer " + self._token,
                                   "Accept": "application/vnd.github+json",
                                   "Content-Type": "application/json",
                                   "X-GitHub-Api-Version": "2022-11-28",
                                   "User-Agent": "morphicons-upstream-sync"})
        try:
            with self._open(request, timeout=30) as response:
                body = response.read()
            return json.loads(body) if body else None
        except HTTPError as exc:
            exc.close()
            raise PortError(f"GitHub {method} {endpoint} returned HTTP {exc.code}; "
                            "verify token permissions, workflow availability and repository settings; retry.") from None
        except (URLError, OSError, ValueError) as exc:
            # Never echo a URL, token, response body, or third-party exception text.
            raise PortError(f"GitHub {method} {endpoint} failed; check connectivity and API response, then retry.") from None


def _pages(api, collection: str, **filters):
    page = 1
    while True:
        endpoint = collection + "?" + urlencode({**filters, "per_page": 100, "page": page})
        items = api.request("GET", endpoint)
        if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
            raise PortError(f"GitHub {collection} response must be a list; retry after checking API availability.")
        yield from items
        if len(items) < 100:
            return
        page += 1


def _number(item: dict) -> int:
    number = item.get("number") if isinstance(item, dict) else None
    if type(number) is not int or number < 1:
        raise PortError("GitHub response is missing a valid issue/PR number; inspect the API result and retry.")
    return number


def _conflict_issue(api, target: str, paths: list[str]):
    matches = [item for item in _pages(api, "issues", state="open")
               if item.get("title") == ISSUE_TITLE and "pull_request" not in item]
    if len(matches) > 1:
        raise PortError("Multiple upstream-sync manual integration issues exist; consolidate them and retry.")
    body = (f"Upstream target: `{target}`\n\n"
            "The script-created merge was aborted; the remote sync/upstream branch was preserved.\n"
            "The target is available on upstream-main. Integrate manually and review the Dart port.\n\n"
            "Conflicting paths:\n" + "\n".join("- `" + path + "`" for path in paths))
    data = {"title": ISSUE_TITLE, "body": body}
    if matches:
        api.request("PATCH", f"issues/{_number(matches[0])}", data)
    else:
        _number(api.request("POST", "issues", data))


def _merge(git: Git, ref: str, target: str, api):
    # Guard at the operation boundary as well as at startup: abort only our merge.
    if git.run("rev-parse", "--verify", "MERGE_HEAD", check=False).returncode == 0:
        raise PortError("An existing merge is in progress; finish it before rerunning upstream sync.")
    # Normalize historic CRLF/LF differences only for this merge, not repository
    # configuration or existing files. Never select ours/theirs for real conflicts.
    result = git.run("-c", "commit.gpgsign=false", "-c", "merge.renormalize=true",
                     "-c", "core.autocrlf=input", "merge", "--no-ff", "--no-edit", ref, check=False)
    if result.returncode == 0:
        return
    owned_merge = git.run("rev-parse", "--verify", "MERGE_HEAD", check=False).returncode == 0
    paths = git.run("diff", "--name-only", "--diff-filter=U", "-z").stdout.split("\0")
    paths = [path for path in paths if path]
    if owned_merge:
        git.run("merge", "--abort")
    if paths and owned_merge:
        try:
            _conflict_issue(api, target, paths)
        except PortError as exc:
            raise PortError(f"Merge conflict aborted, but manual integration issue update failed: {exc}") from None
        raise PortError("Merge conflict aborted; use the manual integration issue and upstream-main target.")
    raise PortError("Git merge failed; inspect commit identity, repository history and merge configuration; retry.")


def _review_pr(api, target: str, pending: list[str]):
    prs = list(_pages(api, "pulls", state="open", head="userSigma:" + SYNC_BRANCH, base=BASE_BRANCH))
    if len(prs) > 1:
        raise PortError("Multiple sync/upstream PRs exist; consolidate to one draft PR and retry.")
    data = {"title": "[upstream-sync] Review upstream " + target[:12],
            "body": (f"Reference upstream target: `{target}`\n\n"
                     "TypeScript reference history has been integrated, not automatically ported to Dart.\n"
                     "Review every pending commit, port applicable changes, and explicitly acknowledge\n"
                     "docs/upstream-sync.json before merging. No automatic merge is performed.\n\n"
                     "Pending upstream commits:\n" + "\n".join("- `" + sha + "`" for sha in pending))}
    begin, end = "<!-- upstream-sync:begin -->", "<!-- upstream-sync:end -->"
    block = begin + "\n" + data["body"] + "\n" + end
    data["body"] = block
    if prs:
        if prs[0].get("draft") is not True:
            raise PortError("Existing sync/upstream PR must be converted back to draft before retrying.")
        existing = prs[0].get("body") or ""
        if not isinstance(existing, str):
            raise PortError("Existing PR body must be text; inspect the API response before retrying.")
        if begin in existing or end in existing:
            start, finish = existing.find(begin), existing.find(end)
            if existing.count(begin) != 1 or existing.count(end) != 1 or finish < start:
                raise PortError("PR bot markers are malformed; repair the pair while preserving review notes.")
            data["body"] = existing[:start] + block + existing[finish + len(end):]
        elif existing:
            # Adopt unmarked descriptions without deleting earlier human review.
            data["body"] = block + "\n\n" + existing
        api.request("PATCH", f"pulls/{_number(prs[0])}", data)
    else:
        _number(api.request("POST", "pulls", {**data, "head": SYNC_BRANCH, "base": BASE_BRANCH, "draft": True}))
    # GITHUB_TOKEN-created PRs do not trigger pull_request CI events.
    api.request("POST", DISPATCH_ENDPOINT, {"ref": SYNC_BRANCH})


def _environment(env) -> str:
    if env.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise PortError("GITHUB_REPOSITORY must be exactly " + REPOSITORY + ".")
    token = env.get("GH_TOKEN", "")
    if not token or not token.strip():
        raise PortError("Set GH_TOKEN with contents, pull-requests, issues and actions write permissions.")
    return token


def synchronize(root: Path, api=None, *, env=None, git=None) -> str:
    """Merge one upstream snapshot, maintaining an append-only remote sync history."""
    env = os.environ if env is None else env
    token = _environment(env)
    api = GitHubAPI(token) if api is None else api
    root = Path(root)
    git = Git(root) if git is None else git
    if git.run("rev-parse", "--verify", "MERGE_HEAD", check=False).returncode == 0:
        raise PortError("An existing merge is in progress; finish it before running upstream sync.")
    if git.run("status", "--porcelain", "--untracked-files=all").stdout:
        raise PortError("A clean checkout (including untracked files) is required; preserve local work first.")
    if git.run("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip() != BASE_BRANCH:
        raise PortError("Start upstream sync from a trusted develop checkout.")
    if git.run("config", "--get", "remote.upstream.url", check=False).stdout.strip() != UPSTREAM_URL:
        raise PortError("The upstream remote URL must be exactly " + UPSTREAM_URL + "; ask the repository owner to configure it.")
    load_ledger(root / LEDGER_PATH)
    git.run("fetch", "upstream", "main", "--no-tags")
    target = git.commit("FETCH_HEAD")  # Freeze the full SHA before fetching anything else.
    heads = git.run("ls-remote", "--heads", "origin", "refs/heads/develop",
                    "refs/heads/upstream-main", "refs/heads/sync/upstream").stdout
    remote_branches = {line.split()[1].removeprefix("refs/heads/") for line in heads.splitlines() if line.strip()}
    if BASE_BRANCH not in remote_branches:
        raise PortError("origin/develop is missing; create the trusted base branch before syncing.")
    git.run("fetch", "origin", "--no-tags", *(
        f"refs/heads/{branch}:refs/remotes/origin/{branch}" for branch in sorted(remote_branches)))
    base = git.commit("refs/remotes/origin/develop")
    if "upstream-main" in remote_branches:
        mirror = git.commit(MIRROR_REF)
        if not git.is_ancestor(mirror, target):
            raise PortError("Upstream history was rewritten or origin/upstream-main is divergent; "
                            "inspect both histories and repair the mirror manually; no force push was attempted.")
    else:
        baseline = load_ledger(root / LEDGER_PATH)["reference_commit"]
        if not git.is_ancestor(git.commit(baseline), target):
            raise PortError("Upstream history was rewritten relative to the ledger; inspect before creating the mirror.")
    git.run("push", "origin", target + ":refs/heads/upstream-main")
    # Keep the required checker's mirror ref current even for a newly created mirror.
    git.run("fetch", "origin", "--no-tags", "refs/heads/upstream-main:" + MIRROR_REF)
    if git.is_ancestor(target, base):
        return target  # Mirror update only: leave local/remote sync branches and PRs alone.
    for key, value in (("user.name", "github-actions[bot]"),
                       ("user.email", "41898282+github-actions[bot]@users.noreply.github.com")):
        if not git.run("config", "--get", key, check=False).stdout.strip():
            git.run("config", "--local", key, value)
    start = git.commit("refs/remotes/origin/sync/upstream") if SYNC_BRANCH in remote_branches else base
    git.run("checkout", "--detach", start)
    _merge(git, base, target, api)
    _merge(git, target, target, api)
    data = load_ledger(root / LEDGER_PATH)
    for field in ("reference_commit", "ported_commit"):
        if not git.is_ancestor(git.commit(data[field]), target):
            raise PortError(f"ledger {field} is outside the upstream target history; review it manually before retrying.")
    pending = git.run("rev-list", "--reverse", "--topo-order", target, "^" + data["ported_commit"]).stdout.splitlines()
    data["reference_commit"] = target
    data["pending_commits"] = pending
    try:
        (root / LEDGER_PATH).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        raise PortError("Writing docs/upstream-sync.json failed; check file permissions and retry.") from exc
    git.run("add", "--", LEDGER_PATH)
    changed = git.run("diff", "--cached", "--quiet", check=False)
    if changed.returncode not in (0, 1):
        raise PortError("Checking the staged ledger failed; inspect the Git index before retrying.")
    if changed.returncode == 1:
        git.run("-c", "commit.gpgsign=false", "commit", "-m", "chore: record upstream review target " + target[:12])
    git.run("push", "origin", "HEAD:refs/heads/" + SYNC_BRANCH)
    _review_pr(api, target, pending)
    return target


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    try:
        target = synchronize(Path.cwd())
    except PortError as exc:
        message = str(exc)
        for key in ("GH_TOKEN", "GITHUB_TOKEN"):
            if os.environ.get(key):
                message = message.replace(os.environ[key], "[REDACTED]")
        print("Upstream sync failed: " + message, file=sys.stderr)
        return 1
    print("Upstream snapshot processed: " + target + "; Dart review state remains explicit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
