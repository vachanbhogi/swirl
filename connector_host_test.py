"""Focused tests for the bounded experimental filesystem writer."""

from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import connector_host


class VaultArtifactWriterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.vault = Path(self.temporary_directory.name)
        self.target = self.vault / "Tomorrow Brief.md"
        self.vault_patch = mock.patch.object(
            connector_host, "_demo_vault_root", return_value=self.vault
        )
        self.vault_patch.start()

    def tearDown(self) -> None:
        self.vault_patch.stop()
        self.temporary_directory.cleanup()

    def test_create_update_and_no_change_are_distinct(self) -> None:
        created = connector_host.save_vault_artifact(
            "Tomorrow Brief.md", "first\n", "absent"
        )
        self.assertTrue(created["success"])
        self.assertTrue(created["created"])
        self.assertEqual(created["write_state"], "create")
        first_hash = hashlib.sha256(b"first\n").hexdigest()
        self.assertEqual(created["content_hash"], first_hash)

        unchanged = connector_host.save_vault_artifact(
            "Tomorrow Brief.md", "first\n", first_hash
        )
        self.assertTrue(unchanged["success"])
        self.assertFalse(unchanged["created"])
        self.assertEqual(unchanged["write_state"], "no_change")

        updated = connector_host.save_vault_artifact(
            "Tomorrow Brief.md", "second\n", first_hash
        )
        self.assertTrue(updated["success"])
        self.assertFalse(updated["created"])
        self.assertEqual(updated["write_state"], "update")
        self.assertEqual(self.target.read_bytes(), b"second\n")

    def test_expected_prior_hash_mismatch_performs_zero_writes(self) -> None:
        created = connector_host.save_vault_artifact(
            "Tomorrow Brief.md", "approved\n", "absent"
        )
        self.assertTrue(created["success"])
        before = self.target.read_bytes()

        rejected = connector_host.save_vault_artifact(
            "Tomorrow Brief.md", "unapproved\n", "wrong-prior-hash"
        )
        self.assertFalse(rejected["success"])
        self.assertEqual(rejected["error_code"], "target_changed")
        self.assertEqual(self.target.read_bytes(), before)

    def test_final_target_symlink_is_rejected_without_following_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            outside = Path(temporary_directory) / "outside.md"
            outside.write_bytes(b"outside\n")
            self.target.symlink_to(outside)

            inspected = connector_host.inspect_vault_artifact()
            self.assertFalse(inspected["success"])
            self.assertEqual(inspected["error_code"], "unsafe_target")

            rejected = connector_host.save_vault_artifact(
                "Tomorrow Brief.md", "replacement\n", "absent"
            )
            self.assertFalse(rejected["success"])
            self.assertEqual(rejected["error_code"], "unsafe_target")
            self.assertEqual(outside.read_bytes(), b"outside\n")


if __name__ == "__main__":
    unittest.main()
