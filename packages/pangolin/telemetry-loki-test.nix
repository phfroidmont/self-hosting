{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.runNixOSTest {
  name = "telemetry-loki";

  nodes.loki = { config, lib, pkgs, ... }: {
    imports = [ ../../modules/grafana.nix ];

    # Keep the production Loki configuration, but avoid unrelated services,
    # secrets and the retention-only source patch in this networking test.
    options.sops.secrets = lib.mkOption { type = lib.types.attrs; };
    config = {
      sops.secrets = lib.mkForce { };
      custom.services.grafana.enable = true;
      services.grafana.enable = lib.mkForce false;
      services.prometheus.enable = lib.mkForce false;
      services.nginx.enable = lib.mkForce false;
      services.loki.package = lib.mkForce pkgs.grafana-loki;
      networking.firewall.enable = false;
      environment.systemPackages = [ pkgs.curl pkgs.iproute2 ];

      assertions = [{
        assertion = !(builtins.any (port: builtins.elem port config.networking.firewall.allowedTCPPorts) [ 3100 9095 ]);
        message = "Loki must not open HTTP or gRPC firewall ports.";
      }];
    };
  };

  nodes.client = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = ''
    import json
    import shlex

    start_all()
    loki.wait_for_unit("loki.service")
    loki.wait_for_open_port(3100, "127.0.0.1")
    loki.wait_until_succeeds("curl --fail --silent --max-time 2 http://127.0.0.1:3100/ready")

    with subtest("HTTP and gRPC remain loopback-only on a networked VM"):
        for port in (3100, 9095):
            listeners = loki.succeed(f"ss -H -ltn 'sport = :{port}'").splitlines()
            assert len(listeners) == 1, listeners
            assert listeners[0].split()[3] == f"127.0.0.1:{port}", listeners
            client.fail(f"curl --fail --max-time 2 http://loki:{port}/ready")

    timestamp = int(loki.succeed("date +%s%N").strip())
    fixture = "loki-loopback-callback-fixture"
    payload = json.dumps({"streams": [{"stream": {"job": fixture}, "values": [[str(timestamp), fixture]]}]})

    with subtest("a successful push is actually queryable via the scheduler callback"):
        status = loki.succeed(
            "curl --silent --show-error --max-time 8 --output /dev/null --write-out '%{http_code}' "
            "--header 'Content-Type: application/json' --data-binary " + shlex.quote(payload) +
            " http://127.0.0.1:3100/loki/api/v1/push"
        ).strip()
        assert status == "204", status

        # /ready and push both pass when the scheduler advertises the VM's
        # non-loopback IP while its gRPC socket only listens on loopback.
        url = "http://127.0.0.1:3100/loki/api/v1/query"
        response = loki.succeed(
            "curl --fail --silent --show-error --max-time 8 --get " + shlex.quote(url) +
            " --data-urlencode " + shlex.quote('query=count_over_time({job="' + fixture + '"}[1m])') +
            " --data-urlencode " + shlex.quote("time=" + str(timestamp + 1000000000))
        )
        result = json.loads(response)
        assert result["status"] == "success", result
        assert any(float(item["value"][1]) == 1 for item in result["data"]["result"]), result
  '';
}
