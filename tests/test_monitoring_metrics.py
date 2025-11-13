import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from python.monitoring_metrics import MetricsCollector


class MetricsCollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.collector = MetricsCollector(self.temp_dir.name)
        self.metrics_file = Path(self.temp_dir.name) / "code2" / "logs" / "metrics.json"

    def test_initialization_creates_metrics_file(self):
        self.assertTrue(self.metrics_file.exists())
        with open(self.metrics_file, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        self.assertIn("operations", data)
        self.assertIn("summary", data)

    def test_record_operation_updates_summary_counts(self):
        self.collector.record_operation("message_processed", 12.0, True)
        with open(self.metrics_file, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        self.assertEqual(data["summary"]["messages_processed"], 1)
        self.assertEqual(len(data["operations"]), 1)

    def test_operations_trim_to_last_thousand_entries(self):
        for index in range(1100):
            self.collector.record_operation("message_received", 5.0, True)
        with open(self.metrics_file, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        self.assertEqual(len(data["operations"]), 1000)

    def test_get_summary_filters_by_time_and_computes_average(self):
        now = 1_700_000_000.0
        recent_duration = 45.0
        older_duration = 120.0

        with patch("python.monitoring_metrics.time.time", return_value=now - 25 * 3600):
            self.collector.record_operation("auto_response", older_duration, True)
        with patch("python.monitoring_metrics.time.time", return_value=now):
            self.collector.record_operation("auto_response", recent_duration, True)

        with patch("python.monitoring_metrics.time.time", return_value=now):
            summary = self.collector.get_summary(hours=24)

        self.assertEqual(summary["total_operations"], 1)
        self.assertAlmostEqual(summary["avg_response_time_ms"], recent_duration, places=2)
        self.assertGreaterEqual(summary["summary"].get("auto_responses", 0), 2)


if __name__ == "__main__":
    unittest.main()
