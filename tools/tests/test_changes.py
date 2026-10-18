"""Check change classification for CI (tools/changes.py, shared by the three Mod repositories)."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import changes  # noqa: E402

NON_CORE = ("README.md", "docs/**", "*-mod/DEVELOPMENT.md", "*-mod/assets/**/*.png")


class MatchTests(unittest.TestCase):
    def test_patterns(self):
        cases = {
            ("README.md", "README.md"): True,
            ("demo-mod/README.md", "README.md"): False,
            ("docs/a/b.md", "docs/**"): True,
            ("docs", "docs/**"): True,
            ("docsx/a.md", "docs/**"): False,
            ("demo-mod/DEVELOPMENT.md", "*-mod/DEVELOPMENT.md"): True,
            ("demo-mod/sub/DEVELOPMENT.md", "*-mod/DEVELOPMENT.md"): False,
            ("demo-mod/assets/a.png", "*-mod/assets/**/*.png"): True,
            ("demo-mod/assets/shots/a.png", "*-mod/assets/**/*.png"): True,
            ("demo-mod/assets/a.xml", "*-mod/assets/**/*.png"): False,
            ("readme.md", "README.md"): False,
        }
        for (path, pattern), expected in cases.items():
            with self.subTest(path=path, pattern=pattern):
                self.assertEqual(changes.matches(path, pattern), expected)

    def test_classify(self):
        self.assertEqual(changes.classify(["README.md", "docs/x.md"], NON_CORE), {"core": False, "workflows": False})
        self.assertEqual(changes.classify(["README.md", "demo-mod/main.lua"], NON_CORE)["core"], True)
        self.assertEqual(changes.classify([".github/workflows/mods.yml"], NON_CORE), {"core": True, "workflows": True})
        self.assertEqual(changes.classify([], NON_CORE), {"core": False, "workflows": False})
        self.assertEqual(changes.classify(None, NON_CORE), {"core": True, "workflows": True})


class GitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "--quiet")
        self.commits = [self.commit({"README.md": "a\n", "demo-mod/main.lua": "return 1\n"})]

    def git(self, *args):
        return subprocess.run(["git", "-c", "user.name=CI", "-c", "user.email=ci@example.invalid",
                               "-c", "commit.gpgsign=false", *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, files, remove=()):
        for name in remove:
            self.git("rm", "--quiet", name)
        for name, text in files.items():
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text(text, encoding="utf-8")
            self.git("add", name)
        self.git("commit", "--quiet", "-m", "change")
        return self.git("rev-parse", "HEAD")

    def test_range_and_renames(self):
        docs = self.commit({"docs/guide.md": "x\n"})
        self.assertEqual(changes.changed_files(self.root, self.commits[0], docs), ["docs/guide.md"])
        moved = self.commit({"docs/main.lua": "return 1\n"}, remove=["demo-mod/main.lua"])
        self.assertEqual(set(changes.changed_files(self.root, docs, moved)), {"demo-mod/main.lua", "docs/main.lua"})
        self.assertTrue(changes.classify(changes.changed_files(self.root, docs, moved), NON_CORE)["core"])

    def test_merge_base_ignores_base_branch_changes(self):
        base = self.commits[0]
        self.git("checkout", "--quiet", "-b", "feature")
        feature = self.commit({"docs/guide.md": "x\n"})
        self.git("checkout", "--quiet", "-")
        main = self.commit({"demo-mod/main.lua": "return 2\n"})
        self.assertEqual(changes.changed_files(self.root, main, feature, merge_base=True), ["docs/guide.md"])
        self.assertIn("demo-mod/main.lua", changes.changed_files(self.root, main, feature))
        self.assertEqual(changes.changed_files(self.root, base, feature, merge_base=True), ["docs/guide.md"])

    def test_unknown_ranges(self):
        head = self.commits[0]
        for base in (None, "", "0" * 40, "f" * 40, "not-a-sha"):
            with self.subTest(base=base):
                self.assertIsNone(changes.changed_files(self.root, base, head))
        self.assertIsNone(changes.changed_files(self.root, head, None))

    def test_main_writes_outputs(self):
        docs = self.commit({"docs/guide.md": "x\n"})
        output = self.root / "output.txt"
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": ""}):
            changes.main(self.root, NON_CORE, self.commits[0], docs, False)
            changes.main(self.root, NON_CORE, None, None, False)
        self.assertEqual(output.read_text(encoding="utf-8").splitlines(),
                         ["core=false", "workflows=false", "core=true", "workflows=true"])


if __name__ == "__main__":
    unittest.main()
