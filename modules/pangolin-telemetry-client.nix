{ config, lib, pkgs, ... }:

let
  cfg = config.services.pangolin-telemetry;
  olm = pkgs.callPackage ../packages/pangolin/olm.nix { };
  consumer = config.systemd.services.${cfg.consumerUnit};
  user = config.users.users.${cfg.consumerUser} or null;
  ipv4 = address:
    builtins.match "(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}" address != null
    && lib.all (part: lib.toInt part <= 255) (lib.splitString "." address);
  ipNumber = address: lib.foldl' (n: part: n * 256 + lib.toInt part) 0 (lib.splitString "." address);
  subnet = lib.splitString "/" cfg.utilitySubnet;
  validSubnet = builtins.length subnet == 2 && ipv4 (builtins.head subnet)
    && builtins.match "([1-9]|[12][0-9]|30)" (builtins.elemAt subnet 1) != null;
  subnetBase = ipNumber (builtins.head subnet);
  subnetSize = lib.foldl' (n: _: n * 2) 1 (lib.range 1 (32 - lib.toInt (builtins.elemAt subnet 1)));
  validInterface = name: builtins.match "[a-zA-Z0-9_.-]{1,15}" name != null;

  resolver = pkgs.writeText "pangolin-telemetry-resolv.conf" ''
    nameserver ${cfg.dnsAddress}
    options timeout:1 attempts:1
  '';

  # add + flush + replacement are one nft transaction: no unguarded interval,
  # including reloads. Never flush another table or remove this table on stop.
  # Match the UID positively: socketless kernel traffic (e.g. IPv6 neighbor
  # discovery) must not fall through into the consumer's reject rule.
  guard = pkgs.writeShellScript "pangolin-telemetry-guard" ''
    set -eu
    consumer_uid=$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg cfg.consumerUser})
    test "$consumer_uid" -gt 0
    ${pkgs.nftables}/bin/nft -f - <<EOF
    add table inet pangolin_telemetry
    flush table inet pangolin_telemetry
    table inet pangolin_telemetry {
      chain output {
        type filter hook output priority 10; policy accept;
        meta skuid $consumer_uid jump consumer
      }
      chain consumer {
        oifname "lo" ip daddr 127.0.0.0/8 accept
        oifname "lo" ip6 daddr ::1 accept
        oifname "pgtel0" ip daddr ${cfg.dnsAddress} udp dport 53 accept
        ${lib.optionalString (cfg.allowedTCPPorts != [ ]) ''
        oifname "pgtel0" ip daddr ${cfg.utilitySubnet} tcp dport { ${lib.concatMapStringsSep ", " toString cfg.allowedTCPPorts} } accept
        ''}
        ${lib.concatMapStringsSep "\n" (destination: ''
        oifname "${destination.interface}" ip daddr ${destination.address} tcp dport ${toString destination.port} accept
        '') cfg.legacyDestinations}
        counter reject with icmpx type admin-prohibited
      }
    }
    EOF
    printf 'Installed Pangolin telemetry egress guard for UID %s\n' "$consumer_uid"
  '';
