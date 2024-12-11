{ config, lib, ... }:
let
  cfg = config.custom.services.monitoring-exporters;
in
{
  options.custom.services.monitoring-exporters = {
    enable = lib.mkEnableOption "monitoring-exporters";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "systemd"
            "processes"
          ];
        };
        dmarc = {
          enable = true;
          debug = true;
          imap = {
            host = "mail.banditlair.com";
            username = "paultrial@banditlair.com";
            passwordFile = "/run/credentials/prometheus-dmarc-exporter.service/password";
          };
          folders = {
            inbox = "dmarc_reports";
            done = "Archives.dmarc_report_processed";
            error = "Archives.dmarc_report_error";
          };
        };
      };
    };

    systemd.services.prometheus-dmarc-exporter.serviceConfig.LoadCredential = "password:${config.sops.secrets.dmarcExporterPassword.path}";

    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 3101;
          grpc_listen_port = 0;
        };
        clients = [ { url = "http://127.0.0.1:3100/loki/api/v1/push"; } ];
        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = "${config.networking.hostName}";
              };
            };
            relabel_configs = [
              {
                source_labels = [ "__journal__systemd_unit" ];
                target_label = "unit";
              }
            ];
          }
          (lib.mkIf config.services.nginx.enable {
            job_name = "nginx";
            static_configs = [
              {
                targets = [ "localhost" ];
                labels = {
                  job = "nginx";
                  host = "${config.networking.hostName}";
                  __path__ = "/var/log/nginx/*.log";
                };
              }
            ];
          })
        ];
      };
    };

    systemd.services.promtail.serviceConfig = {
      ReadOnlyPaths = lib.mkIf config.services.nginx.enable "/var/log/nginx";
      SupplementaryGroups = lib.mkIf config.services.nginx.enable [ "nginx" ];
    };
  };
}
