{ pkgs, lib, config, ... }:
{

  sops.secrets = {
    pgPassFile = {
      owner = "nginx";
      key = "roundcube/pg_pass_file";
    };
    dbPassword = {
      owner = "nginx";
      key = "roundcube/db_password";
    };
  };

  services.roundcube = {
    enable = true;
    plugins = [ "managesieve" ];
    dicts = with pkgs.aspellDicts; [ en fr de ];
    hostName = "webmail.banditlair.com";
    database = {
      host = "10.0.1.11";
      username = "roundcube";
      dbname = "roundcube";
      passwordFile = config.sops.secrets.pgPassFile.path;
    };


    extraConfig = ''
      # This override is required as a workaround for the nixpkgs config because we need a plain password instead of a pgpass file
      $password = file_get_contents('${config.sops.secrets.dbPassword.path}');
      $config['db_dsnw'] = 'pgsql://roundcube:' . $password . '@10.0.1.11/roundcube';

      $config['default_host'] = 'ssl://mail.banditlair.com:993';
      $config['smtp_server'] = 'ssl://%h';
      $config['smtp_user'] = '%u';
      $config['smtp_pass'] = '%p';
      $config['identities_level'] = 0;
      $config['managesieve_host'] = 'tls://%h';
      $config['managesieve_auth_type'] = 'PLAIN';
    '';
  };
}
