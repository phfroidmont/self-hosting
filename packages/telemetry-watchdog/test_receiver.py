import http.client
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("receiver", Path(__file__).with_name("receiver.py"))
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)
TOKEN = "a" * 64  # Synthetic, never a real SOPS credential.


class ReceiverTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.server = receiver.http.server.ThreadingHTTPServer(("127.0.0.1", 0), receiver.handler_for(TOKEN, self.temp.name))
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def send(self, payload, *, path="/watchdog", token=TOKEN, method="POST", headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=8)
        body = json.dumps(payload).encode() if not isinstance(payload, bytes) else payload
        conn.request(method, path, body=body, headers={"Authorization": "Bearer " + token, **(headers or {})})
        response = conn.getresponse()
        status = response.status
        self.assertEqual(response.read(), b"")
        conn.close()
        return status

    def alert(self, *, stamp=None, status="firing", labels=None):
        return {"alerts": [{"status": status, "labels": labels or {"alertname": "TelemetryWatchdog", "watchdog": "central"},
                            "annotations": {"watchdog_evaluated_at": str(time.time() if stamp is None else stamp)}}]}

    def test_auth_route_body_and_time(self):
        path = Path(self.temp.name) / "heartbeat.json"
        valid = self.alert()
        self.assertEqual(self.send(valid, token="b" * 64), 401)
        self.assertEqual(self.send(valid, headers={"Authorization": "Bearer é"}), 401)
        self.assertEqual(self.send(valid, path="/watchdog?x=1"), 404)
        self.assertEqual(self.send(valid, path="/watchdog/"), 404)
        self.assertEqual(self.send(valid, method="GET"), 405)
        self.assertEqual(self.send(b"x" * 32769), 413)
        self.assertEqual(self.send(b"{}", headers={"Content-Length": "9"}), 400)
        self.assertEqual(self.send(b"{}", headers={"Content-Length": "9" * 5000}), 413)
        self.assertEqual(self.send(b"broken"), 400)
        self.assertEqual(self.send(b"[" * 1200 + b"0"), 400)
        with mock.patch.object(receiver.json, "loads", side_effect=RecursionError("deep JSON")):
            self.assertEqual(self.send(b"{}"), 400)
        self.assertFalse(path.exists())
        self.assertEqual(self.send(valid), 204)
        first = json.loads(path.read_text())["received_at"]
        self.assertLess(abs(first - time.time()), 3)
        for invalid in [
            {"alerts": {}}, {"alerts": []},
            self.alert(status="resolved"), self.alert(status="NoData"),
            self.alert(labels={"alertname": "TelemetryWatchdog", "watchdog": "other"}),
            self.alert(labels={"alertname": "Unrelated", "watchdog": "central"}),
            self.alert(labels={"alertname": "TelemetryWatchdog", "watchdog": "central", "grafana_state": "Error"}),
            self.alert(labels={"alertname": "TelemetryWatchdog", "watchdog": "central", "grafana_state": "NoData"}),
            self.alert(stamp=time.time() - 181), self.alert(stamp=time.time() + 31),
            self.alert(stamp="nan"),
        ]:
            self.assertEqual(self.send(invalid), 422)
            self.assertEqual(json.loads(path.read_text())["received_at"], first)
        self.assertEqual(self.send(self.alert(stamp=time.time() + 20)), 204)
        self.assertFalse(list(Path(self.temp.name).glob(".heartbeat-*")))

    def test_replace_failure_returns_503_without_refresh(self):
        path = Path(self.temp.name) / "heartbeat.json"
        receiver.write_heartbeat(self.temp.name, time.time() - 700)
        first = path.stat().st_mtime_ns
        contents = path.read_bytes()
        with mock.patch.object(receiver.os, "replace", side_effect=OSError("synthetic disk failure")):
            self.assertEqual(self.send(self.alert()), 503)
        self.assertEqual(path.read_bytes(), contents)
        self.assertEqual(path.stat().st_mtime_ns, first)
        self.assertFalse(list(Path(self.temp.name).glob(".heartbeat-*")))

    def test_restart_does_not_refresh_and_missing_state(self):
        state = Path(self.temp.name) / "heartbeat.json"
        self.assertFalse(state.exists())
        old = time.time() - 700
        receiver.write_heartbeat(self.temp.name, old)
        self.assertEqual(json.loads(state.read_text())["received_at"], old)
        other = receiver.handler_for(TOKEN, self.temp.name)
        self.assertIsNotNone(other)
        self.assertEqual(json.loads(state.read_text())["received_at"], old)


if __name__ == "__main__":
    unittest.main()
