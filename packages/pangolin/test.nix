{ pkgs ? import <nixpkgs> { } }:

let
  pangolinPackage = pkgs.callPackage ./. { };
in
pkgs.testers.runNixOSTest {
  name = "pangolin-native";

  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [ ../../modules/pangolin.nix ];

    custom.services.pangolin = {
      enable = true;
      environmentFile = "/run/pangolin/environment";
    };

    environment.systemPackages = [ pkgs.curl ];

    systemd.services.pangolin-test-environment = {
      description = "Create Pangolin's test-only environment file";
      before = [
        "pangolin.service"
        "gerbil.service"
      ];
      requiredBy = [
        "pangolin.service"
        "gerbil.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "pangolin";
        RuntimeDirectoryMode = "0700";
      };
      script = ''
        printf '%s\n' 'SERVER_SECRET=nixos-vm-test-only' > /run/pangolin/environment
        chmod 0600 /run/pangolin/environment
      '';
    };

    # The test has no external network from which Traefik could fetch Badger.
    systemd.services = {
      gerbil.upholds = lib.mkForce [ ];
      traefik.wantedBy = lib.mkForce [ ];
    };

    virtualisation.memorySize = 3072;

    assertions = [
      {
        assertion = builtins.attrNames config.services.traefik.dynamicConfigOptions.http.routers == [
          "api-router"
          "main-app-router-redirect"
          "next-router"
        ];
        message = "Pangolin must expose only its dashboard routers";
      }
      {
        assertion = config.services.pangolin.settings.flags.enable_acme_cert_sync;
        message = "Pangolin's ACME certificate sync flag must be enabled";
      }
      {
        assertion = config.services.pangolin.settings.acme.acme_json_path == "/var/lib/pangolin/config/acme-sync/acme.json";
        message = "Pangolin must read certificates from its private ACME copy";
      }
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("pangolin.service")
    machine.wait_until_succeeds(
        "curl --fail --silent http://127.0.0.1:3001/api/v1/ | grep -q Healthy",
        timeout=180,
    )
    machine.succeed("grep -q 'disable_signup_without_invite: true' /var/lib/pangolin/config/config.yml")
    machine.succeed("grep -q 'disable_user_create_org: true' /var/lib/pangolin/config/config.yml")
    machine.succeed("grep -q 'enable_acme_cert_sync: true' /var/lib/pangolin/config/config.yml")
    machine.succeed("grep -q 'acme_json_path: /var/lib/pangolin/config/acme-sync/acme.json' /var/lib/pangolin/config/config.yml")
    machine.succeed("systemctl is-enabled pangolin-acme-cert-sync.timer")

    # Before Traefik's first issuance, a missing source is a successful no-op.
    machine.succeed("rm -f /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.succeed("systemctl start pangolin-acme-cert-sync.service")
    machine.succeed("test ! -e /var/lib/pangolin/config/acme-sync/acme.json")

    machine.succeed("install -d -m 0700 -o traefik -g traefik /var/lib/pangolin/config/letsencrypt")
    machine.succeed("${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=test.example -keyout /tmp/test.key -out /tmp/test.crt >/dev/null 2>&1")
    machine.succeed("${pkgs.jq}/bin/jq -n --arg certificate \"$(base64 -w0 /tmp/test.crt)\" --arg key \"$(base64 -w0 /tmp/test.key)\" '{letsencrypt:{Account:{},Certificates:[{domain:{main:\"test.example\"},certificate:$certificate,key:$key}]}}' > /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.succeed("chown traefik:traefik /var/lib/pangolin/config/letsencrypt/acme.json && chmod 0600 /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.succeed("systemctl start pangolin-acme-cert-sync.service")
    machine.succeed("cmp /var/lib/pangolin/config/letsencrypt/acme.json /var/lib/pangolin/config/acme-sync/acme.json")
    machine.succeed("test $(stat -c %a /var/lib/pangolin/config/letsencrypt) = 700")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/pangolin/config/letsencrypt/acme.json) = traefik:traefik:600")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/pangolin/config/acme-sync) = pangolin:fossorial:700")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/pangolin/config/acme-sync/acme.json) = pangolin:fossorial:600")
    machine.fail("runuser -u pangolin -- test -r /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.succeed("runuser -u pangolin -- test -r /var/lib/pangolin/config/acme-sync/acme.json")
    machine.succeed("stat -c %i /var/lib/pangolin/config/acme-sync/acme.json > /tmp/acme-inode")
    machine.succeed("systemctl start pangolin-acme-cert-sync.service")
    machine.succeed("test $(cat /tmp/acme-inode) = $(stat -c %i /var/lib/pangolin/config/acme-sync/acme.json)")

    machine.succeed("cp /var/lib/pangolin/config/acme-sync/acme.json /tmp/last-good-acme.json")
    machine.succeed("rm /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.fail("systemctl start pangolin-acme-cert-sync.service")
    machine.succeed("cmp /tmp/last-good-acme.json /var/lib/pangolin/config/acme-sync/acme.json")

    machine.succeed("printf '%s\\n' 'not valid json' > /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.succeed("chown traefik:traefik /var/lib/pangolin/config/letsencrypt/acme.json && chmod 0600 /var/lib/pangolin/config/letsencrypt/acme.json")
    machine.fail("systemctl start pangolin-acme-cert-sync.service")
    machine.succeed("cmp /tmp/last-good-acme.json /var/lib/pangolin/config/acme-sync/acme.json")
    machine.succeed("test $(stat -c %U:%G:%a /var/lib/pangolin/config/letsencrypt/acme.json) = traefik:traefik:600")

    machine.succeed("grep -q nodejs-22 ${pangolinPackage}/share/pangolin/dist/server.mjs")
    machine.wait_for_unit("gerbil.service")
    machine.succeed("systemctl cat gerbil.service | grep -q gerbil-1.5.1")
    machine.succeed("test $(readlink /var/lib/pangolin/.next/.nix-package) = ${pangolinPackage}")
    machine.succeed("ln -sfn /nix/store/previous-pangolin-build /var/lib/pangolin/.next/.nix-package")
    machine.succeed("systemctl restart pangolin.service")
    machine.wait_until_succeeds(
        "curl --fail --silent http://127.0.0.1:3001/api/v1/ | grep -q Healthy",
        timeout=180,
    )
    machine.wait_for_unit("gerbil.service")
    machine.succeed("test $(readlink /var/lib/pangolin/.next/.nix-package) = ${pangolinPackage}")
  '';
}
