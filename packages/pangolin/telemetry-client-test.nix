{ pkgs ? import <nixpkgs> { } }:

let
  # Check the final merged option, including NixOS's implicit flush default
  # for raw rulesets and older state versions, without booting extra VMs.
  acceptsFirewall = extra:
    let
      evaluated = import "${pkgs.path}/nixos/lib/eval-config.nix" {
        inherit pkgs;
        system = pkgs.stdenv.hostPlatform.system;
        modules = [
          ../../modules/pangolin-telemetry-client.nix
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
            services.pangolin-telemetry = {
              enable = true;
              credentialsFile = "/run/test-credentials";
              utilitySubnet = "100.96.0.0/24";
              dnsAddress = "100.96.0.1";
              consumerUnit = "collector";
              consumerUser = "collector";
              allowedTCPPorts = [ ];
            };
            users.users.collector = { uid = 991; group = "collector"; };
            users.groups.collector = { };
          }
          extra
        ];
      };
    in
    pkgs.lib.all (a: a.assertion || !pkgs.lib.hasPrefix "pangolin-telemetry:" a.message)
      evaluated.config.assertions;

  # A real Go resolver/HTTP consumer, with a local control endpoint for probes.
  probeSource = pkgs.writeText "telemetry-probe.go" ''
    package main
    import (
      "encoding/json"
      "io"
      "net"
      "net/http"
      "os"
      "time"
    )
    func main() {
      client := &http.Client{Timeout: 2 * time.Second}
      http.HandleFunc("/fetch", func(w http.ResponseWriter, r *http.Request) {
        response, err := client.Get(r.URL.Query().Get("url"))
        if err != nil { http.Error(w, err.Error(), 503); return }
        defer response.Body.Close()
        io.Copy(w, response.Body)
      })
      http.HandleFunc("/lookup", func(w http.ResponseWriter, r *http.Request) {
        addresses, err := net.LookupHost(r.URL.Query().Get("name"))
        if err != nil { http.Error(w, err.Error(), 503); return }
        json.NewEncoder(w).Encode(addresses)
      })
      http.HandleFunc("/env", func(w http.ResponseWriter, r *http.Request) {
        json.NewEncoder(w).Encode(os.Environ())
      })
      http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        io.WriteString(w, "collecting\n")
      })
      panic(http.ListenAndServe("127.0.0.1:19100", nil))
    }
  '';
  probe = pkgs.runCommand "telemetry-probe" { nativeBuildInputs = [ pkgs.go ]; } ''
    export GOCACHE=$TMPDIR/go-cache
    mkdir -p $out/bin
    CGO_ENABLED=0 go build -o $out/bin/telemetry-probe ${probeSource}
  '';
  python = pkgs.python3.withPackages (p: [ p.dnslib ]);
  endpoints = pkgs.writeText "telemetry-test-endpoints.py" ''
    import http.server
    import socket
    import threading
    from dnslib import A, RR, RCODE
    from dnslib.server import BaseResolver, DNSServer

    class Resolver(BaseResolver):
        def resolve(self, request, handler):
            reply = request.reply()
            records = {"metrics.internal.": "100.96.0.2", "ordinary.test.": "192.0.2.2"}
            address = records.get(str(request.q.qname))
            if address and request.q.qtype == 1:
                reply.add_answer(RR(request.q.qname, ttl=1, rdata=A(address)))
            elif not address:
                reply.header.rcode = RCODE.SERVFAIL
            return reply

    # Bind each address so UDP replies originate from the queried address.
    for address in ["100.96.0.1", "100.96.0.2", "192.0.2.2"]:
        for port, tcp in [(53, False), (53, True), (5353, False)]:
            DNSServer(Resolver(), address=address, port=port, tcp=tcp).start_thread()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"fixture metric 1\n")

    for port in [9100, 9101, 9102]:
        server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    class IPv6Server(http.server.ThreadingHTTPServer):
        address_family = socket.AF_INET6
    IPv6Server(("2001:db8::2", 9100), Handler).serve_forever()
  '';
