from __future__ import annotations

import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MCP_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MCP_DIR))

from lookin_client import LookinClient, LookinClientError  # noqa: E402


class _Response:
    def __init__(self, payload: dict, status: int = 200) -> None:
        self.payload = payload
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


class LookinClientTests(unittest.TestCase):
    def test_export_all_images_sends_exact_json_body(self) -> None:
        with patch(
            "lookin_client.urlopen",
            return_value=_Response({"status": "success", "exported_count": 0}),
        ) as mocked:
            LookinClient().export_all_images("/tmp/lookin-images")

        request = mocked.call_args.args[0]
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(request.data, b'{"directory":"/tmp/lookin-images"}')

    def test_hierarchy_encodes_filters(self) -> None:
        with patch("lookin_client.urlopen", return_value=_Response({"status": "success"})) as mocked:
            client = LookinClient("http://127.0.0.1:10086")
            client.hierarchy(max_depth=3, filter_class="UI Label", element_id="42")

        request = mocked.call_args.args[0]
        self.assertEqual(request.method, "GET")
        self.assertIn("max_depth=3", request.full_url)
        self.assertIn("filter_class=UI+Label", request.full_url)
        self.assertIn("element_id=42", request.full_url)

    def test_server_error_becomes_actionable_exception(self) -> None:
        with patch(
            "lookin_client.urlopen",
            return_value=_Response({"status": "error", "message": "No hierarchy"}),
        ):
            with self.assertRaisesRegex(LookinClientError, "No hierarchy"):
                LookinClient().context()

    def test_capture_writes_consistent_bundle(self) -> None:
        png = b"\x89PNG\r\n\x1a\n"
        responses = [
            _Response({"status": "success", "message": "reloaded"}),
            _Response(
                {
                    "status": "success",
                    "summary": {"root_element_ids": ["123"]},
                    "hierarchy": [{"oid": "123", "className": "UIWindow"}],
                }
            ),
            _Response({"status": "success", "element_id": "123"}),
            _Response(
                {"status": "success", "data": base64.b64encode(png).decode()}
            ),
        ]
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("lookin_client.urlopen", side_effect=responses):
                manifest = LookinClient().capture(temp_dir)

            output = Path(temp_dir)
            self.assertEqual((output / "screenshot.png").read_bytes(), png)
            self.assertEqual(
                json.loads((output / "context.json").read_text())["status"],
                "success",
            )
            self.assertEqual(manifest["target_element_id"], "123")
            self.assertTrue((output / "element.json").exists())
            self.assertTrue((output / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
