"""Plan and publish GitHub Releases for a multi-Mod repository.

This file is shared verbatim by the Old Market Simulator, Parisian Bistro
Simulator and Farming Simulator 25 Mod repositories; change it in all three.
Each repository's tools/ci.py builds and verifies its own packages, then
describes every Mod as a ModRelease. This module decides what happens on main:

- a numbered version without a release is published (merging is the approval);
- a beta release whose release.json now says "prerelease": false is promoted;
- everything else is left untouched, and published assets are never replaced.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

NUMBERED = re.compile(r"(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){2,3}")
COMMIT = re.compile(r"[0-9a-f]{40}")


@dataclass(frozen=True)
class ModRelease:
    slug: str
    display_name: str
    version: str
    prerelease: bool
    notes: str | None      # CHANGELOG entry for `version`, or None when it has none
    unreleased: bool       # the Unreleased section has content
    assets: tuple[Path, ...]
    summary: str           # e.g. "Old Market Simulator 2.1.6 · BepInEx 5"
    readme_url: str

    @property
    def tag(self) -> str:
        return f"{self.slug}-v{self.version}"


@dataclass(frozen=True)
class Decision:
    mod: ModRelease
    action: str            # publish, promote, current, waiting, skip, error
    reason: str
    release: dict | None = None


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def plan(mods: list[ModRelease], releases: list[dict], tags: set[str]) -> list[Decision]:
    by_tag = {r["tag_name"]: r for r in releases}
    decisions = []
    for mod in mods:
        decisions.append(_decide(mod, by_tag, releases, tags))
    return decisions


def _decide(mod: ModRelease, by_tag: dict, releases: list[dict], tags: set[str]) -> Decision:
    if not NUMBERED.fullmatch(mod.version):
        return Decision(mod, "skip", "development version; not released")
    release = by_tag.get(mod.tag)
    if release and not release["draft"]:
        if release["prerelease"] and not mod.prerelease:
            return Decision(mod, "promote", "beta becomes a stable release", release)
        if not release["prerelease"] and mod.prerelease:
            return Decision(mod, "error", f"{mod.tag} is already stable; set prerelease to false in release.json")
        if mod.unreleased:
            return Decision(mod, "waiting", "Unreleased changes wait for the next version")
        return Decision(mod, "current", "already released")
    prefix = mod.slug + "-v"
    published = [r["tag_name"][len(prefix):] for r in releases
                 if not r["draft"] and r["tag_name"].startswith(prefix)
                 and NUMBERED.fullmatch(r["tag_name"][len(prefix):])]
    newest = max(published, key=version_key, default=None)
    if newest and version_key(newest) >= version_key(mod.version):
        return Decision(mod, "error", f"version {mod.version} is not newer than published {newest}")
    if mod.tag in tags and not release:
        return Decision(mod, "error", f"tag {mod.tag} exists without a release")
    if not mod.notes or not mod.notes.strip():
        return Decision(mod, "error", f"CHANGELOG has no entry for {mod.version}")
    if re.search(rf"^#+ [^\n]*{re.escape(mod.version)}[^\n]*[(（]", mod.notes, re.M):
        return Decision(mod, "error", "keep the CHANGELOG heading to the version and date; release state lives in release.json")
    if mod.unreleased:
        return Decision(mod, "error", f"move the Unreleased entries into {mod.version} before merging")
    if not mod.assets:
        return Decision(mod, "error", "no built package to attach")
    kind = "beta" if mod.prerelease else "stable release"
    return Decision(mod, "publish", f"new {kind}", release)


def release_title(mod: ModRelease) -> str:
    return f"{mod.display_name} {mod.version}"


def release_body(mod: ModRelease) -> str:
    zips = [f"**{p.name}**" for p in mod.assets if p.suffix == ".zip"]
    if len(zips) > 1:
        en = f"the ZIP for your loader ({' or '.join(zips)})"
        zh = f"与你的加载器对应的 ZIP（{' 或 '.join(zips)}）"
    else:
        en = zips[0] if zips else "the Mod ZIP"
        zh = f" {en}" if zips else " Mod ZIP"
    lines = [f"**{mod.display_name} {mod.version}** · {mod.summary}", ""]
    if mod.prerelease:
        lines += ["Beta for early testers. / 测试版，供少量玩家提前试用。", ""]
    lines += [f"Download {en} below (not \"Source code\") and follow the [install guide]({mod.readme_url}).",
              f"请从下方 Assets 下载{zh}，不要下载 Source code；安装方法见[安装说明]({mod.readme_url})。",
              "", mod.notes.strip(), ""]
    return "\n".join(lines)


def checksums(files: dict[str, bytes]) -> bytes:
    return "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, data in files.items()).encode()


def release_files(mod: ModRelease) -> dict[str, bytes]:
    files = {}
    for path in mod.assets:
        if path.name in files or path.name == "SHA256SUMS.txt":
            raise ValueError(f"Duplicate release asset name: {path.name}")
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing release asset: {path}")
        files[path.name] = path.read_bytes()
    files["SHA256SUMS.txt"] = checksums(files)
    return files


ICONS = {"publish": "🚀 publish", "promote": "⬆️ promote", "current": "✅ current",
         "waiting": "📝 waiting", "skip": "⏭️ skip", "error": "❌ error"}


def report(decisions: list[Decision]) -> None:
    rows = ["| Mod | Version | Result | Reason |", "| --- | --- | --- | --- |"]
    for d in decisions:
        rows.append(f"| {d.mod.display_name} | {d.mod.version} | {ICONS[d.action]} | {d.reason} |")
        if d.action == "error":
            print(f"::error title={d.mod.slug}::{d.reason}")
        elif d.action in ("publish", "promote"):
            print(f"::notice title={d.mod.slug}::{d.mod.tag}: {d.reason}")
        else:
            print(f"{d.mod.tag}: {d.action} ({d.reason})")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write("### Release plan\n\n" + "\n".join(rows) + "\n")


class _AssetRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlparse(newurl).scheme != "https":
            raise ValueError("Refusing non-HTTPS asset redirect")
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None and urllib.parse.urlparse(req.full_url).hostname != urllib.parse.urlparse(newurl).hostname:
            result.remove_header("Authorization")
        return result


class GitHub:
    def __init__(self, repository: str, token: str | None = None):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
            raise ValueError("Invalid repository")
        self.base = f"https://api.github.com/repos/{repository}"
        self.upload_base = f"https://uploads.github.com/repos/{repository}/releases/"
        self.token = token or os.environ["GH_TOKEN"]
        self.opener = urllib.request.build_opener(_AssetRedirect())

    def request(self, path, method="GET", payload=None, raw=False, missing_ok=False):
        url = path if path.startswith("https://") else self.base + path
        if not (url == self.base or url.startswith(self.base + "/") or url.startswith(self.upload_base)):
            raise ValueError("Unexpected GitHub endpoint")
        data = payload if isinstance(payload, bytes) else None if payload is None else json.dumps(payload).encode()
        headers = {"Authorization": f"Bearer {self.token}",
                   "Accept": "application/octet-stream" if raw else "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28"}
        if data is not None:
            headers["Content-Type"] = "application/octet-stream" if isinstance(payload, bytes) else "application/json"
        try:
            with self.opener.open(urllib.request.Request(url, data, headers, method=method), timeout=120) as response:
                content = response.read()
                return content if raw else json.loads(content) if content else None
        except urllib.error.HTTPError as error:
            if error.code == 404 and method == "GET" and missing_ok:
                return None
            raise

    def pages(self, path):
        result = []
        for page in range(1, 101):
            batch = self.request(f"{path}?per_page=100&page={page}")
            if not isinstance(batch, list):
                raise ValueError("Invalid GitHub pagination response")
            result.extend(batch)
            if len(batch) < 100:
                return result
        raise ValueError("GitHub pagination limit exceeded")

    def tag_commit(self, tag: str) -> str | None:
        ref = self.request(f"/git/ref/tags/{tag}", missing_ok=True)
        if ref is None:
            return None
        obj = ref["object"]
        for _ in range(8):
            if obj["type"] == "commit":
                return obj["sha"]
            if obj["type"] != "tag":
                break
            obj = self.request(f"/git/tags/{obj['sha']}")["object"]
        raise ValueError(f"Invalid release tag: {tag}")


def remote_tags(api) -> set[str]:
    # matching-refs returns every match in one response; it is not paginated.
    refs = api.request("/git/matching-refs/tags") or []
    return {ref["ref"].removeprefix("refs/tags/") for ref in refs}


def check(api, mods: list[ModRelease]) -> list[Decision]:
    """Read-only plan for pull requests and pushes; fails on errors."""
    decisions = plan(mods, api.pages("/releases"), remote_tags(api))
    report(decisions)
    errors = [d for d in decisions if d.action == "error"]
    if errors:
        raise SystemExit(f"Release plan has {len(errors)} error(s); see the table above.")
    return decisions


def publish(api, mods: list[ModRelease], commit: str) -> None:
    """Publish new versions and promote betas; finish valid Mods before failing."""
    if not COMMIT.fullmatch(commit):
        raise ValueError("Publishing requires an exact commit SHA")
    decisions = plan(mods, api.pages("/releases"), remote_tags(api))
    report(decisions)
    failures = [f"{d.mod.slug}: {d.reason}" for d in decisions if d.action == "error"]
    for d in decisions:
        try:
            if d.action == "publish":
                _publish_one(api, d, commit)
            elif d.action == "promote":
                api.request(f"/releases/{d.release['id']}", "PATCH",
                            {"prerelease": False, "body": release_body(d.mod), "make_latest": "false"})
                print(f"Promoted {d.mod.tag} to a stable release.")
        except Exception as error:  # keep going so one Mod cannot block the others
            failures.append(f"{d.mod.slug}: {error}")
    if failures:
        raise SystemExit("Release failures:\n" + "\n".join(failures))


def _publish_one(api, d: Decision, commit: str) -> None:
    mod, tag = d.mod, d.mod.tag
    files = release_files(mod)
    title, body = release_title(mod), release_body(mod)
    draft = d.release
    target = api.tag_commit(tag)
    if draft:
        if draft["target_commitish"] != commit or draft["body"] != body or draft["prerelease"] != mod.prerelease \
                or target not in (None, commit):
            raise ValueError(f"Draft {tag} belongs to different source or notes; inspect it on GitHub")
    else:
        if target is not None:
            raise ValueError(f"Tag {tag} exists without a release")
        draft = api.request("/releases", "POST", {
            "tag_name": tag, "target_commitish": commit, "name": title, "body": body,
            "draft": True, "prerelease": mod.prerelease, "make_latest": "false"})
    assets = {a["name"]: a for a in api.pages(f"/releases/{draft['id']}/assets")}
    if set(assets) - set(files):
        raise ValueError(f"Unexpected assets in draft {tag}")
    for name, data in files.items():
        asset = assets.get(name)
        if asset is None:
            url = draft["upload_url"].split("{")[0] + "?name=" + urllib.parse.quote(name)
            asset = api.request(url, "POST", data)
        if api.request(f"/releases/assets/{asset['id']}", raw=True) != data:
            raise ValueError(f"Uploaded asset differs: {name}; draft kept for inspection")
    current = api.request(f"/releases/{draft['id']}")
    if not current["draft"] or current["tag_name"] != tag or current["target_commitish"] != commit:
        raise ValueError(f"Draft {tag} changed during publication")
    api.request(f"/releases/{draft['id']}", "PATCH", {"draft": False, "make_latest": "false"})
    if api.tag_commit(tag) != commit:
        raise ValueError(f"Published tag {tag} does not point at {commit}")
    print(f"Published {tag} at {commit}.")
