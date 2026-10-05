import unittest
import urllib.request
from unittest import mock

from exporter import commit_time, compute_dora, http_json, render

DAY = 86400
NOW = 100 * DAY


def run(finish_days_ago, ok, lead_hours=1, dur_min=10):
    finish = NOW - finish_days_ago * DAY
    return {"finish": finish, "start": finish - dur_min * 60, "commit": finish - lead_hours * 3600, "ok": ok}


class DoraTests(unittest.TestCase):
    def test_frequency_lead_time_and_failure_rate(self):
        runs = [run(10, True, 2), run(5, False), run(4, True, 4), run(1, True, 6)]
        d = compute_dora(runs, NOW, 30)
        self.assertEqual((d["success"], d["failed"]), (3, 1))
        self.assertAlmostEqual(d["change_failure_rate"], 25.0)
        self.assertEqual(d["lead_time_seconds"], 4 * 3600)  # median of 2,4,6 h
        self.assertAlmostEqual(d["frequency_per_day"], 3 / 10)  # history is only 10 days old
        self.assertEqual(d["duration_seconds"], 600)

    def test_mttr_counts_resolved_incidents_only(self):
        runs = [run(9, False), run(8, True), run(3, False)]  # one resolved after 1 day, one still open
        d = compute_dora(runs, NOW, 30)
        self.assertEqual(d["mttr_seconds"], DAY)
        self.assertEqual(d["open_incident"], 1)

    def test_no_runs_in_window(self):
        d = compute_dora([run(60, True)], NOW, 30)
        self.assertEqual((d["success"], d["failed"]), (0, 0))
        self.assertNotIn("change_failure_rate", d)
        self.assertEqual(d["open_incident"], 0)
        self.assertIn("last_success_ts", d)

    def test_render_is_valid_prometheus_text(self):
        text = render({"azure-devops/app": compute_dora([run(1, True)], NOW, 30)}, {"azure-devops": 0}, 123)
        self.assertIn('dora_deployments_window{pipeline="azure-devops/app",result="success"} 1', text)
        self.assertIn("# TYPE dora_lead_time_seconds gauge", text)
        self.assertNotIn("dora_mttr_seconds{", text)  # no incident -> series omitted, not fake zero


class HttpTests(unittest.TestCase):
    def test_html_sign_in_page_gives_a_clear_error(self):
        class Resp:
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def read(self): return b"\n<html>sign in</html>"
        with mock.patch.object(urllib.request, "urlopen", return_value=Resp()):
            with self.assertRaisesRegex(RuntimeError, "token is probably invalid"):
                http_json("https://dev.azure.com/x", {})

    def test_unknown_commit_falls_back_instead_of_failing_the_whole_fetch(self):
        # A pipeline for another repository has a commit GitHub cannot find (HTTP 422); that must not abort the fetch.
        with mock.patch("exporter.http_json", side_effect=RuntimeError("HTTP 422 from api.github.com")):
            self.assertIsNone(commit_time("owner/app", "deadbeef", "", {}))


if __name__ == "__main__":
    unittest.main()
