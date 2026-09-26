{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.grafana;
  backendTelemetryHosts = builtins.filter (host: host.role == "backend") cfg.telemetryHosts;
  telemetryTarget = port: host: {
    targets = [ "${host.host}-metrics.ov.internal:${toString port}" ];
    labels = {
      instance = host.host;
      inherit (host) host environment role;
    };
  };
in
{
  options.custom.services.grafana = {
    enable = lib.mkEnableOption "grafana";
    telemetryHosts = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Canonical host name, for example backup1-staging.";
          };
          environment = lib.mkOption {
            type = lib.types.enum [ "staging" "production" ];
          };
          role = lib.mkOption {
            type = lib.types.enum [ "backend" "db" "backup" "bastion" ];
          };
        };
      });
      default = [ ];
      description = "Hosts scraped through Newt; only backends expose application and nginx metrics.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      grafanaAdminPassword = {
        owner = config.users.users.grafana.name;
        key = "grafana/admin_password";
      };
      grafanaSecretKey = {
        owner = config.users.users.grafana.name;
        key = "grafana/secret_key";
      };
    };

    services = {
      grafana = {
        enable = true;
        dataDir = "/nix/var/data/grafana";
        settings = {
          server = {
            domain = "grafana.${config.networking.domain}";
            root_url = "https://${config.services.grafana.settings.server.domain}/";
          };
          security = {
            admin_password = "$__file{${config.sops.secrets.grafanaAdminPassword.path}}";
            secret_key = "$__file{${config.sops.secrets.grafanaSecretKey.path}}";
          };
        };
        provision = {
          enable = true;
          datasources.settings = {
            datasources = [
              {
                name = "Prometheus";
                uid = "PBFA97CFB590B2093";
                type = "prometheus";
                url = "http://127.0.0.1:${toString config.services.prometheus.port}";
                isDefault = true;
              }
              {
                name = "Loki";
                uid = "P8E80F9AEF21F6940";
                type = "loki";
                access = "proxy";
                url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}";
              }
            ];
          };
          dashboards.settings.providers = [
            {
              name = "Config";
              options.path = ./dashboards;
            }
          ];
        };
      };

      prometheus = {
        enable = true;
        listenAddress = "127.0.0.1";
        retentionTime = "180d";
        scrapeConfigs = [
          {
            job_name = "node";
            static_configs = [
              {
                targets = [
                  "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
                ];
                labels = {
                  environment = "banditlair";
                  host = "hel1";
                  role = "hosting";
                };
              }
            ] ++ map (telemetryTarget 9100) cfg.telemetryHosts;
          }
          {
            job_name = "synapse";
            scrape_interval = "15s";
            metrics_path = "/_synapse/metrics";
            static_configs = [{ targets = [ "127.0.0.1:9000" ]; }];
          }
          {
            job_name = "dmarc";
            scrape_interval = "15s";
            static_configs = [
              {
                targets = [
                  "127.0.0.1:${toString config.services.prometheus.exporters.dmarc.port}"
                ];
              }
            ];
          }
          {
            job_name = "prometheus";
            static_configs = [{ targets = [ "127.0.0.1:9090" ]; }];
          }
          {
            job_name = "loki";
            static_configs = [{ targets = [ "127.0.0.1:3100" ]; }];
          }
        ] ++ lib.optionals (backendTelemetryHosts != [ ]) [
          {
            job_name = "osteoview";
            metrics_path = "/_metrics";
            static_configs = map (telemetryTarget 30091) backendTelemetryHosts;
          }
          {
            job_name = "nginx";
            static_configs = map (telemetryTarget 9117) backendTelemetryHosts;
          }
        ];
      };

      nginx = {
        enable = true;
        appendHttpConfig = ''
          # All Newt clients arrive from loopback. Budget the private gateway as
          # a whole, independently of the public vhosts' per-IP limits.
          limit_req_zone $server_name zone=telemetry_ingest_requests:1m rate=100r/s;
          limit_conn_zone $server_name zone=telemetry_ingest_connections:1m;
        '';
        virtualHosts."telemetry-ingest.local" = {
          # The sole vhost on this socket also accepts Newt's preserved Host.
          listen = [{ addr = "127.0.0.1"; port = 3102; ssl = false; }];
          extraConfig = ''
            client_max_body_size 10m;
            client_body_timeout 30s;
            client_header_timeout 10s;
            send_timeout 30s;
            keepalive_timeout 15s;

            # Defining both here replaces, rather than inherits, the HTTP-level
            # perip/perip_conn limits. Public vhost policy is unchanged.
            limit_req zone=telemetry_ingest_requests burst=200 nodelay;
            limit_req_status 429;
            limit_conn telemetry_ingest_connections 256;
            limit_conn_status 429;
          '';
          locations."= /loki/api/v1/push" = {
            proxyPass = "http://127.0.0.1:3100";
            extraConfig = ''
              if ($request_method != POST) { return 405; }
              if ($request_uri != "/loki/api/v1/push") { return 404; }
              proxy_connect_timeout 5s;
              proxy_send_timeout 30s;
              proxy_read_timeout 30s;
            '';
          };
          locations."/".extraConfig = ''
            return 404;
          '';
        };
      };

      loki = {
        enable = true;

        # Loki 3.7.6 still lacks the BoltDB cross-day retention fix. Keep the
        # exact patch pin used by appinfra until an upstream release includes it.
        package = pkgs.grafana-loki.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (pkgs.fetchurl {
              url = "https://patch-diff.githubusercontent.com/raw/grafana/loki/pull/23402.patch";
              hash = "sha256-g3u3Fi40NYq6qjc8BOlHtm+h+2f7R6MDIGkZDtZ9t9k=";
            })
          ];
        });

        configuration = {
          server = {
            http_listen_address = "127.0.0.1";
            http_listen_port = 3100;
            grpc_listen_address = "127.0.0.1";
          };
          # The scheduler must advertise the frontend's loopback gRPC listener,
          # not the container IP chosen by automatic interface discovery.
          frontend.address = "127.0.0.1";
          auth_enabled = false;

          ingester = {
            lifecycler = {
              address = "127.0.0.1";
              ring = {
                kvstore = {
                  store = "inmemory";
                };
                replication_factor = 1;
              };
            };
            chunk_idle_period = "1h";
            max_chunk_age = "1h";
            chunk_target_size = 999999;
            chunk_retain_period = "30s";
          };

          limits_config = {
            ingestion_rate_mb = 16;
            allow_structured_metadata = false;
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
            retention_period = "8760h";
            max_query_lookback = "8760h";
          };

          schema_config = {
            configs = [
              {
                from = "2022-09-15";
                store = "boltdb-shipper";
                object_store = "filesystem";
                schema = "v11";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];
          };

          storage_config = {
            boltdb_shipper = {
              active_index_directory = "${config.services.loki.dataDir}/boltdb-index";
              cache_location = "${config.services.loki.dataDir}/boltdb-cache";
              cache_ttl = "24h";
            };

            filesystem = {
              directory = "${config.services.loki.dataDir}/chunks";
            };
          };

          querier.engine.max_look_back_period = "0s";

          compactor = {
            working_directory = "${config.services.loki.dataDir}";
            compaction_interval = "10m";
            retention_enabled = true;
            retention_delete_delay = "2h";
            retention_delete_worker_count = 50;
            delete_request_store = "filesystem";
            compactor_ring = {
              kvstore = {
                store = "inmemory";
              };
            };
          };

          analytics = {
            reporting_enabled = false;
          };
        };
      };
    };
  };
}
