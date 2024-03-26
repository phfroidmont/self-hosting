{ config, lib, ... }:
let cfg = config.custom.services.grafana;
in {
  options.custom.services.grafana = { enable = lib.mkEnableOption "grafana"; };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      grafanaAdminPassword = {
        owner = config.users.users.grafana.name;
        key = "grafana/admin_password";
      };
    };

    services.grafana = {
      enable = true;
      dataDir = "/nix/var/data/grafana";
      settings = {
        server = { domain = "grafana.${config.networking.domain}"; };
        security.admin_password =
          "$__file{${config.sops.secrets.grafanaAdminPassword.path}}";
      };
      provision = {
        enable = true;
        datasources.settings = {
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url =
                "http://127.0.0.1:${toString config.services.prometheus.port}";
              isDefault = true;
            }
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:${
                  toString
                  config.services.loki.configuration.server.http_listen_port
                }";
            }
          ];
        };
        dashboards.settings.providers = [{
          name = "Config";
          options.path = ./dashboards;
        }];
      };
    };

    services.nginx = {
      virtualHosts = {
        "${config.services.grafana.settings.server.domain}" = {

          enableACME = true;
          forceSSL = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:${
                toString config.services.grafana.settings.server.http_port
              }";
            proxyWebsockets = true;
          };
        };
      };
    };

    services.prometheus = {
      enable = true;

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [
              "10.0.2.3:${
                toString config.services.prometheus.exporters.node.port
              }"
              "10.0.1.1:${
                toString config.services.prometheus.exporters.node.port
              }"
              "10.0.1.11:${
                toString config.services.prometheus.exporters.node.port
              }"
            ];
          }];
        }
        {
          job_name = "synapse";
          scrape_interval = "15s";
          metrics_path = "/_synapse/metrics";
          static_configs = [{ targets = [ "10.0.1.1:9000" ]; }];
        }
        {
          job_name = "dmarc";
          scrape_interval = "15s";
          static_configs = [{
            targets = [
              "10.0.2.3:${
                toString config.services.prometheus.exporters.dmarc.port
              }"
            ];
          }];
        }
      ];
    };

    services.loki = {
      enable = true;

      dataDir = "/nix/var/data/loki";

      configuration = {
        server.http_listen_port = 3100;
        auth_enabled = false;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore = { store = "inmemory"; };
              replication_factor = 1;
            };
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 999999;
          chunk_retain_period = "30s";
          max_transfer_retries = 0;
        };

        limits_config = { ingestion_rate_mb = 16; };

        schema_config = {
          configs = [{
            from = "2022-09-15";
            store = "boltdb-shipper";
            object_store = "filesystem";
            schema = "v11";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };

        storage_config = {
          boltdb_shipper = {
            active_index_directory =
              "${config.services.loki.dataDir}/boltdb-index";
            cache_location = "${config.services.loki.dataDir}/boltdb-cache";
            cache_ttl = "24h";
            shared_store = "filesystem";
          };

          filesystem = {
            directory = "${config.services.loki.dataDir}/chunks";
          };
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        chunk_store_config = { max_look_back_period = "0s"; };

        table_manager = {
          retention_deletes_enabled = false;
          retention_period = "0s";
        };

        compactor = {
          working_directory = "${config.services.loki.dataDir}";
          shared_store = "filesystem";
          compactor_ring = { kvstore = { store = "inmemory"; }; };
        };

        analytics = { reporting_enabled = false; };
      };
    };
  };
}
