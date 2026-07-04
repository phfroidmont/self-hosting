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

    services.alloy = {
      enable = true;
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "journal" {
        forward_to    = [loki.write.local.receiver]
        max_age       = "12h"
        labels        = {job = "systemd-journal", host = "${config.networking.hostName}"}
        relabel_rules = loki.relabel.journal.rules
      }

      local.file_match "nginx" {
        path_targets = [{"__path__" = "/var/log/nginx/*.log", job = "nginx", host = "${config.networking.hostName}"}]
      }

      loki.source.file "nginx" {
        targets    = local.file_match.nginx.targets
        forward_to = [loki.write.local.receiver]
      }

      loki.write "local" {
        endpoint {
          url = "http://127.0.0.1:3100/loki/api/v1/push"
        }
      }
    '';

    systemd.services.alloy.serviceConfig = {
      ReadOnlyPaths = lib.mkIf config.services.nginx.enable [ "/var/log/nginx" ];
      SupplementaryGroups = lib.mkIf config.services.nginx.enable (lib.mkAfter [ "nginx" ]);
    };
  };
}
