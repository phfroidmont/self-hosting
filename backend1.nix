{ modulesPath, pkgs, lib, config, ... }:
let
  fqdn =
    let
      join = hostName: domain: hostName + lib.optionalString (domain != null) ".${domain}";
    in join "matrix" config.networking.domain;
in {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/sda";
  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

  # Set NIX_PATH to be the same as the Terraform module
  # nix.nixPath = [ "nixpkgs=${pkgs}" ];

  boot.cleanTmpDir = true;

  networking.hostName = "backend1";
  networking.domain = "banditlair.com";
  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
  networking.firewall.allowedUDPPorts = [ 64738 ];

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keyFiles = [
     ./ssh_keys/phfroidmont-desktop.pub
  ];

  security.acme.email = "letsencrypt.account@banditlair.com";
  security.acme.acceptTerms = true;

  services.nginx = {
    enable = true;
    # only recommendedProxySettings and recommendedGzipSettings are strictly required,
    # but the rest make sense as well
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    virtualHosts = {
      # This host section can be placed on a different host than the rest,
      # i.e. to delegate from the host being accessible as ${config.networking.domain}
      # to another host actually running the Matrix homeserver.
      "${config.networking.domain}" = {
        enableACME = true;
        forceSSL = true;

        locations."= /.well-known/matrix/server".extraConfig =
          let
            # use 443 instead of the default 8448 port to unite
            # the client-server and server-server port for simplicity
            server = { "m.server" = "${fqdn}:443"; };
          in ''
            add_header Content-Type application/json;
            return 200 '${builtins.toJSON server}';
          '';
        locations."= /.well-known/matrix/client".extraConfig =
          let
            client = {
              "m.homeserver" =  { "base_url" = "https://${fqdn}"; };
              "m.identity_server" =  { "base_url" = "https://vector.im"; };
            };
          # ACAO required to allow element-web on any URL to request this json file
          in ''
            add_header Content-Type application/json;
            add_header Access-Control-Allow-Origin *;
            return 200 '${builtins.toJSON client}';
          '';
      };

      # Reverse proxy for Matrix client-server and server-server communication
      ${fqdn} = {
        enableACME = true;
        forceSSL = true;

        # Or do a redirect instead of the 404, or whatever is appropriate for you.
        # But do not put a Matrix Web client here! See the Element web section below.
        locations."/".extraConfig = ''
          return 404;
        '';

        # forward all Matrix API calls to the synapse Matrix homeserver
        locations."/_matrix" = {
          proxyPass = "http://[::1]:8008"; # without a trailing /
        };
      };
    };
  };

  services.matrix-synapse = {
    enable = true;
    server_name = config.networking.domain;
    listeners = [
      {
        port = 8008;
        bind_address = "::1";
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [
          {
            names = [ "client" "federation" ];
            compress = false;
          }
        ];
      }
    ];
    database_type = "psycopg2";
    database_args = {
      host = "fake"; # This section is overriden in deploy_nixos keys
    };
    extraConfigFiles = [ "/var/keys/synapse-extra-config.yaml" ];
  };
  users.users.matrix-synapse.extraGroups = [ "keys" ];

  services.murmur = {
    enable = true;
    bandwidth = 128000;
    password = "$MURMURD_PASSWORD";
    environmentFile = "/var/keys/murmur.env";
  };

  users.users.murmur.extraGroups = [ "keys" ];
}
