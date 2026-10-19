"""Decide which CI jobs a change needs, from the files it touches.

This file is shared verbatim by the Old Market Simulator, Parisian Bistro
Simulator and Farming Simulator 25 Mod repositories; change it in all three.
Each repository's tools/ci.py lists its own NON_CORE patterns: files that never
enter a package and never affect validation or tests. Every other file is core,
and a change whose files cannot be determined counts as a core change.
"""
from __future__ import annotations

from fnmatch import fnmatchcase
import os
from pathlib import Path
import re
import subprocess

COMMIT = re.compile(r"[0-9a-f]{40}")


def matches(path: str, pattern: str) -> bool:
    """Match a repository path against a pattern; `*` stays within a folder, `**` spans folders."""
    def match(parts: list[str], patterns: list[str]) -> bool:
        if not patterns:
            return not parts
        if patterns[0] == "**":
            return any(match(parts[index:], patterns[1:]) for index in range(len(parts) + 1))
        return bool(parts) and fnmatchcase(parts[0], patterns[0]) and match(parts[1:], patterns[1:])
    return match(path.split("/"), pattern.split("/"))


def is_core(path: str, non_core: tuple[str, ...]) -> bool:
    return not any(matches(path, pattern) for pattern in non_core)


def changed_files(root: Path, base: str | None, head: str | None, merge_base: bool = False) -> list[str] | None:
    """Files changed between two commits (both sides of a rename), or None when unknown."""
    if not base or not head or not COMMIT.fullmatch(base) or not COMMIT.fullmatch(head) or not base.strip("0"):
        return None
    revisions = [f"{base}...{head}"] if merge_base else [base, head]
    result = subprocess.run(["git", "diff", "--name-only", "--no-renames", "-z", *revisions, "--"],
                            cwd=root, capture_output=True)
    if result.returncode:
        return None
    return [name for name in result.stdout.decode("utf-8").split("\0") if name]


def classify(paths: list[str] | None, non_core: tuple[str, ...]) -> dict[str, bool]:
    """`core`: build and test are needed; `workflows`: GitHub Actions files must be linted."""
    if paths is None:
        return {"core": True, "workflows": True}
    return {"core": any(is_core(path, non_core) for path in paths),
            "workflows": any(path.startswith(".github/") for path in paths)}


def write_outputs(values: dict[str, bool]) -> None:
    """Expose results as GitHub Actions step outputs; no-op outside Actions."""
    target = os.environ.get("GITHUB_OUTPUT")
    if target:
        with open(target, "a", encoding="utf-8") as stream:
            stream.writelines(f"{key}={str(value).lower()}\n" for key, value in values.items())


def main(root: Path, non_core: tuple[str, ...], base: str | None, head: str | None, merge_base: bool) -> dict:
    paths = changed_files(root, base, head, merge_base)
    result = classify(paths, non_core)
    if paths is None:
        print("Changed files unknown (manual run, new branch or missing history): treating as a core change.")
    else:
        for path in paths:
            print(f'{"core    " if is_core(path, non_core) else "non-core"}  {path}')
        print(f"{len(paths)} changed file(s).")
    print(f'Core files changed: {result["core"]}; workflow files changed: {result["workflows"]}.')
    write_outputs(result)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        count = "unknown" if paths is None else str(len(paths))
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(f"### Changes\n\nChanged files: {count} · core: {result['core']} · "
                         f"workflows: {result['workflows']}\n\n")
    return result
