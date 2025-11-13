import types
import unittest
from collections import namedtuple
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

from python.system_health import get_system_health


class SystemHealthTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)

    def test_reports_healthy_when_all_checks_pass(self):
        fake_usage = namedtuple("usage", "total used free")(
            total=10 * 1024 ** 3,
            used=5 * 1024 ** 3,
            free=5 * 1024 ** 3,
        )

        with patch("python.system_health.shutil.disk_usage", return_value=fake_usage), \
             patch("python.system_health.psutil.virtual_memory", return_value=types.SimpleNamespace(percent=42.0)), \
             patch("python.system_health.subprocess.run", return_value=Mock(returncode=0, stdout="")):
            result = get_system_health(self.temp_dir.name)

        self.assertEqual(result["overall"], "HEALTHY")
        self.assertEqual(result["checks"]["disk_space"]["status"], "OK")
        self.assertEqual(result["checks"]["memory"]["status"], "OK")
        self.assertEqual(result["checks"]["git_repo"]["status"], "OK")
        self.assertEqual(result["checks"]["git_repo"]["uncommitted"], 0)

    def test_marks_disk_space_critical_when_below_threshold(self):
        fake_usage = namedtuple("usage", "total used free")(
            total=1 * 1024 ** 3,
            used=0.8 * 1024 ** 3,
            free=0.3 * 1024 ** 3,
        )

        with patch("python.system_health.shutil.disk_usage", return_value=fake_usage), \
             patch("python.system_health.psutil.virtual_memory", return_value=types.SimpleNamespace(percent=30.0)), \
             patch("python.system_health.subprocess.run", return_value=Mock(returncode=0, stdout="")):
            result = get_system_health(self.temp_dir.name)

        self.assertEqual(result["overall"], "CRITICAL")
        self.assertEqual(result["checks"]["disk_space"]["status"], "CRITICAL")
        self.assertLess(result["checks"]["disk_space"]["free_gb"], 0.5)

    def test_git_warning_does_not_override_critical(self):
        fake_usage = namedtuple("usage", "total used free")(
            total=10 * 1024 ** 3,
            used=5 * 1024 ** 3,
            free=5 * 1024 ** 3,
        )

        with patch("python.system_health.shutil.disk_usage", return_value=fake_usage), \
             patch("python.system_health.psutil.virtual_memory", return_value=types.SimpleNamespace(percent=97.0)), \
             patch("python.system_health.subprocess.run", return_value=Mock(returncode=1, stdout="")):
            result = get_system_health(self.temp_dir.name)

        self.assertEqual(result["overall"], "WARNING")
        self.assertEqual(result["checks"]["memory"]["status"], "WARNING")
        self.assertEqual(result["checks"]["git_repo"]["status"], "WARNING")


if __name__ == "__main__":
    unittest.main()
