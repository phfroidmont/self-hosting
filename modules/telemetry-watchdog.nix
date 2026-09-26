{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.telemetryWatchdog;
  sender = cfg.mode == "sender";
  guard = pkgs.writeShellScript "telemetry-watchdog-proxy-guard" ''
    set -eu
    uid=$(${pkgs.coreutils}/bin/id -u nginx)
    test "$uid" -gt 0
    ${pkgs.nftables}/bin/nft -f - <<EOF
    add table inet telemetry_watchdog_proxy
    flush table inet telemetry_watchdog_proxy
    table inet telemetry_watchdog_proxy {
      chain output {
        type filter hook output priority 10; policy accept;
        meta skuid $uid ip daddr ${cfg.utilitySubnet} oifname != "pgtel0" counter reject with icmpx type admin-prohibited
      }
    }
    EOF
  '';
  receiver = pkgs.writeText "telemetry-watchdog-receiver.py" (builtins.readFile ../packages/telemetry-watchdog/receiver.py);
  stateDir = "/var/lib/telemetry-watchdog";
  # A missing heartbeat must alarm even on a fresh installation. Monit checks
  # this directory immediately after its own short startup grace.
  monitConfig = ''
    set daemon 30
      with start delay 90
    set ssl {
      verify : enable,
    }
    set eventqueue
      basedir /var/lib/telemetry-watchdog-monit/queue
      slots 1000
    include ${config.sops.secrets.telemetryWatchdogMonitConfig.path}
    check file telemetry-watchdog-heartbeat with path ${stateDir}/heartbeat.json
      if does not exist then alert
      if mtime > 5 minutes then alert
  '';
in
{
  options.custom.services.telemetryWatchdog = {
    enable = lib.mkEnableOption "private central telemetry watchdog";
    mode = lib.mkOption { type = lib.types.enum [ "sender" "receiver" ]; description = "Host role in the private watchdog path."; };
    secretsFile = lib.mkOption { type = lib.types.path; description = "Host SOPS ciphertext containing watchdog/token and, on the receiver, watchdog/monit_config."; };
    utilitySubnet = lib.mkOption { type = lib.types.str; default = ""; description = "Verified public enrollment utility IPv4 CIDR for the sender."; };
    dnsAddress = lib.mkOption { type = lib.types.str; default = ""; description = "Verified public enrollment Olm DNS IPv4 address for the sender."; };
    collectorNiceId = lib.mkOption { type = lib.types.str; default = ""; description = "Verified public enrollment hel1 machine niceId for the receiver."; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        { assertion = !sender || (builtins.match "[0-9./]+" cfg.utilitySubnet != null && builtins.match "[0-9.]+" cfg.dnsAddress != null && cfg.utilitySubnet != "" && cfg.dnsAddress != ""); message = "telemetry-watchdog: sender requires verified IPv4 utilitySubnet and dnsAddress."; }
        { assertion = sender || cfg.collectorNiceId != ""; message = "telemetry-watchdog: receiver requires enrolled collectorNiceId."; }
        { assertion = !sender || !(config.networking.nftables.enable && config.networking.nftables.flushRuleset); message = "telemetry-watchdog: whole nftables ruleset flush removes the persistent proxy guard."; }
      ];
      sops.secrets.telemetryWatchdogToken = {
        sopsFile = cfg.secretsFile;
        key = "watchdog/token";
        owner = if sender then "grafana" else "telemetry-watchdog";
        restartUnits = if sender then [ "grafana.service" ] else [ "telemetry-watchdog.service" ];
      };
    }
    (lib.mkIf sender {
      assertions = [
        { assertion = config.services.nginx.user == "nginx"; message = "telemetry-watchdog: nginx worker must run under the dedicated static nginx UID."; }
      ];
      systemd.services.telemetry-watchdog-proxy-guard = {
        description = "Persistent nginx UID guard for private watchdog destination";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-sysusers.service" ];
        before = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = guard;
          ExecReload = guard;
          # Never remove the table on stop; the guard survives service restarts.
        };
      };
      systemd.services.nginx = {
        wants = [ "telemetry-watchdog-proxy-guard.service" ];
        after = [ "telemetry-watchdog-proxy-guard.service" ];
        serviceConfig.ExecStartPre = lib.mkBefore [ "+${guard}" ];
      };
      services.nginx = {
        enable = true;
        appendHttpConfig = ''
          limit_req_zone $server_name zone=watchdog_requests:1m rate=2r/s;
          limit_conn_zone $server_name zone=watchdog_connections:1m;
        '';
        virtualHosts."telemetry-watchdog.local" = {
          listen = [{ addr = "127.0.0.1"; port = 3103; ssl = false; }];
          extraConfig = ''
            client_max_body_size 32k;
            client_body_timeout 5s;
            client_header_timeout 5s;
            send_timeout 5s;
            keepalive_timeout 5s;
            limit_req zone=watchdog_requests burst=4 nodelay;
            limit_req_status 429;
            limit_conn watchdog_connections 4;
            limit_conn_status 429;
          '';
          locations."= /watchdog".extraConfig = ''
            if ($request_method != POST) { return 405; }
            if ($request_uri != "/watchdog") { return 404; }
            resolver ${cfg.dnsAddress} ipv6=off valid=30s;
            resolver_timeout 5s;
            set $watchdog_upstream watchdog.bl.internal:19095;
            proxy_pass http://$watchdog_upstream;
            proxy_set_header Authorization $http_authorization;
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
          '';
          locations."/".extraConfig = "return 404;";
        };
      };
    })
    (lib.mkIf (!sender) {
      users.groups.telemetry-watchdog = { };
      users.users.telemetry-watchdog = { isSystemUser = true; group = "telemetry-watchdog"; };
      sops.secrets.telemetryWatchdogMonitConfig = {
        sopsFile = cfg.secretsFile;
        key = "watchdog/monit_config";
        owner = "root";
        restartUnits = [ "monit.service" ];
      };
      services.newt.blueprint.private-resources.telemetry-watchdog = {
        name = "Telemetry watchdog";
        mode = "host";
        destination = "127.0.0.1";
        alias = "watchdog.bl.internal";
        tcp-ports = "19095";
        udp-ports = "";
        disable-icmp = true;
        roles = [ ];
        users = [ ];
        machines = [ cfg.collectorNiceId ];
      };
      systemd.services.telemetry-watchdog = {
        description = "Private authenticated telemetry watchdog receiver";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "telemetry-watchdog";
          Group = "telemetry-watchdog";
          StateDirectory = "telemetry-watchdog";
          StateDirectoryMode = "0700";
          LoadCredential = [ "token:${config.sops.secrets.telemetryWatchdogToken.path}" ];
          ExecStart = "${pkgs.python3}/bin/python3 ${receiver} --token-file %d/token --state-dir ${stateDir}";
          Restart = "always";
          RestartSec = 5;
          UMask = "0077";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
      services.monit.enable = true;
      services.monit.config = monitConfig;
      systemd.services.monit.serviceConfig.StateDirectory = [ "telemetry-watchdog-monit" "telemetry-watchdog-monit/queue" ];
      systemd.services.monit.serviceConfig.StateDirectoryMode = "0700";
    })
  ]);
}
