{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  cfg = config.custom.services.minecraft-server;
in
{
  options.custom.services.minecraft-server = {
    enable = lib.mkEnableOption "minecraft server";
  };

  config = lib.mkIf cfg.enable {
    services.minecraft-server = {
      enable = true;
      package = pkgs-unstable.minecraft-server;
      eula = true;
      openFirewall = true;
      declarative = true;
      serverProperties = {
        enable-rcon = true;
        "rcon.port" = 25575;
        "rcon.password" = "password";
        server-port = 23363;
        online-mode = true;
        force-gamemode = true;
        white-list = true;
        diffuculty = "hard";
      };
      whitelist = {
        paulplay15 = "1d5abc95-2fdb-4dcb-98e8-4fb5a0fba953";
        Xavier1258 = "e9059cf3-00ef-47a3-92ee-4e4a3fea0e6d";
        denisjulien3333 = "3c93e1a2-42d8-4a51-9fe3-924c8e8d5b07";
      };
    };

    services.bluemap = {
      enable = true;
      eula = true;
      defaultWorld = "${config.services.minecraft-server.dataDir}/world";
      host = "mcmap.${config.networking.domain}";
      enableNginx = true;
      enableRender = true;
      coreSettings = {
        render-thread-count = -4;
      };
      maps = {
        "overworld" = {
          world = config.services.bluemap.defaultWorld;
          ambient-light = 0.1;
          cave-detection-ocean-floor = -5;
        };

        "nether" = {
          world = "${config.services.bluemap.defaultWorld}/DIM-1";
          sorting = 100;
          sky-color = "#290000";
          void-color = "#150000";
          ambient-light = 0.6;
          world-sky-light = 0;
          remove-caves-below-y = -10000;
          cave-detection-ocean-floor = -5;
          cave-detection-uses-block-light = true;
          # render-mask = [
          #   { max-y = 90; }
          # ];

        };

        "end" = {
          world = "${config.services.bluemap.defaultWorld}/DIM1";
          sorting = 200;
          sky-color = "#080010";
          void-color = "#080010";
          ambient-light = 0.6;
          world-sky-light = 0;
          remove-caves-below-y = -10000;
          cave-detection-ocean-floor = -5;
        };
      };
    };

    services.nginx.virtualHosts."mcmap.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
    };
  };
}
