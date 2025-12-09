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
      dataDir = "/nix/var/data/minecraft";
    };

    services.bluemap = {
      enable = true;
      eula = true;
      defaultWorld = "${config.services.minecraft-server.dataDir}/world";
      host = "mcmap.${config.networking.domain}";
      enableNginx = true;
      enableRender = true;
    };

    services.nginx.virtualHosts."mcmap.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
    };
  };
}
