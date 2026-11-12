"""tools/evaluation/compare_metrics.py が，前の版と比べて下がった指標を正しく書くこと"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from compare_metrics import MARKER, report  # noqa: E402


def result(passed, total, top10=90.0, mincer=2.0, zenzai=True):
    return {"zenzai": zenzai, "passed": passed, "total": total, "accuracy": passed / total * 100,
            "top10": top10, "mincer": mincer, "median_seconds": 0.03}


def metrics(label, ajimee, everyday=None, startup=None):
    sets = {"ajimee": {"small": ajimee, "xsmall": result(146, 200)}}
    if everyday:
        sets["conversion-everyday"] = {"small": everyday, "xsmall": everyday}
    return {"label": label, "sets": sets, "startup": startup}


class ReportTests(unittest.TestCase):
    def test_starts_with_marker_to_find_previous_comment(self):
        self.assertTrue(report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(172, 200))).startswith(MARKER))

    def test_no_regression_when_metrics_are_the_same(self):
        text = report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(172, 200)))
        self.assertIn("下がった指標はありません．上がった指標: 0 件", text)
        self.assertIn("172/200(86.0%) | 172/200(86.0%) | ±0", text)

    def test_reports_lower_accuracy_and_higher_mincer_as_regressions(self):
        text = report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(170, 200, mincer=2.5)))
        self.assertIn("**下がった指標: 1 件**(AJIMEE-Bench(small))", text)
        self.assertIn("-1.0%", text)
        self.assertIn("下がった |", text)

    def test_reports_improvements(self):
        text = report(metrics("v0.2.7", result(172, 200, top10=87.0)), metrics("v0.2.8", result(172, 200, top10=88.0)))
        self.assertIn("上がった指標: 1 件", text)
        self.assertIn("87.0% → 88.0%(+1.0%)", text)

    def test_sets_added_in_this_version_have_no_difference(self):
        text = report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(172, 200), everyday=result(129, 142)))
        self.assertIn("| ふだんの文(conversion-everyday) | small | — | 129/142(90.8%) | — |", text)

    def test_startup_of_old_version_without_probe_is_blank(self):
        startup = {"verification_seconds": 0.8, "engine_seconds": 0.02, "warm_up_seconds": 0.2, "first_conversion_seconds": 0.03}
        text = report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(172, 200), startup=startup))
        self.assertIn("| 辞書とモデルの確認 | — | 0.80 秒 |", text)

    def test_warns_when_zenzai_was_not_loaded(self):
        text = report(metrics("v0.2.7", result(172, 200)), metrics("v0.2.8", result(90, 200, zenzai=False)))
        self.assertIn("Zenzai を読み込めなかった版がある", text)


if __name__ == "__main__":
    unittest.main()
