from pathlib import Path
from contextlib import redirect_stdout, redirect_stderr
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import game_build_monitor as monitor


def config():
    return monitor.load_baseline(monitor.BASELINE)


def snapshot(build="25879112"):
    return dict(buildid=build, timeupdated="1792400000")


def app_info(public='"buildid" "25879111" "timeupdated" "1792497682"'):
    return '''Steam Console Client
Connecting anonymously to Steam Public...OK
"2300320"
{
    "common" { "name" "Farming Simulator 25" }
    "config" { "description" "A \\"quoted\\" title with { braces }" }
    "depots" {
        "2300321" { "manifests" { "public" { "gid" "999" } } }
        "branches" {
            "downgrade1.24.0.0" { "buildid" "99999999" "description" "Outdated Version\t" "timeupdated" "1785854662" }
            "public" { ''' + public + ''' }
        }
    }
}
Unloading Steam API...OK
'''


class History:
    def __init__(self, issues=None):
        self.issues = issues or []
        self.posts = []
        self.paths = []

    def request(self, path, method="GET", payload=None):
        self.paths.append(path)
        if method == "POST":
            issue = dict(payload, user=dict(login=monitor.BOT), html_url="https://github.com/example/issues/1")
            self.posts.append(issue)
            self.issues.insert(0, issue)
            return issue
        page = int(path.rsplit("page=", 1)[1])
        return self.issues[(page - 1) * 100:page * 100]


def event(current, **extra):
    return dict(monitor.issue_payload(config()["initialBuild"], current, config()),
                user=dict(login=monitor.BOT), **extra)


class AppInfoTests(unittest.TestCase):
    def test_exact_public_branch_not_first_build_or_manifest(self):
        self.assertEqual(monitor.extract_snapshot(app_info(), config()), config()["initialBuild"])

    def test_quoted_strings_comments_and_braces(self):
        text = app_info().replace('"depots"', '// comment\n "depots"')
        parsed = monitor.parse_app_info(text, "2300320")
        self.assertEqual(parsed["config"]["description"], 'A "quoted" title with { braces }')

    def test_missing_or_wrong_app_fails(self):
        for text in ("ERROR! No app info", app_info().replace('"2300320"', '"999"'),
                     app_info().replace("Farming Simulator 25", "Another Game")):
            with self.subTest(text=text[:50]), self.assertRaises(ValueError):
                monitor.extract_snapshot(text, config())

    def test_missing_public_branch_fails(self):
        with self.assertRaises(ValueError):
            monitor.extract_snapshot(app_info().replace('"public"', '"beta"'), config())

    def test_malformed_truncated_duplicate_or_invalid_values_fail(self):
        bad = [app_info()[:app_info().index('"depots"')],
               app_info().replace('"common"', 'bare-token'),
               app_info('"buildid" "1" "buildid" "2" "timeupdated" "1792497682"'),
               app_info('"buildid" "0" "timeupdated" "1792497682"'),
               app_info('"buildid" "latest" "timeupdated" "1792497682"'),
               app_info('"buildid" "1"'),
               app_info('"buildid" "1" "timeupdated" "99999999999999999999"')]
        for text in bad:
            with self.subTest(text=text[-100:]), self.assertRaises((ValueError, OverflowError, OSError)):
                monitor.extract_snapshot(text, config())

    @patch.object(monitor.time, "sleep")
    @patch.object(monitor.subprocess, "run")
    def test_query_retries_a_failed_connection_and_uses_anonymous_metadata_only(self, run, sleep):
        run.side_effect = [subprocess.TimeoutExpired("steamcmd", 180),
                           subprocess.CompletedProcess([], 0, app_info().encode())]
        result = monitor.query_steam(Path(__file__), config())
        self.assertEqual(result, config()["initialBuild"])
        self.assertEqual(run.call_args.args[0][1:],
                         ["+login", "anonymous", "+app_info_update", "1", "+app_info_print", "2300320", "+quit"])
        self.assertEqual(run.call_count, 2)

    @patch.object(monitor.time, "sleep")
    @patch.object(monitor.subprocess, "run")
    def test_query_fails_after_bounded_retries(self, run, sleep):
        run.return_value = subprocess.CompletedProcess([], 0, b"No app info")
        with self.assertRaises(RuntimeError):
            monitor.query_steam(Path(__file__), config())
        self.assertEqual(run.call_count, 2)

    @patch.object(monitor.time, "sleep")
    @patch.object(monitor.subprocess, "run")
    def test_cached_metadata_after_failed_login_is_not_accepted(self, run, sleep):
        cached = app_info().replace("Connecting anonymously to Steam Public...OK", "Login FAILED")
        run.return_value = subprocess.CompletedProcess([], 0, cached.encode())
        with self.assertRaises(RuntimeError):
            monitor.query_steam(Path(__file__), config())


