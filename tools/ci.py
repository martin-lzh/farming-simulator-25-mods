"""Validate, test and package FS25 Mods; release them through tools/modrelease.py."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import changes
import modrelease

ROOT = Path(__file__).resolve().parents[1]
MODS = {
    "animal-products-manager": "AnimalProductsManager",
    "fill-type-selector": "FillTypeSelector",
    "map-helper": "MapHelper",
    "production-overflow": "ProductionOverflow",
}
VERSION = r"(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){3}"
GAME = "Farming Simulator 25 1.25 (PC)"
# Files that never enter a package and never affect validation or tests; CI skips
# build and test when a change touches only these (tools/changes.py). Packages hold
# only .lua, .xml and .dds files, so Mod images can never be packaged. The Mod
# README and CHANGELOG are validated, so they stay core.
NON_CORE = (
    "README.md", "AGENTS.md", "DEVELOPMENT.md", "docs/**", "assets/**", "releases/**",
    "*-mod/DEVELOPMENT.md", "*-mod/assets/**/*.png", "*-mod/assets/**/*.jpg",
)


def run(*args) -> None:
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def changelog(text: str, version: str) -> tuple[str | None, bool]:
    """Return the entry for `version` and whether Unreleased has content; history must be descending."""
    headings = list(re.finditer(r"^## (.+)$", text, re.M))
    notes, unreleased, history = None, False, []
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        content = re.sub(r"<!--.*?-->", "", text[heading.end():end], flags=re.S).strip()
        title = heading[1].strip()
        if title == "Unreleased":
            unreleased = bool(content)
            continue
        match = re.match(rf"({VERSION})(?:\s|$)", title)
        if not match:
            raise ValueError(f"Unexpected CHANGELOG heading: {title}")
        history.append(match[1])
        if match[1] == version:
            notes = f"## {title}\n\n{content}" if content else None
    keys = [tuple(map(int, v.split("."))) for v in history]
    if not history or keys != sorted(set(keys), reverse=True):
        raise ValueError("CHANGELOG versions must be unique and descending")
    if history[0] != version:
        raise ValueError(f"CHANGELOG starts at {history[0]}, but modDesc.xml says {version}")
    return notes, unreleased


def config(slug: str) -> dict:
    directory = ROOT / f"{slug}-mod"
    version = ET.parse(directory / "modDesc.xml").getroot().findtext("version")
    if not version or not re.fullmatch(VERSION, version):
        raise ValueError(f"{slug}: modDesc.xml needs a four-part version")
    settings = json.loads((directory / "release.json").read_text(encoding="utf-8"))
    if (set(settings) != {"displayName", "prerelease"} or type(settings["prerelease"]) is not bool
            or not isinstance(settings["displayName"], str) or not settings["displayName"].strip()):
        raise ValueError(f"{slug}: release.json needs displayName and prerelease")
    notes, unreleased = changelog((directory / "CHANGELOG.md").read_text(encoding="utf-8"), version)
    readme = (directory / "README.md").read_text(encoding="utf-8")
    if not re.search(rf"(?<![\d.]){re.escape(version)}(?![\d])", readme):
        raise ValueError(f"{slug}: README does not mention version {version}")
    return dict(slug=slug, name=MODS[slug], directory=directory, version=version, notes=notes,
                unreleased=unreleased, display_name=settings["displayName"], prerelease=settings["prerelease"],
                archive=f"FS25_{MODS[slug]}.zip")


def validate() -> None:
    for slug in MODS:
        c = config(slug)
        print(f'{slug} {c["version"]}')


def build() -> None:
    validate()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    for slug in MODS:
        c = config(slug)
        run("uv", "run", f"{slug}-mod/tests/run.py")
        run(sys.executable, f"{slug}-mod/tools/build.py")
        target = ROOT / "outputs/ci" / slug
        target.mkdir(parents=True, exist_ok=True)
        archive = target / c["archive"]
        shutil.copyfile(ROOT / "outputs" / c["archive"], archive)
        evidence = dict(source=commit, mod=slug, version=c["version"],
                        archiveSha256=hashlib.sha256(archive.read_bytes()).hexdigest())
        (target / "build-info.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"CI package: {archive}")


def release_assets(c: dict) -> tuple[Path, ...]:
    return (ROOT / "outputs/ci" / c["slug"] / c["archive"],)


def verify_artifacts(c: dict, commit: str) -> None:
    """The CI package must come from this commit and carry this version's modDesc.xml."""
    directory = ROOT / "outputs/ci" / c["slug"]
    archive = directory / c["archive"]
    evidence = json.loads((directory / "build-info.json").read_text(encoding="utf-8"))
    if (evidence.get("source") != commit or evidence.get("version") != c["version"]
            or evidence.get("archiveSha256") != hashlib.sha256(archive.read_bytes()).hexdigest()):
        raise ValueError(f'{c["slug"]}: build evidence does not match the release source')
    with ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError(f"{archive.name}: ZIP integrity check failed")
        if ET.fromstring(package.read("modDesc.xml")).findtext("version") != c["version"]:
            raise ValueError(f"{archive.name}: packaged modDesc.xml has a different version")
        for name in package.namelist():
            if Path(name).suffix not in {".lua", ".xml", ".dds"} or name.startswith(("/", "..")):
                raise ValueError(f"{archive.name}: unexpected package entry {name}")


def release_mods(repository: str) -> list[modrelease.ModRelease]:
    mods = []
    for slug in MODS:
        c = config(slug)
        mods.append(modrelease.ModRelease(
            slug=slug, display_name=c["display_name"], version=c["version"], prerelease=c["prerelease"],
            notes=c["notes"], unreleased=c["unreleased"], assets=release_assets(c), summary=GAME,
            readme_url=f"https://github.com/{repository}/blob/main/{slug}-mod/README.md"))
    return mods


def publish(repository: str, commit: str, api=None) -> None:
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if actual != commit:
        raise ValueError("Checkout differs from release commit")
    for slug in MODS:
        verify_artifacts(config(slug), commit)
    modrelease.publish(api or modrelease.GitHub(repository), release_mods(repository), commit)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "build", "changes", "release-plan", "publish"])
    parser.add_argument("--repository")
    parser.add_argument("--commit")
    parser.add_argument("--base", help="changes: commit to compare from (omit to treat everything as changed)")
    parser.add_argument("--head", help="changes: commit to compare to")
    parser.add_argument("--merge-base", action="store_true", help="changes: compare from the merge base (pull requests)")
    args = parser.parse_args()
    if args.command == "validate":
        validate()
    elif args.command == "build":
        build()
    elif args.command == "changes":
        changes.main(ROOT, NON_CORE, args.base, args.head, args.merge_base)
    elif args.command == "release-plan":
        if not args.repository:
            parser.error("release-plan requires --repository")
        decisions = modrelease.check(modrelease.GitHub(args.repository), release_mods(args.repository))
        changes.write_outputs({"release": any(d.action in ("publish", "promote") for d in decisions)})
    else:
        if not args.repository or not args.commit:
            parser.error("publish requires --repository and --commit")
        publish(args.repository, args.commit)


if __name__ == "__main__":
    main()
