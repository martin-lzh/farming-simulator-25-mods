"""Check tracked Python, JSON and XML without reading ignored local references."""

import ast
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    count = 0
    for name in names.decode("utf-8").split("\0"):
        path = ROOT / name
        if path.suffix == ".py":
            ast.parse(path.read_text(encoding="utf-8"), filename=name)
        elif path.suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
        elif path.suffix == ".xml":
            ET.parse(path)
        else:
            continue
        count += 1
    print(f"Checked syntax of {count} tracked Python/JSON/XML files.")


if __name__ == "__main__":
    main()