in
{
  options.services.pangolin-telemetry = {
    enable = lib.mkEnableOption "native, fail-closed Pangolin telemetry transport";
    credentialsFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime path to a JSON object containing only nonempty id and secret strings. Never put credentials in the Nix store.";
    };
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://pangolin.banditlair.com";
      description = "Pangolin control-plane URL.";
    };
    utilitySubnet = lib.mkOption {
      type = lib.types.str;
      description = "Explicit, verified organization utility IPv4 network in canonical CIDR notation.";
    };
    dnsAddress = lib.mkOption {
      type = lib.types.str;
      description = "Explicit, verified organization utility network base + 1 (Olm's embedded DNS).";
    };
    consumerUnit = lib.mkOption {
      type = lib.types.str;
      example = "prometheus";
      description = "Existing collector service name, without .service.";
    };
    consumerUser = lib.mkOption {
      type = lib.types.str;
      description = "Declared static, non-root user exclusively used by the collector; all traffic from this UID is guarded.";
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      description = "TCP destination ports permitted in utilitySubnet through pgtel0 only.";
    };
    legacyDestinations = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          address = lib.mkOption { type = lib.types.str; description = "Exact legacy IPv4 destination."; };
          port = lib.mkOption { type = lib.types.port; description = "Exact legacy TCP destination port."; };
          interface = lib.mkOption { type = lib.types.str; description = "Required output interface for this legacy destination."; };
        };
      });
      default = [ ];
      description = "Temporary, exact legacy TCP exceptions; no hostname or wildcard destinations.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = validSubnet && ipv4 cfg.dnsAddress
          && builtins.bitAnd subnetBase (4294967296 - subnetSize) == subnetBase
          && ipNumber cfg.dnsAddress == subnetBase + 1;
        message = "pangolin-telemetry: utilitySubnet must be a canonical IPv4 CIDR (/1../30), and dnsAddress must be its base + 1; verify both against the organization configuration.";
      }
      {
        assertion = user != null && (user.uid != null || user.isSystemUser || user.isNormalUser)
          && cfg.consumerUser != "root" && user.uid != 0
          && (consumer.serviceConfig.DynamicUser or false) == false
          && (consumer.serviceConfig.PrivateNetwork or false) == false;
        message = "pangolin-telemetry: declare consumerUser as a static non-root NixOS user; the consumer must not use DynamicUser or PrivateNetwork.";
      }
      {
        assertion = builtins.match "[a-zA-Z0-9_@.-]+" cfg.consumerUnit != null
          && !lib.hasSuffix ".service" cfg.consumerUnit
          && lib.all (d: ipv4 d.address && validInterface d.interface) cfg.legacyDestinations;
        message = "pangolin-telemetry: invalid consumerUnit or legacy destination IPv4/interface.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.credentialsFile && !lib.hasPrefix "/nix/store/" cfg.credentialsFile;
        message = "pangolin-telemetry: credentialsFile must be an absolute runtime path outside the Nix store.";
      }
      {
        # Check the final value: NixOS also defaults this to true for raw
        # rulesets and older state versions. The guard owns a separate table.
        assertion = !(config.networking.nftables.enable && config.networking.nftables.flushRuleset);
        message = "pangolin-telemetry: networking.nftables.flushRuleset must be false when nftables is enabled; whole-ruleset flushes remove the persistent egress guard.";
      }
    ];

    systemd.services.pangolin-telemetry = {
      description = "Native Pangolin telemetry tunnel";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.iproute2 ];
      environment.CONFIG_FILE = "/run/pangolin-telemetry/config.json";
      startLimitIntervalSec = 0;
      preStart = ''
        ${pkgs.coreutils}/bin/install -m 0600 "$CREDENTIALS_DIRECTORY/credentials" "$CONFIG_FILE"
        if ! ${pkgs.jq}/bin/jq -e 'type == "object" and keys == ["id", "secret"] and (.id | type == "string" and length > 0) and (.secret | type == "string" and length > 0)' "$CONFIG_FILE" >/dev/null 2>&1; then
          printf 'Invalid Pangolin telemetry credentials: expected nonempty id and secret strings\n' >&2
          exit 1
        fi
      '';
      serviceConfig = {
        Type = "simple";
        User = "root";
        UMask = "0077";
        LoadCredential = [ "credentials:${cfg.credentialsFile}" ];
        RuntimeDirectory = [ "pangolin-telemetry" "pangolin-telemetry/wireguard" ];
        RuntimeDirectoryMode = "0700";
        # Hide, rather than chmod/chown, any shared host /run/wireguard directory.
        BindPaths = [ "/run/pangolin-telemetry/wireguard:/run/wireguard" ];
        ExecStart = lib.escapeShellArgs [
          "${olm}/bin/olm"
          "--endpoint=${cfg.endpoint}"
          "--interface=pgtel0"
          # JSON false is ignored by Olm 1.8.2's config merger.
          "--override-dns=false"
          "--upstream-dns=127.0.0.1:9"
          "--log-level=INFO"
          "--enable-api=true"
          "--http-addr="
          "--socket-path=/run/pangolin-telemetry/api.sock"
        ];
        Restart = "always";
        RestartSec = 5;
        TimeoutStopSec = 20;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      };
    };

    systemd.services.pangolin-telemetry-guard = {
      description = "Persistent Pangolin telemetry UID egress guard";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-sysusers.service" ];
      before = [ "${cfg.consumerUnit}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = guard;
        ExecReload = guard;
        TimeoutStartSec = 15;
        # Deliberately no ExecStop: stopping either service must not open egress.
      };
    };

    systemd.services.${cfg.consumerUnit} = {
      wants = [ "pangolin-telemetry.service" "pangolin-telemetry-guard.service" ];
      after = [ "pangolin-telemetry-guard.service" ];
      environment.GODEBUG = lib.mkForce "netdns=go";
      serviceConfig = {
        User = cfg.consumerUser;
        BindReadOnlyPaths = [ "${resolver}:/etc/resolv.conf" ];
        # Also install before each collector start. Wants alone must not allow
        # startup if the guard failed, nor should stopping it stop collection.
        ExecStartPre = lib.mkBefore [ "+${guard}" ];
        UnsetEnvironment = [
          "HTTP_PROXY"
          "HTTPS_PROXY"
          "ALL_PROXY"
          "FTP_PROXY"
          "NO_PROXY"
          "http_proxy"
          "https_proxy"
          "all_proxy"
          "ftp_proxy"
          "no_proxy"
        ];
      };
    };
  };
}
