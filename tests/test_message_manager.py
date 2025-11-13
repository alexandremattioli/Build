import json
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory

from python.message_manager import MessageManager, MessageType, Priority


class MessageManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.repo_path = Path(self.temp_dir.name)
        (self.repo_path / "coordination").mkdir(parents=True, exist_ok=True)
        self.manager = MessageManager(repo_path=str(self.repo_path))

    def _load_disk_messages(self):
        with open(self.manager.messages_file, "r", encoding="utf-8") as handle:
            return json.load(handle)

    def test_send_message_persists_to_disk(self):
        msg_id = self.manager.send_message(
            from_server="build1",
            to_server="all",
            subject="Status",
            body="Build complete",
            priority=Priority.HIGH,
            msg_type=MessageType.INFO,
        )

        data = self._load_disk_messages()

        self.assertEqual(len(data["messages"]), 1)
        self.assertEqual(data["messages"][0]["id"], msg_id)
        self.assertEqual(data["metadata"]["total_messages"], 1)
        self.assertIn("last_modified", data["metadata"])

    def test_mark_read_updates_message_and_get_unread_filters(self):
        msg_id = self.manager.send_message(
            from_server="build1",
            to_server="code1",
            subject="Deployment",
            body="Deploy now",
        )

        unread = self.manager.get_unread("code1")
        self.assertEqual(len(unread), 1)
        self.assertEqual(unread[0]["id"], msg_id)

        self.manager.mark_read(msg_id, "code1")
        data = self._load_disk_messages()
        stored_msg = data["messages"][0]

        self.assertTrue(stored_msg["read"])
        self.assertIn("read_at", stored_msg)
        self.assertEqual(stored_msg["read_by"], "code1")
        self.assertEqual(self.manager.get_unread("code1"), [])

    def test_search_returns_matching_messages(self):
        self.manager.send_message(
            from_server="build1",
            to_server="all",
            subject="Infrastructure Report",
            body="CPU levels normal",
        )
        self.manager.send_message(
            from_server="build2",
            to_server="build1",
            subject="Alert",
            body="Disk space critical",
            msg_type=MessageType.WARNING,
        )

        results = self.manager.search("disk", server_id="build1")

        self.assertEqual(len(results), 1)
        self.assertIn("critical", results[0]["body"].lower())

    def test_archive_old_messages_moves_items_to_archive(self):
        old_timestamp = (datetime.utcnow() - timedelta(days=40)).strftime("%Y-%m-%dT%H:%M:%SZ")
        data = {
            "schema_version": "1.0",
            "metadata": {"total_messages": 1},
            "messages": [
                {
                    "id": "msg_old",
                    "from": "build1",
                    "to": "build2",
                    "subject": "Old message",
                    "body": "Obsolete",
                    "timestamp": old_timestamp,
                    "priority": Priority.NORMAL.value,
                    "type": MessageType.INFO.value,
                    "read": True,
                }
            ],
        }
        self.manager.save_messages(data)

        archived_count = self.manager.archive_old_messages(days_old=30)

        self.assertEqual(archived_count, 1)
        updated = self.manager.load_messages()
        self.assertEqual(updated["metadata"]["total_messages"], 0)
        self.assertEqual(len(updated["messages"]), 0)

        archive_files = list((self.repo_path / "coordination" / "archive").glob("messages_archive_*.json"))
        self.assertEqual(len(archive_files), 1)
        with open(archive_files[0], "r", encoding="utf-8") as handle:
            archived_content = json.load(handle)
        self.assertEqual(len(archived_content["messages"]), 1)
        self.assertEqual(archived_content["messages"][0]["id"], "msg_old")


if __name__ == "__main__":
    unittest.main()
