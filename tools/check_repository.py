"""Reject tracked local reference material and binary game data."""

from pathlib import PurePosixPath
import subprocess
import sys


def main() -> int:
    result = subprocess.run(
        ["git", "ls-files", "-z"], check=True, capture_output=True
    )
    local_dirs = {
        "work", "outputs", "reference", "references", "decompiled", "dumps",
        "extracted", "mappings", "binaries", "intermediate", "saved",
    }
    excluded_suffixes = {
        ".dll", ".exe", ".pdb", ".pak", ".utoc", ".ucas", ".uasset", ".uexp",
        ".ubulk", ".umap", ".usmap", ".jmap", ".dmp", ".bin", ".locres",
        ".locmeta", ".zip", ".7z", ".log", ".sav", ".save",
    }
    paths = [p.decode("utf-8") for p in result.stdout.split(b"\0") if p]
    rejected = []
    for name in paths:
        path = PurePosixPath(name.lower())
        if (
            set(path.parts[:-1]) & local_dirs
            or path.suffix in excluded_suffixes
            or name.lower().endswith(".jmap.gz")
            or path.name.startswith(".env")
            or ".local." in path.name
        ):
            rejected.append(name)
    if rejected:
        print("Local-only material is tracked:", file=sys.stderr)
        print("\n".join(rejected), file=sys.stderr)
        return 1
    print(f"Checked {len(paths)} tracked files: no forbidden paths or file types.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