in
assert acceptsFirewall { };
assert acceptsFirewall { networking.nftables = { enable = true; flushRuleset = false; }; };
assert !(acceptsFirewall { networking.nftables = { enable = true; flushRuleset = true; }; });
assert !(acceptsFirewall { networking.nftables = { enable = true; ruleset = "table inet regression {}"; }; });
assert !(acceptsFirewall { networking.nftables.enable = true; system.stateVersion = pkgs.lib.mkForce "23.05"; });
pkgs.testers.runNixOSTest {
  name = "pangolin-telemetry-client";

  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [ ../../modules/pangolin-telemetry-client.nix ];

    services.pangolin-telemetry = {
      enable = true;
      credentialsFile = "/run/telemetry-test/credentials.json";
      # Native Olm runs without contacting any real control plane.
      endpoint = "http://127.0.0.1:9";
      utilitySubnet = "100.96.0.0/24";
      dnsAddress = "100.96.0.1";
      consumerUnit = "collector";
      consumerUser = "collector";
      allowedTCPPorts = [ 9100 ];
      legacyDestinations = [
        { address = "192.0.2.2"; port = 9101; interface = "legacy0"; }
      ];
    };
    # Like NixOS's Prometheus user, a fixed UID need not set isSystemUser.
    users.users.collector = { uid = 991; group = "collector"; };
    users.groups.collector = { };
    # Exercise the first start explicitly, including a failed guard install.
    systemd.services.pangolin-telemetry-guard.wantedBy = lib.mkForce [ ];
    systemd.services.collector = {
      wantedBy = lib.mkForce [ ];
      environment = {
        HTTP_PROXY = "http://127.0.0.1:9";
        https_proxy = "http://127.0.0.1:9";
        ALL_PROXY = "http://127.0.0.1:9";
      };
      serviceConfig = {
        ExecStart = "${probe}/bin/telemetry-probe";
        # The privileged guard pre-start must also work for hardened collectors.
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        PrivateUsers = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    networking.nameservers = [ "192.0.2.2" ];
    networking.useDHCP = false;
    # The fixture deliberately selects the supported, table-scoped nftables
    # backend. The telemetry module itself must not select a host backend.
    networking.nftables = { enable = true; flushRuleset = false; };
    environment.systemPackages = [ pkgs.curl pkgs.dig pkgs.nftables pkgs.iproute2 pkgs.jq ];

    # Only the fixture servers use a namespace. Olm and the collector must both
    # remain in the host network namespace. No second VM or live server needed.
    systemd.services.telemetry-test-fixture = {
      wantedBy = [ "multi-user.target" ];
      before = [ "pangolin-telemetry.service" ];
      requiredBy = [ "pangolin-telemetry.service" ];
      path = [ pkgs.iproute2 pkgs.nftables ];
      preStart = ''
        install -d -m 0700 /run/telemetry-test
        printf '%s\n' '{"id":"test-only-id","secret":"test-only-secret"}' > /run/telemetry-test/credentials.json
        chmod 0600 /run/telemetry-test/credentials.json
        # An unrelated, shared UAPI directory must not be chowned or chmodded.
        install -d -m 0750 -o collector -g collector /run/wireguard
        touch /run/wireguard/unrelated
        nft add table inet unrelated
        ip netns add endpoints
        ip link add pgtel0 type veth peer name tunpeer
        ip link set tunpeer netns endpoints
        ip address add 100.96.0.254/24 dev pgtel0
        ip link set pgtel0 up
        ip -n endpoints address add 100.96.0.1/24 dev tunpeer
        ip -n endpoints address add 100.96.0.2/24 dev tunpeer
        ip -n endpoints link set tunpeer up
        ip -n endpoints link set lo up
        ip link add legacy0 type veth peer name legacypeer
        ip link set legacypeer netns endpoints
        ip address add 192.0.2.1/24 dev legacy0
        ip -6 address add 2001:db8::1/64 dev legacy0 nodad
        ip link set legacy0 up
        ip -n endpoints address add 192.0.2.2/24 dev legacypeer
        ip -n endpoints address add 192.0.2.3/24 dev legacypeer
        ip -n endpoints -6 address add 2001:db8::2/64 dev legacypeer nodad
        ip -n endpoints link set legacypeer up
        ip -n endpoints address add 203.0.113.9/32 dev lo
        ip route add 203.0.113.9/32 via 192.0.2.2 dev legacy0
        ip route add default via 192.0.2.2 dev legacy0
      '';
      serviceConfig.ExecStart = "${pkgs.iproute2}/bin/ip netns exec endpoints ${python}/bin/python ${endpoints}";
    };

    virtualisation.memorySize = 768;
    assertions = [
      { assertion = !config.networking.nftables.flushRuleset; message = "The host firewall must preserve separately owned tables."; }
      { assertion = config.networking.firewall.enable; message = "Keep the ordinary host firewall enabled."; }
      { assertion = !(config.systemd.services.collector.serviceConfig.PrivateNetwork or false); message = "Collector must share the host network."; }
    ];
  };

  testScript = ''
    import json
    import shlex

    machine.start()
    machine.wait_for_unit("pangolin-telemetry.service")
    machine.wait_for_unit("telemetry-test-fixture.service")
    machine.wait_for_unit("nftables.service")

    # An incompatible existing base chain makes nft reject the guard's atomic
    # transaction. Neither a failed guard unit nor its failed pre-start may let
    # the collector execute. Restore only our table and then start normally.
    machine.succeed("nft add table inet pangolin_telemetry")
    machine.succeed("nft 'add chain inet pangolin_telemetry output { type nat hook output priority 10; policy accept; }'")
    machine.fail("systemctl start pangolin-telemetry-guard")
    machine.succeed("systemctl is-failed pangolin-telemetry-guard")
    machine.fail("systemctl start collector")
    machine.succeed("systemctl is-failed collector")
    assert machine.succeed("systemctl show -p MainPID --value collector").strip() == "0"
    assert "status=1" in machine.succeed("systemctl show -p ExecStartPre --value collector")
    machine.succeed("nft delete table inet pangolin_telemetry")
    machine.succeed("systemctl reset-failed pangolin-telemetry-guard collector")
    machine.succeed("systemctl start pangolin-telemetry-guard collector")
    machine.wait_for_unit("collector.service")
    machine.wait_until_succeeds("curl -fsS http://192.0.2.2:9100", timeout=30)
    machine.wait_until_succeeds("test -S /run/pangolin-telemetry/api.sock", timeout=30)

    def probe(path):
        return "curl --max-time 5 -fsS " + shlex.quote("http://127.0.0.1:19100" + path)

    def fetch(url):
        return probe("/fetch?url=" + url)

    def denied(url):
        machine.fail(fetch(url))

    pid = machine.succeed("systemctl show -p MainPID --value collector").strip()
    olm_pid = machine.succeed("systemctl show -p MainPID --value pangolin-telemetry").strip()
    host_resolver = machine.succeed("cat /etc/resolv.conf")
    assert "nameserver 192.0.2.2" in host_resolver
    private_resolver = machine.succeed(f"cat /proc/{pid}/root/etc/resolv.conf")
    assert "nameserver 100.96.0.1" in private_resolver
    assert "192.0.2.2" not in private_resolver
    for process in [pid, olm_pid]:
        machine.succeed(f"test $(readlink /proc/{process}/ns/net) = $(readlink /proc/1/ns/net)")
    machine.succeed(f"cmp /etc/hosts /proc/{pid}/root/etc/hosts")
    assert "127.0.0.1" in machine.succeed(probe("/lookup?name=localhost"))
    assert "100.96.0.2" in machine.succeed(probe("/lookup?name=metrics.internal"))
    machine.succeed("getent hosts ordinary.test")
    machine.fail(probe("/lookup?name=missing.invalid"))
    env = json.loads(machine.succeed(probe("/env")))
    assert "GODEBUG=netdns=go" in env
    assert not any("proxy=" in entry.lower() for entry in env)

    # Real Olm writes its full config. Assert the false-boolean workaround and
    # dead upstream survive SaveConfig, and neither secrets nor APIs leak.
    saved = json.loads(machine.succeed("cat /run/pangolin-telemetry/config.json"))
    assert saved["overrideDNS"] is False
    assert saved["upstreamDNS"] == ["127.0.0.1:9"]
    assert saved["interface"] == "pgtel0" and saved["logLevel"] == "INFO"
    machine.succeed("test $(stat -c %U:%G:%a /run/pangolin-telemetry) = root:root:700")
    machine.succeed("test $(stat -c %U:%G:%a /run/pangolin-telemetry/config.json) = root:root:600")
    machine.succeed("test $(stat -c %U:%G:%a /run/wireguard) = collector:collector:750")
    machine.succeed("test -f /run/wireguard/unrelated")
    machine.fail("runuser -u collector -- cat /run/pangolin-telemetry/config.json")
    machine.fail("runuser -u collector -- curl --unix-socket /run/pangolin-telemetry/api.sock http://localhost/")
    machine.fail("ss -lnt | grep ':4444 '")
    machine.fail(f"tr '\\0' ' ' </proc/{olm_pid}/cmdline | grep test-only-secret")
    machine.fail("journalctl -u pangolin-telemetry --no-pager | grep test-only-secret")

    # Reachable fixture endpoints distinguish policy rejection from a dead server.
    machine.succeed(fetch("http://metrics.internal:9100"))
    machine.succeed(fetch("http://192.0.2.2:9101"))
    machine.succeed(fetch("http://127.0.0.1:19100/"))
    for url in ["http://203.0.113.9:9100", "http://[2001:db8::2]:9100", "http://100.96.0.2:9102", "http://192.0.2.2:9102", "http://192.0.2.3:9101"]:
        machine.succeed("curl --max-time 3 -fsS " + shlex.quote(url))
        denied(url)
    machine.succeed("runuser -u collector -- dig @100.96.0.1 metrics.internal +short +tries=1 +time=1 | grep 100.96.0.2")
    for args in ["@100.96.0.2", "@192.0.2.2", "@100.96.0.1 +tcp", "@100.96.0.1 -p 5353"]:
        machine.succeed("dig " + args + " metrics.internal +short +tries=1 +time=1 | grep 100.96.0.2")
        machine.fail("runuser -u collector -- dig " + args + " metrics.internal +short +tries=1 +time=1")

    # Atomic reload owns only its table. Stopping the guard doesn't remove it
    # or stop the collector; restarting the collector still reapplies the guard.
    machine.succeed("systemctl reload pangolin-telemetry-guard")
    machine.succeed("systemctl is-active pangolin-telemetry-guard")
    machine.succeed("nft list table inet unrelated")
    machine.succeed("systemctl stop pangolin-telemetry-guard")
    assert machine.succeed("systemctl show -p ActiveState --value pangolin-telemetry-guard").strip() == "inactive"
    machine.succeed("nft list table inet pangolin_telemetry")
    machine.succeed("systemctl is-active collector")
    denied("http://203.0.113.9:9100")

    # With the guard stopped, firewall reload/restart cannot rely on the guard
    # being reapplied. Its existing table must survive and keep rejecting egress.
    for operation in ["reload", "restart"]:
        machine.succeed(f"systemctl {operation} nftables")
        machine.succeed("systemctl is-active nftables")
        machine.succeed("nft list table inet pangolin_telemetry")
        machine.succeed("nft list table inet unrelated")
        machine.succeed("systemctl is-active collector")
        assert machine.succeed("systemctl show -p ActiveState --value pangolin-telemetry-guard").strip() == "inactive"
        assert machine.succeed("systemctl show -p MainPID --value collector").strip() == pid
        denied("http://203.0.113.9:9100")
        denied("http://[2001:db8::2]:9100")
        machine.succeed(fetch("http://metrics.internal:9100"))
        machine.succeed(fetch("http://192.0.2.2:9101"))

    # A correct destination/port on a wrong output interface remains forbidden.
    machine.succeed("ip route replace 100.96.0.0/24 via 192.0.2.2 dev legacy0")
    machine.succeed("curl -fsS http://100.96.0.2:9100")
    denied("http://100.96.0.2:9100")
    machine.fail(probe("/lookup?name=metrics.internal"))
    machine.succeed("ip route replace 100.96.0.0/24 dev pgtel0 src 100.96.0.254")
    machine.succeed("ip route add 192.0.2.2/32 via 100.96.0.1 dev pgtel0")
    machine.succeed("curl -fsS http://192.0.2.2:9101")
    denied("http://192.0.2.2:9101")
    machine.succeed("ip route del 192.0.2.2/32")

    # Simulate the native TUN disappearing on stop using the fixture veth.
    machine.succeed("systemctl stop pangolin-telemetry")
    assert machine.succeed("systemctl show -p ActiveState --value pangolin-telemetry").strip() == "inactive"
    machine.succeed("ip link del pgtel0")
    machine.succeed("systemctl is-active collector")
    assert machine.succeed("systemctl show -p MainPID --value collector").strip() == pid
    machine.succeed(fetch("http://127.0.0.1:19100/"))
    machine.succeed(fetch("http://192.0.2.2:9101"))
    denied("http://100.96.0.2:9100")
    denied("http://203.0.113.9:9100")
    machine.fail(probe("/lookup?name=metrics.internal"))
    assert machine.succeed("cat /etc/resolv.conf") == host_resolver
    machine.succeed("getent hosts ordinary.test")
    machine.succeed("nft list table inet unrelated")
    machine.succeed("nft list table inet pangolin_telemetry")
    machine.succeed("systemctl restart collector")
    machine.wait_until_succeeds(probe("/"), timeout=30)
    denied("http://203.0.113.9:9100")
  '';
}
