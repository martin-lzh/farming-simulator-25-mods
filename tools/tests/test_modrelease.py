"""Tests for the shared release module (identical in every Mod repository)."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import modrelease as mr  # noqa: E402

COMMIT = "a" * 40


def mod(tmp, version="1.1.0", prerelease=False, notes="### 1.1.0 — 2026-10-18\n\n- Change.", unreleased=False, assets=None):
    if assets is None:
        path = Path(tmp) / f"Mod-{version}.zip"
        path.write_bytes(b"zip:" + version.encode())
        assets = (path,)
    return mr.ModRelease("demo", "Demo Mod", version, prerelease, notes, unreleased, assets,
                         "Game 1.0 · Loader 5", "https://example.invalid/README.md")


def release(tag, prerelease=False, draft=False, id=1, commit=COMMIT, body=""):
    return {"tag_name": tag, "prerelease": prerelease, "draft": draft, "id": id,
            "target_commitish": commit, "body": body, "upload_url": f"https://uploads.github.com/x/{id}/assets{{?name}}"}


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def decide(self, m, releases=(), tags=()):
        return mr.plan([m], list(releases), set(tags))[0]

    def test_new_numbered_version_publishes(self):
        self.assertEqual(self.decide(mod(self.tmp.name), [release("demo-v1.0.0")], {"demo-v1.0.0"}).action, "publish")

    def test_first_release_publishes(self):
        self.assertEqual(self.decide(mod(self.tmp.name)).action, "publish")

    def test_four_part_versions(self):
        m = mod(self.tmp.name, "0.1.3.0", notes="## 0.1.3.0 — 2026-10-18\n- x")
        self.assertEqual(self.decide(m, [release("demo-v0.1.2.0")]).action, "publish")

    def test_development_version_is_skipped(self):
        self.assertEqual(self.decide(mod(self.tmp.name, "1.1.0-dev")).action, "skip")

    def test_published_version_is_current_or_waiting(self):
        self.assertEqual(self.decide(mod(self.tmp.name), [release("demo-v1.1.0")]).action, "current")
        waiting = self.decide(mod(self.tmp.name, unreleased=True), [release("demo-v1.1.0")])
        self.assertEqual(waiting.action, "waiting")

    def test_beta_is_promoted_when_release_json_says_stable(self):
        d = self.decide(mod(self.tmp.name), [release("demo-v1.1.0", prerelease=True)])
        self.assertEqual(d.action, "promote")

    def test_stable_release_is_never_demoted(self):
        d = self.decide(mod(self.tmp.name, prerelease=True), [release("demo-v1.1.0")])
        self.assertEqual(d.action, "error")

    def test_errors(self):
        cases = {
            "older": (mod(self.tmp.name, "1.0.0"), [release("demo-v1.0.5")], set()),
            "orphan tag": (mod(self.tmp.name), [], {"demo-v1.1.0"}),
            "no notes": (mod(self.tmp.name, notes=None), [], set()),
            "status heading": (mod(self.tmp.name, notes="### 1.1.0 — 2026-10-18 (pending publication)\n- x"), [], set()),
            "unreleased": (mod(self.tmp.name, unreleased=True), [], set()),
            "no assets": (mod(self.tmp.name, assets=()), [], set()),
        }
        for name, (m, releases, tags) in cases.items():
            with self.subTest(name):
                self.assertEqual(self.decide(m, releases, tags).action, "error")

    def test_body_names_zip_and_marks_beta(self):
        body = mr.release_body(mod(self.tmp.name, prerelease=True))
        self.assertIn("**Mod-1.1.0.zip**", body)
        self.assertIn("Beta", body)
        self.assertNotIn("not implied", body)
        self.assertEqual(mr.release_title(mod(self.tmp.name)), "Demo Mod 1.1.0")

    def test_checksums_cover_every_asset(self):
        files = mr.release_files(mod(self.tmp.name))
        self.assertEqual(set(files), {"Mod-1.1.0.zip", "SHA256SUMS.txt"})
        self.assertIn(b"Mod-1.1.0.zip", files["SHA256SUMS.txt"])


class FakeGitHub:
    def __init__(self, releases=(), tags=None, corrupt=False):
        self.releases = {r["id"]: dict(r) for r in releases}
        self.tags = dict(tags or {})
        self.assets = {}
        self.writes = []
        self.corrupt = corrupt

    def pages(self, path):
        if path == "/releases":
            return list(self.releases.values())
        release_id = int(path.split("/")[2])
        return [a for a in self.assets.values() if a["release"] == release_id]

    def tag_commit(self, tag):
        return self.tags.get(tag)

    def request(self, path, method="GET", payload=None, raw=False, missing_ok=False):
        if path == "/git/matching-refs/tags":
            return [{"ref": f"refs/tags/{t}"} for t in self.tags]
        if method != "GET":
            self.writes.append((method, path))
        if method == "POST" and path == "/releases":
            rid = len(self.releases) + 10
            self.releases[rid] = release(payload["tag_name"], payload["prerelease"], True, rid, payload["target_commitish"], payload["body"])
            return self.releases[rid]
        if method == "POST" and path.startswith("https://uploads"):
            aid = len(self.assets) + 100
            self.assets[aid] = {"id": aid, "name": path.split("name=")[1], "release": int(path.split("/")[4]),
                                "data": payload + (b"!" if self.corrupt else b"")}
            return self.assets[aid]
        if path.startswith("/releases/assets/"):
            return self.assets[int(path.rsplit("/", 1)[1])]["data"]
        if path.startswith("/releases/"):
            rid = int(path.rsplit("/", 1)[1])
            if method == "PATCH":
                self.releases[rid].update(payload)
                if payload.get("draft") is False:
                    self.tags[self.releases[rid]["tag_name"]] = self.releases[rid]["target_commitish"]
            return self.releases[rid]
        raise AssertionError(path)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_publish_uploads_verifies_and_tags(self):
        api = FakeGitHub([release("demo-v1.0.0", id=1)], {"demo-v1.0.0": "b" * 40})
        mr.publish(api, [mod(self.tmp.name)], COMMIT)
        new = [r for r in api.releases.values() if r["tag_name"] == "demo-v1.1.0"][0]
        self.assertFalse(new["draft"])
        self.assertEqual(api.tags["demo-v1.1.0"], COMMIT)
        self.assertEqual({a["name"] for a in api.assets.values()}, {"Mod-1.1.0.zip", "SHA256SUMS.txt"})

    def test_promote_only_patches_release(self):
        api = FakeGitHub([release("demo-v1.1.0", prerelease=True, id=1)], {"demo-v1.1.0": COMMIT})
        mr.publish(api, [mod(self.tmp.name)], COMMIT)
        self.assertEqual(api.writes, [("PATCH", "/releases/1")])
        self.assertFalse(api.releases[1]["prerelease"])

    def test_current_release_is_never_written(self):
        api = FakeGitHub([release("demo-v1.1.0", id=1)], {"demo-v1.1.0": COMMIT})
        mr.publish(api, [mod(self.tmp.name)], COMMIT)
        self.assertEqual(api.writes, [])

    def test_corrupt_upload_keeps_draft_and_fails(self):
        api = FakeGitHub(corrupt=True)
        with self.assertRaises(SystemExit):
            mr.publish(api, [mod(self.tmp.name)], COMMIT)
        self.assertTrue(all(r["draft"] for r in api.releases.values()))

    def test_one_bad_mod_does_not_block_others(self):
        good = mod(self.tmp.name)
        bad = mr.ModRelease("other", "Other", "1.0.0", False, None, False, good.assets, "", "")
        api = FakeGitHub()
        with self.assertRaises(SystemExit):
            mr.publish(api, [bad, good], COMMIT)
        self.assertIn("demo-v1.1.0", api.tags)

    def test_draft_from_other_commit_is_not_reused(self):
        m = mod(self.tmp.name)
        api = FakeGitHub([release("demo-v1.1.0", draft=True, id=1, commit="c" * 40, body=mr.release_body(m))])
        with self.assertRaises(SystemExit):
            mr.publish(api, [m], COMMIT)
        self.assertEqual(api.writes, [])


class GitHubTransportTests(unittest.TestCase):
    def test_cross_host_asset_redirect_strips_token(self):
        request = urllib.request.Request("https://api.github.com/repos/example/mods/releases/assets/1",
                                         headers={"Authorization": "Bearer fixture-token"})
        redirected = mr._AssetRedirect().redirect_request(
            request, None, 302, "Found", {}, "https://release-assets.githubusercontent.com/asset")
        self.assertIsNone(redirected.get_header("Authorization"))

    def test_asset_redirect_cannot_downgrade_to_http(self):
        request = urllib.request.Request("https://api.github.com/asset")
        with self.assertRaisesRegex(ValueError, "non-HTTPS"):
            mr._AssetRedirect().redirect_request(request, None, 302, "Found", {}, "http://example.invalid/asset")

    def test_pagination_reads_every_page(self):
        api = mr.GitHub("example/mods", token="fixture-token")
        with patch.object(api, "request", side_effect=[[{}] * 100, [{"id": 101}]]) as request:
            self.assertEqual(len(api.pages("/releases")), 101)
        self.assertEqual(request.call_args_list[1].args[0], "/releases?per_page=100&page=2")

    def test_other_repository_endpoints_are_refused(self):
        api = mr.GitHub("example/mods", token="fixture-token")
        with self.assertRaises(ValueError):
            api.request("https://api.github.com/repos/other/repo/releases")


if __name__ == "__main__":
    unittest.main()