class NotificationTests(unittest.TestCase):
    def test_initial_baseline_produces_no_issue(self):
        history = History()
        report = monitor.check_build(config()["initialBuild"], config(), history, True)
        self.assertFalse(report["changed"])
        self.assertEqual(history.posts, [])

    def test_change_creates_once_and_closed_issue_remains_state(self):
        history = History()
        current = snapshot()
        self.assertTrue(monitor.check_build(current, config(), history, True)["notified"])
        history.issues[0]["state"] = "closed"
        self.assertFalse(monitor.check_build(current, config(), history, True)["changed"])
        self.assertEqual(len(history.posts), 1)
        self.assertIn("state=all", history.paths[-1])

    def test_rollback_and_later_return_to_seen_build_both_notify(self):
        history = History()
        for current in (snapshot(), config()["initialBuild"], snapshot()):
            self.assertTrue(monitor.check_build(current, config(), history, True)["notified"])
        self.assertEqual(len(history.posts), 3)

    def test_timestamp_only_change_does_not_notify(self):
        history = History()
        current = snapshot(config()["initialBuild"]["buildid"])
        self.assertFalse(monitor.check_build(current, config(), history, True)["changed"])
        self.assertEqual(history.posts, [])

    def test_read_only_check_never_writes_or_advances_state(self):
        history = History()
        report = monitor.check_build(snapshot(), config(), history)
        self.assertTrue(report["changed"])
        self.assertFalse(report["notified"])
        self.assertEqual(history.posts, [])
        self.assertEqual(monitor.previous_build(history, config()), config()["initialBuild"])

    def test_history_ignores_other_authors_and_pull_requests(self):
        user_issue = event(snapshot())
        user_issue["user"]["login"] = "someone-else"
        history = History([user_issue, event(snapshot(), pull_request={})])
        self.assertEqual(monitor.previous_build(history, config()), config()["initialBuild"])

    def test_newest_issue_wins_even_if_an_older_one_is_edited(self):
        history = History([event(snapshot("25879113")), event(snapshot())])
        self.assertEqual(monitor.previous_build(history, config())["buildid"], "25879113")
        self.assertIn("sort=created&direction=desc", history.paths[0])

    def test_history_reads_past_first_page_and_ignores_other_branch(self):
        foreign = event(snapshot())
        foreign["body"] = foreign["body"].replace('"branch":"public"', '"branch":"downgrade1.24.0.0"')
        history = History([foreign] + [{} for _ in range(99)] + [event(snapshot())])
        self.assertEqual(monitor.previous_build(history, config()), snapshot())
        self.assertEqual(len(history.paths), 2)

    def test_broken_history_fails_without_creating_an_issue(self):
        for body in (monitor.MARKER + "broken", monitor.MARKER + '{} -->',
                     event(snapshot())["body"].replace('"25879112"', '"not-a-build"')):
            history = History([dict(user=dict(login=monitor.BOT), body=body)])
            with self.subTest(body=body[-100:]), self.assertRaises((ValueError, KeyError)):
                monitor.check_build(snapshot(), config(), history, True)
            self.assertEqual(history.posts, [])

    def test_github_failure_does_not_look_like_no_history(self):
        history = Mock()
        history.request.return_value = None
        with self.assertRaises(ValueError):
            monitor.check_build(snapshot(), config(), history, True)
        self.assertEqual(history.request.call_count, 1)

    def test_uncertain_issue_creation_is_recovered_from_history(self):
        history = History()
        original = history.request

        def create_then_timeout(path, method="GET", payload=None):
            result = original(path, method, payload)
            if method == "POST":
                raise TimeoutError("Response lost after creation")
            return result

        with patch.object(history, "request", side_effect=create_then_timeout):
            with self.assertRaises(TimeoutError):
                monitor.check_build(snapshot(), config(), history, True)
        self.assertFalse(monitor.check_build(snapshot(), config(), history, True)["changed"])
        self.assertEqual(len(history.posts), 1)

    def test_invalid_snapshot_or_missing_repository_cannot_notify(self):
        with self.assertRaises(ValueError):
            monitor.check_build(snapshot(), config(), notify=True)
        with self.assertRaises(ValueError):
            monitor.check_build(dict(buildid="1"), config(), History(), True)


class ConfigurationAndCliTests(unittest.TestCase):
    def test_wrong_game_or_repository_baseline_is_rejected(self):
        for key, value in (("appid", "3058360"), ("name", "Parisian Bistro Simulator"),
                           ("repository", "someone/another-repository"), ("branch", "beta")):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "baseline.json"
                settings = dict(config(), **{key: value})
                path.write_text(json.dumps(settings), encoding="utf-8")
                with self.assertRaises(ValueError):
                    monitor.load_baseline(path)

    @patch.object(monitor, "GitHub")
    @patch.object(monitor, "query_steam")
    def test_notify_refuses_non_main_or_foreign_actions_before_network_calls(self, query, github):
        valid = {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main",
                 "GITHUB_REPOSITORY": config()["repository"]}
        argv = ["monitor", "--steamcmd", __file__, "--repository", config()["repository"], "--notify"]
        for env in ({}, dict(valid, GITHUB_REF="refs/heads/dev"),
                    dict(valid, GITHUB_REPOSITORY="someone/fork"),
                    dict(valid, GITHUB_REF="refs/pull/7/merge")):
            with self.subTest(env=env), patch.dict(os.environ, env, clear=True), \
                    patch.object(sys, "argv", argv), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    monitor.main()
                self.assertEqual(error.exception.code, 2)
        query.assert_not_called()
        github.assert_not_called()

    @patch.object(monitor, "GitHub")
    @patch.object(monitor, "query_steam")
    def test_main_cli_notifies_and_read_only_cli_does_not(self, query, github):
        query.return_value = snapshot()
        env = {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main",
               "GITHUB_REPOSITORY": config()["repository"]}
        argv = ["monitor", "--steamcmd", __file__, "--repository", config()["repository"]]
        for notify in (False, True):
            history = History()
            github.return_value = history
            output = io.StringIO()
            with self.subTest(notify=notify), patch.dict(os.environ, env, clear=True), \
                    patch.object(sys, "argv", argv + (["--notify"] if notify else [])), redirect_stdout(output):
                self.assertEqual(monitor.main(), 0)
            self.assertEqual(len(history.posts), int(notify))
            self.assertEqual(json.loads(output.getvalue())["notified"], notify)
            if notify:
                self.assertIn("Farming Simulator 25", history.posts[0]["body"])
                self.assertIn("modDesc.xml", history.posts[0]["body"])
                self.assertNotIn("Unreal", history.posts[0]["body"])


if __name__ == "__main__":
    unittest.main()
