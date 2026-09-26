{ pkgs ? import <nixpkgs> { } }:
let
  fixturePython = pkgs.python3.withPackages (p: [ p.dnslib ]);
  fixture = pkgs.writeText "watchdog-private-endpoint.py" ''
    import http.server
    import threading
    from dnslib import A, RR
    from dnslib.server import BaseResolver, DNSServer

    class Resolver(BaseResolver):
        def resolve(self, request, handler):
            reply = request.reply()
            if str(request.q.qname) == "watchdog.bl.internal." and request.q.qtype == 1:
                reply.add_answer(RR(request.q.qname, ttl=1, rdata=A("100.96.0.1")))
            return reply

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            if self.path == "/watchdog" and self.headers.get("Authorization") == "Bearer " + "a" * 64:
                self.send_response(204)
            else:
                self.send_response(400)
            self.end_headers()

    DNSServer(Resolver(), address="100.96.0.1", port=53).start_thread()
    http.server.HTTPServer(("100.96.0.1", 19095), Handler).serve_forever()
  '';
  pythonTests = pkgs.runCommand "telemetry-watchdog-python-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 -m unittest discover -s ${./.} -p test_receiver.py -v
    touch $out
  '';
  smtpSink = pkgs.writeText "watchdog-smtp-sink.py" ''
    import socketserver

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            self.wfile.write(b"220 test.local ESMTP\r\n")
            self.wfile.flush()
            message = []
            in_data = False
            while line := self.rfile.readline():
                if in_data:
                    if line == b".\r\n":
                        with open("/run/watchdog-smtp-messages", "ab") as output:
                            output.write(b"".join(message))
                            output.write(b"\n---MESSAGE---\n")
                        message = []
                        in_data = False
                        self.wfile.write(b"250 stored\r\n")
                    else:
                        message.append(line)
                elif line.upper().startswith(b"EHLO"):
                    self.wfile.write(b"250 test.local\r\n")
                elif line.upper().startswith(b"DATA"):
                    self.wfile.write(b"354 end with dot\r\n")
                    in_data = True
                elif line.upper().startswith(b"QUIT"):
                    self.wfile.write(b"221 goodbye\r\n")
                    self.wfile.flush()
                    break
                else:
                    self.wfile.write(b"250 ok\r\n")
                self.wfile.flush()

    Server(("127.0.0.1", 2525), Handler).serve_forever()
  '';
