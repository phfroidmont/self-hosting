{ config
, lib
, pkgs
, pkgs-unstable
, ...
}:
let
  cfg = config.custom.services.reticulum;
  user = "reticulum";
  stateDir = "/nix/var/data/reticulum";
  port = 4242;

  # Public entrypoint settings follow the "Hosting Public Entrypoints" section
  # of the Reticulum manual. The bootstrap links are only used until enough
  # discovered transport nodes are connected.
  rnsConfig = pkgs.writeText "reticulum-config" ''
    [reticulum]
      enable_transport = yes
      discover_interfaces = yes
      autoconnect_discovered_interfaces = 3

    [logging]
      loglevel = 4

    [interfaces]
      [[Public Entrypoint]]
        type = BackboneInterface
        enabled = yes
        mode = gateway
        listen_on = 0.0.0.0
        port = ${toString port}
        announce_rate_target = 3600
        announce_rate_penalty = 3600
        announce_rate_grace = 6

      [[Bootstrap One-Big-Network]]
        type = BackboneInterface
        enabled = yes
        remote = rns.one-big.network
        target_port = 4242
        bootstrap_only = yes

      [[Bootstrap AT-Vienna-Backbone]]
        type = BackboneInterface
        enabled = yes
        remote = rns.radical.computer
        target_port = 4242
        bootstrap_only = yes

      [[Bootstrap zer0bitz]]
        type = BackboneInterface
        enabled = yes
        remote = zer0bitz.ddns.net
        target_port = 4242
        bootstrap_only = yes
  '';

  # lxmd neither announces nor re-announces the propagation node unless asked.
  lxmdConfig = pkgs.writeText "lxmd-config" ''
    [propagation]
      enable_node = yes
      node_name = ${config.networking.domain}
      announce_at_start = yes
      announce_interval = 360

    [logging]
      loglevel = 4
  '';
in
{
  options.custom.services.reticulum = {
    enable = lib.mkEnableOption "Reticulum transport and LXMF propagation node";
  };

  config = lib.mkIf cfg.enable {
    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = stateDir;
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0700 ${user} ${user} - -"
    ];

    environment.systemPackages = [
      pkgs-unstable.rns
      pkgs-unstable.lxmf
    ];

    # lxmd hosts the shared Reticulum instance itself, so a single process
    # provides both the transport node and the propagation node.
    systemd.services.lxmd = {
      description = "Reticulum transport and LXMF propagation node";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment.PYTHONUNBUFFERED = "1";
      preStart = ''
        install -D -m 0600 ${rnsConfig} ${stateDir}/rns/config
        install -D -m 0600 ${lxmdConfig} ${stateDir}/lxmd/config
      '';
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = user;
        ExecStart = "${lib.getExe pkgs-unstable.lxmf} --config ${stateDir}/lxmd --rnsconfig ${stateDir}/rns";
        Restart = "on-failure";
        RestartSec = "10s";
        ReadWritePaths = [ stateDir ];
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };

    networking.firewall.allowedTCPPorts = [ port ];
  };
}
