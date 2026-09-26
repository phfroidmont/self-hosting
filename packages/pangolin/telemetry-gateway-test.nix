{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.runNixOSTest {
  name = "telemetry-gateway";

  nodes.gateway = { config, lib, pkgs, ... }: {
    imports = [
      ../../modules/grafana.nix
      ../../modules/nginx.nix
    ];

    # Exercise the real gateway and inherited public rate limits without
    # building hel1, provisioning secrets, or running the monitoring stack.
    options.sops.secrets = lib.mkOption { type = lib.types.attrs; };
    config = {
      sops.secrets = lib.mkForce { };
      custom.services.grafana.enable = true;
      custom.services.nginx.enable = true;
      services.grafana.enable = lib.mkForce false;
      services.prometheus.enable = lib.mkForce false;
      services.loki.enable = lib.mkForce false;

      # Disabling the test firewall proves isolation comes from binding, not
      # from a firewall that happens to hide a wildcard listener.
      networking.firewall.enable = false;
      environment.systemPackages = [ pkgs.curl ];
      services.nginx.virtualHosts."public.test" = {
        listen = [{ addr = "0.0.0.0"; port = 8080; }];
        locations."/".extraConfig = "return 418;";
      };

      systemd.services.stub-loki = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          StateDirectory = "stub-loki";
          ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "stub-loki.py" ''
            from http.server import BaseHTTPRequestHandler, HTTPServer
            import json

            class Handler(BaseHTTPRequestHandler):
                def record(self):
                    body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    with open("/var/lib/stub-loki/requests", "a") as requests:
                        requests.write(json.dumps({
                            "method": self.command,
                            "path": self.path,
                            "body": body.decode(),
                        }) + "\n")
                    self.send_response(204)
                    self.end_headers()

                do_POST = record
                do_GET = record
                do_HEAD = record
                do_PUT = record
                do_DELETE = record
                do_OPTIONS = record
                do_PATCH = record

            HTTPServer(("127.0.0.1", 3100), Handler).serve_forever()
          ''}";
        };
      };

      assertions = [
        {
          assertion = !(builtins.any (port: builtins.elem port config.networking.firewall.allowedTCPPorts) [ 3100 3102 9090 ]);
          message = "Telemetry listeners must not open firewall ports.";
        }
        {
          assertion = !config.services.nginx.virtualHosts."telemetry-ingest.local".enableACME;
          message = "The telemetry gateway must not request a public certificate.";
        }
      ];
    };
  };

  nodes.client = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = ''
    import json
    import shlex

    start_all()
    gateway.wait_for_unit("stub-loki.service")
    gateway.wait_for_unit("nginx.service")
    gateway.wait_for_open_port(3102, "127.0.0.1")

    def request(method, path, expected, extra=""):
        result = gateway.succeed(
            "curl --silent --show-error --max-time 10 --path-as-is "
            "--output /dev/null --write-out '%{http_code}' "
            "--header 'Host: telemetry.banditlair.com' "
            + ("--head " if method == "HEAD" else "--request " + method + " ")
            + extra + " " + shlex.quote("http://127.0.0.1:3102" + path)
        )
        assert result == str(expected), (method, path, result)

    with subtest("only the exact Loki push POST reaches the backend"):
        request("POST", "/loki/api/v1/push", 204, "--data-binary 'test-payload'")
        recorded = json.loads(gateway.succeed("cat /var/lib/stub-loki/requests"))
        assert recorded == {"method": "POST", "path": "/loki/api/v1/push", "body": "test-payload"}
        for method in ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "PATCH"]:
            request(method, "/loki/api/v1/push", 405)
        for path in [
            "/", "/metrics", "/ready", "/loki/api/v1/query", "/loki/api/v1/query_range",
            "/api/v1/write", "/api/v1/push", "/loki/api/v1/push/",
            "/loki/api/v1/push?query=1", "/loki//api/v1/push", "/loki/api/v1/%70ush",
        ]:
            request("POST", path, 404)
            request("GET", path, 405 if path in [
                "/loki/api/v1/push?query=1", "/loki//api/v1/push", "/loki/api/v1/%70ush"
            ] else 404)
        gateway.succeed("test $(wc -l < /var/lib/stub-loki/requests) = 1")

    with subtest("request bodies are bounded"):
        gateway.succeed("truncate -s 10485761 /tmp/oversize-body")
        request("POST", "/loki/api/v1/push", 413, "--data-binary @/tmp/oversize-body")
        gateway.succeed("test $(wc -l < /var/lib/stub-loki/requests) = 1")

    with subtest("gateway is loopback-only even with the firewall disabled"):
        listeners = gateway.succeed("ss -H -ltn 'sport = :3102'").splitlines()
        assert len(listeners) == 1, listeners
        assert listeners[0].split()[3] == "127.0.0.1:3102", listeners
        client.fail("curl --fail --max-time 5 http://gateway:3102/loki/api/v1/push")
        client.fail("curl --fail --max-time 5 http://gateway:3100/loki/api/v1/push")
        public_status = client.succeed(
            "curl --silent --show-error --max-time 5 --output /dev/null --write-out '%{http_code}' "
            "--header 'Host: telemetry.banditlair.com' --data 'public-request' "
            "http://gateway:8080/loki/api/v1/push"
        )
        assert public_status == "418", public_status
        gateway.succeed("test $(wc -l < /var/lib/stub-loki/requests) = 1")
  '';
}
