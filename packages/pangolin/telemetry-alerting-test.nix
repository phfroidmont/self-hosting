{ pkgs ? import <nixpkgs> { } }:
let
  lib = pkgs.lib;
  host = { host = "backend1-staging"; environment = "staging"; role = "backend"; };
  fixture = lib.evalModules {
    modules = [
      ../../modules/grafana-alerting.nix
      ({ lib, ... }: {
        options = {
          custom.services.grafana.enable = lib.mkOption { type = lib.types.bool; default = true; };
          custom.services.grafana.telemetryHosts = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ host ]; };
          services.grafana.settings = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
          services.grafana.provision.alerting = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
          sops.secrets = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
          users.users.grafana.name = lib.mkOption { type = lib.types.str; default = "grafana"; };
        };
        config = {
          custom.services.grafana.alerting.enable = true;
          custom.services.grafana.alerting.secretsFile = /tmp/telemetry-alerts.enc.yml;
          sops.secrets.telemetryWatchdogToken.path = "/run/secrets/telemetryWatchdogToken";
          sops.secrets.telemetrySmtpUser.path = "/run/secrets/telemetrySmtpUser";
          sops.secrets.telemetrySmtpPassword.path = "/run/secrets/telemetrySmtpPassword";
          sops.secrets.telemetryStagingRecipient.path = "/run/secrets/telemetryStagingRecipient";
          sops.secrets.telemetryProductionRecipient.path = "/run/secrets/telemetryProductionRecipient";
        };
      })
    ];
  };
  rules = (builtins.head fixture.config.services.grafana.provision.alerting.rules.settings.groups).rules;
  oversizedRules = (builtins.head (fixture.extendModules {
    modules = [{ custom.services.grafana.telemetryHosts = lib.mkForce [ (host // { host = "backend-with-overlong-unique-name-staging"; }) ]; }];
  }).config.services.grafana.provision.alerting.rules.settings.groups).rules;
  byUid = uid: builtins.head (builtins.filter (r: r.uid == uid) rules);
  watchdog = byUid "ov-telemetry-watchdog";
  target = byUid "ov-target-node-backend1-staging";
  contacts = fixture.config.services.grafana.provision.alerting.contactPoints.settings.contactPoints;
  policies = (builtins.head fixture.config.services.grafana.provision.alerting.policies.settings.policies).routes;
in
assert builtins.length rules == 9; # four resources, three targets, one heartbeat, watchdog
assert lib.all (r: lib.hasPrefix "ov-" r.uid && r.condition == "B" && r.noDataState == "OK") rules;
assert lib.all (r: builtins.stringLength r.uid <= 40) rules;
assert !(builtins.tryEval (builtins.deepSeq oversizedRules true)).success;
assert (byUid "ov-filesystem").for == "1m";
assert (builtins.head (byUid "ov-cpu").data).model.expr == "100 * (1 - avg by (environment, instance, host) (rate(node_cpu_seconds_total{job=\"node\",environment=~\"staging|production\",mode=\"idle\"}[5m])))";
assert lib.hasInfix "absent(up" (builtins.head target.data).model.expr;
assert target.for == "2m" && target.labels.environment == "staging";
assert (builtins.head (byUid "ov-logs-backend1-staging").data).datasourceUid == "P8E80F9AEF21F6940";
assert (builtins.head (byUid "ov-logs-backend1-staging").data).model.queryType == "instant";
assert watchdog.title == "TelemetryWatchdog" && watchdog.labels.watchdog == "central";
assert watchdog.execErrState == "OK" && watchdog.noDataState == "OK";
assert (builtins.head watchdog.data).model.expr == "up{job=\"prometheus\",instance=\"127.0.0.1:9090\"}";
assert (builtins.elemAt watchdog.data 1).model.expr == "time()";
assert watchdog.annotations.watchdog_evaluated_at == "{{ printf \"%.0f\" $values.T.Value }}";
assert (builtins.head policies).receiver == "Telemetry watchdog" && (builtins.head policies).repeat_interval == "1m";
assert (builtins.head (builtins.elemAt contacts 2).receivers).settings.authorization_credentials == "$__file{/run/secrets/telemetryWatchdogToken}";
assert (builtins.head (builtins.elemAt contacts 2).receivers).disableResolveMessage;
assert fixture.config.services.grafana.settings.smtp.host == "mail.your-server.de:465";
assert fixture.config.sops.secrets.telemetrySmtpPassword.key == "smtp/password";
assert lib.all (secret: secret.restartUnits == [ "grafana.service" ]) (map (name: fixture.config.sops.secrets.${name}) [ "telemetrySmtpUser" "telemetrySmtpPassword" "telemetryStagingRecipient" "telemetryProductionRecipient" ]);
pkgs.testers.runNixOSTest {
  name = "telemetry-alerting";
  nodes.collector = { lib, pkgs, ... }: {
    imports = [ ../../modules/grafana-alerting.nix ];
    options = {
      custom.services.grafana.enable = lib.mkOption { type = lib.types.bool; default = true; };
      custom.services.grafana.telemetryHosts = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ host ]; };
      # Stand-in for sops-nix: fixture-only files, no encryption keys or real credentials.
      sops.secrets = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    };
    config = {
      custom.services.grafana.alerting.enable = true;
      custom.services.grafana.alerting.secretsFile = pkgs.writeText "synthetic-sops-ciphertext" "fixture-only";
      sops.secrets = {
        telemetryWatchdogToken.path = "/etc/telemetry-test/watchdog-token";
        telemetrySmtpUser.path = "/etc/telemetry-test/smtp-user";
        telemetrySmtpPassword.path = "/etc/telemetry-test/smtp-password";
        telemetryStagingRecipient.path = "/etc/telemetry-test/staging-recipient";
        telemetryProductionRecipient.path = "/etc/telemetry-test/production-recipient";
      };
      environment.etc = {
        "telemetry-test/watchdog-token".text = "fixture-watchdog-token";
        "telemetry-test/smtp-user".text = "fixture@example.invalid";
        "telemetry-test/smtp-password".text = "fixture-password";
        "telemetry-test/staging-recipient".text = "staging@example.invalid";
        "telemetry-test/production-recipient".text = "production@example.invalid";
      };
      services.grafana = {
        enable = true;
        provision.enable = true;
        provision.datasources.settings.datasources = [
          { name = "Prometheus"; uid = "PBFA97CFB590B2093"; type = "prometheus"; url = "http://127.0.0.1:19090"; isDefault = true; }
          { name = "Loki"; uid = "P8E80F9AEF21F6940"; type = "loki"; url = "http://127.0.0.1:13100"; }
        ];
        settings = {
          security.admin_user = "fixture-admin";
          security.admin_password = "fixture-admin-password";
          security.secret_key = "fixture-grafana-encryption-key-only-for-vm";
          smtp.host = lib.mkForce "127.0.0.1:2525";
        };
      };
      environment.systemPackages = [ pkgs.curl pkgs.jq pkgs.python3 ];
      systemd.services.telemetry-fixture = {
        wantedBy = [ "multi-user.target" ];
        before = [ "grafana.service" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "telemetry-fixture-server.py" ''
          import json
          import socketserver
          import time
          from pathlib import Path
          from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
          from threading import Thread
          from urllib.parse import parse_qs, urlparse

          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  url = urlparse(self.path)
                  expression = parse_qs(url.query).get("query", [""])[0]
                  if url.path.startswith("/control/"):
                      Path("/tmp/telemetry-selfup").write_text(url.path.removeprefix("/control/"))
                      self.send_response(200)
                      self.end_headers()
                      return
                  if url.path.endswith(("/api/v1/query", "/api/v1/query_range")):
                      if "up{" in expression and "prometheus" in expression and Path("/tmp/telemetry-selfup").read_text() == "error":
                          self.send_response(500)
                          self.end_headers()
                          return
                      if "time()" in expression:
                          metric, value = {}, time.time()
                      elif "up{" in expression and "prometheus" in expression:
                          metric, value = {"job": "prometheus", "instance": "127.0.0.1:9090"}, 0 if Path("/tmp/telemetry-selfup").read_text() == "down" else 1
                      elif "up{" in expression and "backend1-staging" in expression:
                          metric, value = {"job": "node", "instance": "backend1-staging", "environment": "staging"}, 1 if Path("/tmp/telemetry-selfup").read_text() == "node-down" else 0
                      elif "absent_over_time" in expression:
                          metric, value = {"host": "backend1-staging", "environment": "staging"}, 1 if Path("/tmp/telemetry-selfup").read_text() == "logs-missing" else 0
                      else:
                          metric, value = {}, 0
                      instant = not url.path.endswith("/api/v1/query_range")
                      # Loki range results must lie inside Grafana's requested
                      # evaluation window, not at wall-clock time (+~2 seconds).
                      raw_end = float(parse_qs(url.query)["end"][0]) if not instant else time.time()
                      end = raw_end / 1e9 if raw_end > 1e12 else raw_end
                      sample = {"metric": metric, "value" if instant else "values": [end, str(value)] if instant else [[end - 1, str(value)]]}
                      result = [] if "up{" in expression and "prometheus" in expression and Path("/tmp/telemetry-selfup").read_text() == "nodata" else [sample]
                      body = {"status": "success", "data": {"resultType": "vector" if instant else "matrix", "result": result}}
                  elif url.path.endswith("/api/v1/status/buildinfo"):
                      body = {"status": "success", "data": {"version": "3.0.0"}}
                  else:
                      body = {"status": "success", "data": {"resultType": "vector", "result": []}}
                  encoded = json.dumps(body).encode()
                  self.send_response(200)
                  self.send_header("Content-Type", "application/json")
                  self.send_header("Content-Length", str(len(encoded)))
                  self.end_headers()
                  self.wfile.write(encoded)

              def do_POST(self):
                  payload = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                  if self.path.endswith("/api/v1/query"):
                      # Grafana's Prometheus client sends instant queries as POST
                      # form bodies, not as GET query parameters.
                      self.path += "?" + payload.decode()
                      return self.do_GET()
                  with open("/tmp/telemetry-webhook.jsonl", "ab") as out:
                      out.write(json.dumps({"authorization": self.headers.get("Authorization"), "body": json.loads(payload)}).encode() + b"\n")
                  self.send_response(200)
                  self.end_headers()

              def log_message(self, *args):
                  pass

          for port in (19090, 13100, 3103):
              Thread(target=ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever, daemon=True).start()
          Path("/tmp/telemetry-selfup").write_text("up")

          class SMTP(socketserver.StreamRequestHandler):
              def handle(self):
                  self.wfile.write(b"220 fixture ESMTP\r\n")
                  while line := self.rfile.readline():
                      command = line.upper().split(b" ", 1)[0].strip()
                      if command in (b"EHLO", b"HELO"):
                          self.wfile.write(b"250-localhost\r\n250-AUTH PLAIN LOGIN\r\n250 8BITMIME\r\n")
                      elif command == b"AUTH":
                          self.wfile.write(b"235 authenticated\r\n")
                      elif command == b"DATA":
                          self.wfile.write(b"354 End with <CRLF>.<CRLF>\r\n")
                          lines = []
                          while (part := self.rfile.readline()) != b".\r\n":
                              lines.append(part)
                          with open("/tmp/telemetry-email", "ab") as out:
                              out.write(b"".join(lines))
                          self.wfile.write(b"250 queued\r\n")
                      elif command == b"QUIT":
                          self.wfile.write(b"221 bye\r\n")
                          break
                      else:
                          self.wfile.write(b"250 ok\r\n")

          with socketserver.ThreadingTCPServer(("127.0.0.1", 2525), SMTP) as smtp:
              smtp.serve_forever()
        ''}";
      };
    };
  };
  testScript = ''
    import json
    import time

    start_all()
    collector.wait_for_unit("telemetry-fixture.service")
    collector.wait_for_unit("grafana.service")
    collector.wait_for_open_port(3000, "127.0.0.1")
    base = "http://fixture-admin:fixture-admin-password@127.0.0.1:3000"

    def api(path):
        return json.loads(collector.succeed("curl --fail --silent --retry 8 --retry-delay 2 '" + base + path + "'"))

    rules = api("/api/v1/provisioning/alert-rules")
    assert len(rules) == 9, rules
    assert {r["uid"] for r in rules} == {"ov-filesystem", "ov-ram", "ov-cpu", "ov-systemd", "ov-target-node-backend1-staging", "ov-target-nginx-backend1-staging", "ov-target-osteoview-backend1-staging", "ov-logs-backend1-staging", "ov-telemetry-watchdog"}, rules
    watchdog = next(r for r in rules if r["uid"] == "ov-telemetry-watchdog")
    assert watchdog["annotations"]["watchdog_evaluated_at"] == '{{ printf "%.0f" $values.T.Value }}', watchdog
    assert next(r for r in rules if r["uid"] == "ov-filesystem")["annotations"]["summary"].endswith("{{ $labels.instance }}"), rules
    contacts = api("/api/v1/provisioning/contact-points")
    assert len(contacts) >= 3, contacts
    assert any(c.get("uid") == "ov-receiver-watchdog" for c in contacts), contacts
    assert next(c for c in contacts if c.get("uid") == "ov-receiver-watchdog")["disableResolveMessage"], contacts
    assert any("staging@example.invalid" in str(c) for c in contacts), contacts
    policies = api("/api/v1/provisioning/policies")
    assert policies["routes"][0]["receiver"] == "Telemetry watchdog", policies

    # No live recipients: webhook and SMTP are both local fixture sinks.
    collector.wait_until_succeeds("test -s /tmp/telemetry-webhook.jsonl", timeout=180)
    incoming = json.loads(collector.succeed("python3 -c 'import pathlib; print(pathlib.Path(\"/tmp/telemetry-webhook.jsonl\").read_text().splitlines()[0])'"))
    assert incoming["authorization"] == "Bearer fixture-watchdog-token", incoming
    assert incoming["body"]["status"] == "firing", incoming
    assert all(a["labels"].get("alertname") == "TelemetryWatchdog" and a["labels"].get("watchdog") == "central" for a in incoming["body"]["alerts"]), incoming
    for alert in incoming["body"]["alerts"]:
        stamp = alert["annotations"]["watchdog_evaluated_at"]
        assert stamp.isdigit() and abs(time.time() - int(stamp)) < 180, stamp
    collector.wait_until_succeeds("test $(wc -l < /tmp/telemetry-webhook.jsonl) -ge 2", timeout=140)
    second = json.loads(collector.succeed("python3 -c 'import pathlib; print(pathlib.Path(\"/tmp/telemetry-webhook.jsonl\").read_text().splitlines()[-1])'"))
    assert second["authorization"] == "Bearer fixture-watchdog-token", second
    assert all(a["labels"].get("alertname") == "TelemetryWatchdog" and a["labels"].get("watchdog") == "central" and a["annotations"]["watchdog_evaluated_at"].isdigit() and abs(time.time() - int(a["annotations"]["watchdog_evaluated_at"])) < 180 for a in second["body"]["alerts"]), second

    # A self-scrape of zero must resolve the watchdog, and the webhook must not
    # send a resolved notification. Real receivers additionally enforce freshness.
    collector.succeed("curl --fail --silent http://127.0.0.1:19090/control/down")
    time.sleep(75)
    count = int(collector.succeed("wc -l < /tmp/telemetry-webhook.jsonl"))
    time.sleep(70)
    assert int(collector.succeed("wc -l < /tmp/telemetry-webhook.jsonl")) == count
    collector.fail("test -s /tmp/telemetry-email")
    for mode in ("nodata", "error"):
        collector.succeed("curl --fail --silent http://127.0.0.1:19090/control/" + mode)
        time.sleep(70)
        assert int(collector.succeed("wc -l < /tmp/telemetry-webhook.jsonl")) == count, mode

    # After the watchdog is silent, inject failing target and absent log samples.
    collector.succeed("curl --fail --silent http://127.0.0.1:19090/control/node-down")
    collector.wait_until_succeeds("test -s /tmp/telemetry-email", timeout=230)
    message = collector.succeed("python3 -c 'import pathlib; print(pathlib.Path(\"/tmp/telemetry-email\").read_text())'")
    assert "staging@example.invalid" in message and "[STAGING]" in message, message
    collector.succeed("curl --fail --silent http://127.0.0.1:19090/control/logs-missing")
    collector.wait_until_succeeds("python3 -c 'import pathlib; assert \"Journal heartbeat missing\" in pathlib.Path(\"/tmp/telemetry-email\").read_text()'", timeout=230)
  '';
}
