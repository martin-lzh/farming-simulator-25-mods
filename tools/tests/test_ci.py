"""Check how this repository validates its Mods and describes them to tools/modrelease.py."""

import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci  # noqa: E402

LOG = ("# Changelog / 版本记录\n\n## Unreleased\n{pending}\n## 0.1.1.0 — 2026-10-18\n\n- Fix.\n- 修复。\n\n"
       "## 0.1.0.0 — 2026-10-17\n\n- First.\n- 首版。\n")


class ChangelogTests(unittest.TestCase):
    def test_current_entry_and_unreleased(self):
        notes, unreleased = ci.changelog(LOG.format(pending=""), "0.1.1.0")
        self.assertIn("- Fix.", notes)
        self.assertNotIn("First", notes)
        self.assertFalse(unreleased)
        self.assertTrue(ci.changelog(LOG.format(pending="\n- Pending.\n"), "0.1.1.0")[1])

    def test_version_must_match_top_entry(self):
        with self.assertRaises(ValueError):
            ci.changelog(LOG.format(pending=""), "0.1.2.0")

    def test_history_must_descend(self):
        text = "## 0.1.0.0 — a\n\n- x\n\n## 0.1.1.0 — b\n\n- y\n"
        with self.assertRaises(ValueError):
            ci.changelog(text, "0.1.0.0")


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        mod = self.root / "demo-mod"
        mod.mkdir()
        (mod / "modDesc.xml").write_text("<modDesc><version>0.1.1.0</version></modDesc>", encoding="utf-8")
        (mod / "release.json").write_text(json.dumps({"displayName": "Demo", "prerelease": True}), encoding="utf-8")
        (mod / "CHANGELOG.md").write_text(LOG.format(pending=""), encoding="utf-8")
        (mod / "README.md").write_text("Version 0.1.1.0\n", encoding="utf-8")
        for target, name, value in ((ci, "ROOT", self.root), (ci, "MODS", {"demo": "Demo"})):
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)

    def package(self, version="0.1.1.0", source="a" * 40, extra=None):
        directory = self.root / "outputs/ci/demo"
        directory.mkdir(parents=True, exist_ok=True)
        archive = directory / "FS25_Demo.zip"
        with ZipFile(archive, "w") as z:
            z.writestr("modDesc.xml", f"<modDesc><version>{version}</version></modDesc>")
            z.writestr("scripts/Main.lua", "-- code")
            if extra:
                z.writestr(extra, "x")
        evidence = {"source": source, "mod": "demo", "version": "0.1.1.0",
                    "archiveSha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
        (directory / "build-info.json").write_text(json.dumps(evidence), encoding="utf-8")

    def test_release_mod_description(self):
        mod = ci.release_mods("owner/repo")[0]
        self.assertEqual((mod.display_name, mod.version, mod.prerelease), ("Demo", "0.1.1.0", True))
        self.assertEqual([p.name for p in mod.assets], ["FS25_Demo.zip"])
        self.assertIn("- 修复。", mod.notes)

    def test_readme_must_name_version(self):
        (self.root / "demo-mod/README.md").write_text("Version 0.1.10.0\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            ci.config("demo")

    def test_verified_package_passes(self):
        self.package()
        ci.verify_artifacts(ci.config("demo"), "a" * 40)

    def test_bad_packages_fail(self):
        for kwargs in ({"source": "b" * 40}, {"version": "0.1.0.0"}, {"extra": "icon.png"}):
            with self.subTest(**kwargs):
                self.package(**kwargs)
                with self.assertRaises(ValueError):
                    ci.verify_artifacts(ci.config("demo"), "a" * 40)


class ChangeTests(unittest.TestCase):
    """CI skips build and test only for files that never reach a package, validation or tests."""

    def test_examples(self):
        mod = "animal-products-manager-mod"
        core = [f"{mod}/modDesc.xml", f"{mod}/scripts/Main.lua", f"{mod}/gui/ProductDialog.xml",
                f"{mod}/icon_animalProductsManager.dds", f"{mod}/README.md", f"{mod}/CHANGELOG.md",
                f"{mod}/release.json", f"{mod}/LICENSE", f"{mod}/tests/run.py", f"{mod}/tools/build.py",
                f"{mod}/assets/icon.dds", f"{mod}/assets/layout.xml", "tools/ci.py", "tools/README.md",
                "tools/tests/test_ci.py", ".github/workflows/mods.yml", ".github/pull_request_template.md",
                ".gitattributes", ".gitignore", "LICENSE", "new-mod/scripts/Main.lua"]
        non_core = ["README.md", "AGENTS.md", "DEVELOPMENT.md", "docs/README.md", "assets/cover.jpg",
                    "releases/README.md", f"{mod}/DEVELOPMENT.md", f"{mod}/assets/cover.jpg",
                    f"{mod}/assets/icon.png", f"{mod}/assets/screenshots/01-animals.jpg"]
        for path in core:
            with self.subTest(core=path):
                self.assertTrue(ci.changes.is_core(path, ci.NON_CORE))
        for path in non_core:
            with self.subTest(non_core=path):
                self.assertFalse(ci.changes.is_core(path, ci.NON_CORE))

    def test_packageable_tracked_files_are_core(self):
        root = Path(__file__).resolve().parents[2]
        names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode("utf-8").split("\0")
        for name in filter(None, names):
            if PurePosixPath(name).suffix in {".lua", ".xml", ".dds", ".py", ".json", ".toml"}:
                with self.subTest(name=name):
                    self.assertTrue(ci.changes.is_core(name, ci.NON_CORE))


if __name__ == "__main__":
    unittest.main()
