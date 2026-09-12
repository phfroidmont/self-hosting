{ config, lib, ... }:
let cfg = config.custom.services.monero;
in {
  options.custom.services.monero = { enable = lib.mkEnableOption "monero"; };

  config = lib.mkIf cfg.enable {
    services.monero = {
      enable = true;
      rpc.restricted = true;
    };
  };
}
