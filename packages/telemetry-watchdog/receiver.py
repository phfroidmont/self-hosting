"""Private, authenticated Grafana watchdog callback receiver."""

import argparse
import hmac
import http.server
import json
import os
import re
import tempfile
import time

MAX_BODY = 32768
TOKEN_PATTERN = re.compile(r"[0-9a-fA-F]{64}\Z")


def valid_alert(payload, now):
    if not isinstance(payload, dict) or not isinstance(payload.get("alerts"), list):
        return False
    for alert in payload["alerts"]:
        if not isinstance(alert, dict) or alert.get("status") != "firing":
            continue
        labels = alert.get("labels")
        annotations = alert.get("annotations")
        if not isinstance(labels, dict) or not isinstance(annotations, dict):
            continue
        if labels.get("grafana_state") in ("Error", "NoData"):
            continue
        if labels.get("alertname") != "TelemetryWatchdog" or labels.get("watchdog") != "central":
            continue
        stamp = annotations.get("watchdog_evaluated_at")
        if isinstance(stamp, bool):
            continue
        try:
            # Grafana templates emit numeric values as JSON strings in annotations.
            if not isinstance(stamp, (str, int, float)) or (isinstance(stamp, str) and not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", stamp)):
                continue
            evaluated = float(stamp)
        except (ValueError, OverflowError):
            continue
        if 0 <= now - evaluated <= 180 or 0 <= evaluated - now <= 30:
            return True
    return False


def write_heartbeat(directory, now):
    fd, temporary = tempfile.mkstemp(prefix=".heartbeat-", dir=directory)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump({"received_at": now}, output)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, os.path.join(directory, "heartbeat.json"))
        # A later directory fsync error cannot roll back the replace: return
        # 503 and allow the persisted file to be checked at the next cycle.
        dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def handler_for(token, directory):
    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *_args):
            # Neither request targets nor headers nor bodies belong in logs.
            pass

        def respond(self, code):
            self.send_response(code)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True

        def do_POST(self):
            if self.path != "/watchdog":
                return self.respond(404)
            authorization = self.headers.get("Authorization", "")
            # compare_digest rejects non-ASCII str; malformed headers are simply
            # unauthenticated, never an uncaught handler exception.
            if not authorization.isascii() or not hmac.compare_digest(authorization, "Bearer " + token):
                return self.respond(401)
            if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length", [])) != 1:
                return self.respond(400)
            length = self.headers.get("Content-Length")
            if not length or not length.isascii() or not length.isdecimal():
                return self.respond(400)
            # Reject huge decimal lengths *before* int() (Python limits integer
            # conversion digits). Leading zeroes do not increase the body limit.
            digits = length.lstrip("0")
            if len(digits) > len(str(MAX_BODY)):
                return self.respond(413)
            size = int(digits or "0")
            if size > MAX_BODY:
                return self.respond(413)
            try:
                body = self.rfile.read(size)
                if len(body) != size:
                    return self.respond(400)
                payload = json.loads(body)
            except (OSError, RecursionError, UnicodeError, ValueError):
                return self.respond(400)
            if not valid_alert(payload, time.time()):
                return self.respond(422)
            try:
                write_heartbeat(directory, time.time())
            except OSError:
                return self.respond(503)
            self.respond(204)

        def do_GET(self):
            self.respond(405)

        do_PUT = do_GET
        do_HEAD = do_GET
        do_DELETE = do_GET
        do_PATCH = do_GET

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--state-dir", required=True)
    args = parser.parse_args()
    with open(args.token_file, encoding="ascii") as credential:
        token = credential.read().strip()
    if not TOKEN_PATTERN.fullmatch(token):
        raise ValueError("Invalid watchdog credential")
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 19095), handler_for(token, args.state_dir))
    server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