in
pkgs.testers.runNixOSTest {
  name = "telemetry-watchdog";
  nodes = {
    sender = { config, lib, pkgs, ... }: {
      imports = [ ../../modules/telemetry-watchdog.nix ];
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; });
      };
      config = {
        sops.secrets.telemetryWatchdogToken.path = "/run/synthetic-watchdog-token";
        system.stateVersion = "26.05";
        networking.nftables = { enable = true; flushRuleset = false; };
        services.nginx.enable = true;
        custom.services.telemetryWatchdog = {
          enable = true;
          mode = "sender";
          secretsFile = ./test.nix;
          utilitySubnet = "100.96.0.0/24";
          dnsAddress = "100.96.0.1";
        };
        assertions = [{
          assertion = config.sops.secrets.telemetryWatchdogToken.restartUnits == [ "grafana.service" ];
          message = "Rotating the sender watchdog token must restart Grafana.";
        }];
        environment.systemPackages = [ pkgs.curl pkgs.nftables pkgs.iproute2 pkgs.dig ];
        systemd.services.watchdog-fixture = {
          wantedBy = [ "multi-user.target" ];
          before = [ "nginx.service" ];
          requiredBy = [ "nginx.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            ${pkgs.iproute2}/bin/ip netns add private-peer
            ${pkgs.iproute2}/bin/ip link add pgtel0 type veth peer name peer0
            ${pkgs.iproute2}/bin/ip link set peer0 netns private-peer
            ${pkgs.iproute2}/bin/ip addr add 100.96.0.2/24 dev pgtel0
            ${pkgs.iproute2}/bin/ip link set pgtel0 up
            ${pkgs.iproute2}/bin/ip -n private-peer addr add 100.96.0.1/24 dev peer0
            ${pkgs.iproute2}/bin/ip -n private-peer link set peer0 up
            ${pkgs.iproute2}/bin/ip -n private-peer link set lo up
          '';
        };
        systemd.services.watchdog-private-endpoint = {
          serviceConfig.ExecStart = "${pkgs.iproute2}/bin/ip netns exec private-peer ${fixturePython}/bin/python ${fixture}";
          serviceConfig.Restart = "on-failure";
        };
        services.nginx.virtualHosts."public-test" = {
          listen = [{ addr = "127.0.0.1"; port = 3110; ssl = false; }];
          locations."/".return = "200 'public works'";
        };
      };
    };
    receiver = { config, lib, pkgs, ... }:
      let
        # Only the VM's Monit unit uses the fast test config and a plaintext local
        # SMTP sink. /etc/monitrc remains the production-shape TLS/465 config.
        testMonit = pkgs.writeText "watchdog-test-monitrc" (lib.replaceStrings
          [ "set daemon 30" "with start delay 90" "include ${config.sops.secrets.telemetryWatchdogMonitConfig.path}" ]
          [
            ''set httpd port 2813 use address 127.0.0.1 allow localhost
          set daemon 1''
            "with start delay 0"
            "include /run/watchdog-test-mail.conf"
          ]
          config.services.monit.config);
        testMail = pkgs.writeText "watchdog-test-mail.conf" ''
          set mailserver 127.0.0.1 port 2525
          set mail-format { from: synthetic@example.invalid }
          set alert recipient@example.invalid
        '';
      in
      {
        imports = [ ../../modules/telemetry-watchdog.nix ];
        options.sops.secrets = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; });
        };
        config = {
          sops.secrets.telemetryWatchdogToken.path = "/run/synthetic-watchdog-token";
          sops.secrets.telemetryWatchdogMonitConfig.path = toString (pkgs.writeText "synthetic-monit-config" ''
            set mailserver mail.your-server.de port 465 username "synthetic" password "not-a-real-secret" using ssl
            set mail-format { from: synthetic@example.invalid }
            set alert recipient@example.invalid
          '');
          system.stateVersion = "26.05";
          custom.services.telemetryWatchdog = {
            enable = true;
            mode = "receiver";
            secretsFile = ./test.nix;
            collectorNiceId = "synthetic-collector";
          };
          assertions = [{
            assertion = config.sops.secrets.telemetryWatchdogToken.restartUnits == [ "telemetry-watchdog.service" ];
            message = "Rotating the receiver watchdog token must restart the receiver.";
          }];
          environment.systemPackages = [ pkgs.curl pkgs.python3 pkgs.ripgrep ];
          # Synthetic runtime credentials only; no actual SOPS file or SMTP server.
          systemd.services.telemetry-watchdog.serviceConfig.LoadCredential = lib.mkForce [ "token:${pkgs.writeText "synthetic-token" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}" ];
          systemd.services.monit = {
            preStart = ''
              ${pkgs.coreutils}/bin/install -m 0600 ${testMonit} /run/watchdog-test-monitrc
              ${pkgs.coreutils}/bin/install -m 0600 ${testMail} /run/watchdog-test-mail.conf
            '';
            serviceConfig.ExecStart = lib.mkForce "${pkgs.monit}/bin/monit -I -c /run/watchdog-test-monitrc";
            serviceConfig.ExecStop = lib.mkForce "${pkgs.monit}/bin/monit -c /run/watchdog-test-monitrc quit";
          };
          systemd.services.watchdog-smtp-sink.serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${smtpSink}";
        };
      };
  };
  testScript = ''
    import json

    def rejected_packets():
        rules = json.loads(sender.succeed("nft -j list chain inet telemetry_watchdog_proxy output"))
        for rule in rules["nftables"]:
            for part in rule.get("rule", {}).get("expr", []):
                if "counter" in part:
                    return part["counter"]["packets"]
        raise AssertionError("watchdog UID reject counter missing")

    start_all()
    sender.wait_for_unit("nginx.service")
    receiver.wait_for_unit("telemetry-watchdog.service")
    sender.succeed("curl -fsS http://127.0.0.1:3110/")
    sender.succeed("nft list table inet telemetry_watchdog_proxy")
    sender.succeed("curl -s -o /dev/null -w '%{http_code}' -X GET http://127.0.0.1:3103/watchdog | test $(cat) = 405" )
    sender.succeed("curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:3103/watchdog?x=1 | test $(cat) = 404")
    sender.succeed("curl --max-time 12 -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:3103/watchdog | test $(cat) = 502")
    sender.succeed("systemctl start watchdog-private-endpoint")
    sender.wait_until_succeeds("test \"$(dig +time=1 +tries=1 @100.96.0.1 watchdog.bl.internal A +short)\" = 100.96.0.1")
    sender.succeed("curl --max-time 12 -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) http://127.0.0.1:3103/watchdog | test $(cat) = 204")
    before_reject = rejected_packets()
    sender.succeed("ip link set pgtel0 down")
    sender.succeed("ip route add 100.96.0.1/32 dev eth1")
    sender.succeed("curl --max-time 12 -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:3103/watchdog | test $(cat) = 502")
    assert rejected_packets() > before_reject, "the nginx UID guard did not reject the fallback route"
    sender.succeed("nft -a list table inet telemetry_watchdog_proxy")
    sender.succeed("curl -fsS http://127.0.0.1:3110/")
    receiver.succeed("curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:19095/watchdog | test $(cat) = 401")
    receiver.fail("test -e /var/lib/telemetry-watchdog/heartbeat.json")
    receiver.succeed("monit -t -c /etc/monitrc")
    receiver.wait_for_unit("monit.service")
    receiver.succeed("test -d /var/lib/telemetry-watchdog-monit/queue")
    receiver.succeed("monit -t -c /run/watchdog-test-monitrc")
    # No fabricated heartbeat at startup; absent file must fail while SMTP is
    # down and the pending notification must survive in the durable queue.
    receiver.wait_until_succeeds("test -n \"$(ls -A /var/lib/telemetry-watchdog-monit/queue)\"")
    receiver.succeed("systemctl start watchdog-smtp-sink")
    receiver.wait_until_succeeds("test -f /run/watchdog-smtp-messages")
    receiver.wait_until_succeeds("test -z \"$(ls -A /var/lib/telemetry-watchdog-monit/queue)\"")
    receiver.succeed("rg -i 'does not exist' /run/watchdog-smtp-messages")
    missing_count = int(receiver.succeed("rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages").strip())
    receiver.succeed("curl -fsS -o /dev/null -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) -d '{\"alerts\":[{\"status\":\"firing\",\"labels\":{\"alertname\":\"TelemetryWatchdog\",\"watchdog\":\"central\"},\"annotations\":{\"watchdog_evaluated_at\":\"'$(date +%s)'\"}}]}' http://127.0.0.1:19095/watchdog")
    receiver.wait_until_succeeds("journalctl -u monit.service --no-pager | rg \"'telemetry-watchdog-heartbeat' file exists\"", timeout=20)
    receiver.wait_until_succeeds("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -ge " + str(missing_count + 1), timeout=20)
    receiver.succeed("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -eq " + str(missing_count + 1))
    accepted_mtime = receiver.succeed("stat -c %y /var/lib/telemetry-watchdog/heartbeat.json").strip()
    receiver.succeed("test \"$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) -d 'not-json' http://127.0.0.1:19095/watchdog)\" = 400")
    receiver.succeed("test \"$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) -d '{\"alerts\":[{\"status\":\"resolved\",\"labels\":{\"alertname\":\"TelemetryWatchdog\",\"watchdog\":\"central\"},\"annotations\":{\"watchdog_evaluated_at\":\"'$(date +%s)'\"}}]}' http://127.0.0.1:19095/watchdog)\" = 422")
    receiver.succeed("test \"$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) -d '{\"alerts\":[{\"status\":\"firing\",\"labels\":{\"alertname\":\"TelemetryWatchdog\",\"watchdog\":\"central\"},\"annotations\":{\"watchdog_evaluated_at\":\"'$(($(date +%s)-300))'\"}}]}' http://127.0.0.1:19095/watchdog)\" = 422")
    assert receiver.succeed("stat -c %y /var/lib/telemetry-watchdog/heartbeat.json").strip() == accepted_mtime
    receiver.succeed("systemctl restart telemetry-watchdog")
    receiver.succeed("test -f /var/lib/telemetry-watchdog/heartbeat.json")
    assert receiver.succeed("stat -c %y /var/lib/telemetry-watchdog/heartbeat.json").strip() == accepted_mtime
    receiver.succeed("touch -d '10 minutes ago' /var/lib/telemetry-watchdog/heartbeat.json")
    # Monit's unqualified 'timestamp' uses max(ctime, mtime), so touching mtime
    # would be masked by fresh ctime; the module explicitly checks mtime.
    receiver.wait_until_succeeds("journalctl -u monit.service --no-pager | rg 'modify time.*failed'", timeout=20)
    receiver.wait_until_succeeds("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -ge " + str(missing_count + 2), timeout=20)
    receiver.succeed("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -eq " + str(missing_count + 2))
    receiver.succeed("curl -fsS -o /dev/null -X POST -H 'Authorization: Bearer '$(printf 'a%.0s' {1..64}) -d '{\"alerts\":[{\"status\":\"firing\",\"labels\":{\"alertname\":\"TelemetryWatchdog\",\"watchdog\":\"central\"},\"annotations\":{\"watchdog_evaluated_at\":\"'$(date +%s)'\"}}]}' http://127.0.0.1:19095/watchdog")
    receiver.wait_until_succeeds("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -ge " + str(missing_count + 3), timeout=20)
    receiver.succeed("test \"$(rg -c '^---MESSAGE---$' /run/watchdog-smtp-messages)\" -eq " + str(missing_count + 3))
    sender.succeed("systemctl stop telemetry-watchdog-proxy-guard")
    sender.succeed("nft list table inet telemetry_watchdog_proxy")
    sender.succeed("curl -fsS http://127.0.0.1:3110/")
  '';
  extraPythonPackages = _p: [ ];
  passthru.pythonTests = pythonTests;
}
