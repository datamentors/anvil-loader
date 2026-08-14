from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "render_cyclonedds.py"
SPEC = importlib.util.spec_from_file_location("render_cyclonedds", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
render_cyclonedds = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(render_cyclonedds)


class RenderCycloneDdsTest(unittest.TestCase):
    def build(self, **overrides):
        values = {
            "interface": "eno1",
            "robot_ip": "192.0.2.10",
            "gpu_ip": "192.0.2.20",
            "max_auto_participant_index": 31,
            "max_message_size": "1400B",
            "fragment_size": "1344B",
            "whc_high": "8MB",
        }
        values.update(overrides)
        return render_cyclonedds.build_profile(**values)

    def test_profile_is_multicast_free_and_has_exact_peers(self):
        root = self.build().getroot()
        namespace = {"c": "https://cdds.io/config"}
        self.assertEqual(root.findtext(".//c:AllowMulticast", namespaces=namespace), "false")
        self.assertEqual(root.findtext(".//c:ParticipantIndex", namespaces=namespace), "auto")
        self.assertEqual(
            root.findtext(".//c:MaxAutoParticipantIndex", namespaces=namespace),
            "31",
        )
        peers = {
            node.attrib["address"] for node in root.findall(".//c:Peer", namespace)
        }
        self.assertEqual(peers, {"192.0.2.10", "192.0.2.20"})

    def test_profile_write_is_read_only_mount_compatible_and_parseable(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "runtime" / "cyclonedds.xml"
            render_cyclonedds.write_profile(self.build(), output)
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)
            self.assertIn("AllowMulticast", output.read_text(encoding="utf-8"))

    def test_rejects_multicast_or_equal_peer_addresses(self):
        with self.assertRaisesRegex(ValueError, "unicast"):
            self.build(gpu_ip="239.255.0.1")
        with self.assertRaisesRegex(ValueError, "must be different"):
            self.build(gpu_ip="192.0.2.10")

    def test_rejects_too_small_participant_ceiling(self):
        with self.assertRaisesRegex(ValueError, "between 24 and 120"):
            self.build(max_auto_participant_index=9)

    def test_rejects_invalid_interface_and_sizes(self):
        with self.assertRaisesRegex(ValueError, "interface"):
            self.build(interface="eno1; reboot")
        with self.assertRaisesRegex(ValueError, "size syntax"):
            self.build(fragment_size="1344")


if __name__ == "__main__":
    unittest.main()
