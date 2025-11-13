import socket
import unittest
from unittest.mock import MagicMock, patch

from python.network_check import test_connectivity


class NetworkCheckTests(unittest.TestCase):
    @patch("python.network_check.time.time", side_effect=[100.0, 100.1])
    @patch("python.network_check.socket.socket")
    @patch("python.network_check.socket.gethostbyname", return_value="20.26.156.215")
    def test_successful_connectivity(self, mock_dns, mock_socket_ctor, mock_time):
        mock_socket = MagicMock()
        mock_socket_ctor.return_value = mock_socket

        result = test_connectivity()

        self.assertTrue(result["success"])
        self.assertEqual(result["message"], "Network connectivity OK")
        self.assertIsNotNone(result["latency_ms"])
        mock_socket.connect.assert_called_once()
        mock_socket.close.assert_called_once()

    @patch("python.network_check.socket.gethostbyname", side_effect=socket.gaierror("failure"))
    def test_dns_failure_reports_error(self, mock_dns):
        result = test_connectivity()
        self.assertFalse(result["success"])
        self.assertIn("DNS resolution failed", result["message"])
        self.assertIsNone(result["latency_ms"])

    @patch("python.network_check.socket.socket")
    @patch("python.network_check.socket.gethostbyname", return_value="20.26.156.215")
    def test_socket_error_returns_failure(self, mock_dns, mock_socket_ctor):
        mock_socket = MagicMock()
        mock_socket.connect.side_effect = socket.error("boom")
        mock_socket_ctor.return_value = mock_socket

        result = test_connectivity()

        self.assertFalse(result["success"])
        self.assertIn("Connection failed", result["message"])
        self.assertIsNone(result["latency_ms"])
        mock_socket.close.assert_not_called()


if __name__ == "__main__":
    unittest.main()
