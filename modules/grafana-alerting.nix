{ config, lib, ... }:
let
  cfg = config.custom.services.grafana;
  alert = cfg.alerting;
  prometheusUid = "PBFA97CFB590B2093";
  lokiUid = "P8E80F9AEF21F6940";
  # Math conditions return 0 for healthy and 1 for firing, retaining series labels.
  query = uid: expression: refId: {
    inherit refId;
    datasourceUid = uid;
    relativeTimeRange = { from = 900; to = 0; };
    model = {
      datasource = { type = if uid == lokiUid then "loki" else "prometheus"; uid = uid; };
      editorMode = "code";
      expr = expression;
      instant = true;
      range = false;
      queryType = if uid == lokiUid then "instant" else "";
      refId = refId;
    };
  };
  condition = expression: {
    refId = "B";
    datasourceUid = "__expr__";
    relativeTimeRange = { from = 0; to = 0; };
    model = {
      datasource = { type = "__expr__"; uid = "__expr__"; };
      type = "math";
      inherit expression;
      refId = "B";
    };
  };
  rule = { uid, title, expr, threshold ? 0, duration ? "1m", environment ? null, host ? null, source ? prometheusUid, extraData ? [ ], annotations ? { } }:
    {
      inherit uid title;
      condition = "B";
      for = duration;
      noDataState = "OK";
      execErrState = "Error";
      labels = { severity = "warning"; } // lib.optionalAttrs (environment != null) { inherit environment; } // lib.optionalAttrs (host != null) { inherit host; };
      annotations = { summary = title + (if host == null then " on {{ $labels.instance }}" else " on ${host}"); } // annotations;
      data = [ (query source expr "A") ] ++ extraData ++ [ (condition "$A > ${toString threshold}") ];
    };
  node = "job=\"node\",environment=~\"staging|production\"";
  resources = [
    (rule { uid = "ov-filesystem"; title = "Filesystem usage above 80%"; expr = "100 * (1 - node_filesystem_avail_bytes{${node},mountpoint=\"/\",fstype!=\"rootfs\"} / node_filesystem_size_bytes{${node},mountpoint=\"/\",fstype!=\"rootfs\"})"; threshold = 80; })
    (rule { uid = "ov-ram"; title = "RAM free below 20%"; expr = "100 * (1 - (node_memory_Buffers_bytes{${node}} + node_memory_MemFree_bytes{${node}} + node_memory_Cached_bytes{${node}}) / node_memory_MemTotal_bytes{${node}})"; threshold = 80; })
    (rule { uid = "ov-cpu"; title = "CPU busy above 80% over 5m"; expr = "100 * (1 - avg by (environment, instance, host) (rate(node_cpu_seconds_total{${node},mode=\"idle\"}[5m])))"; threshold = 80; })
    (rule { uid = "ov-systemd"; title = "Systemd unit failed"; expr = "node_systemd_unit_state{${node},state=\"failed\"}"; })
  ];
  target = host: job: rule {
    uid = "ov-target-${job}-${host.host}";
    title = "${job} target unavailable";
    environment = host.environment;
    inherit (host) host;
    duration = "2m";
    expr = "(up{job=\"${job}\",environment=\"${host.environment}\",instance=\"${host.host}\"} == bool 0) or absent(up{job=\"${job}\",environment=\"${host.environment}\",instance=\"${host.host}\"})";
  };
  hostRules = lib.concatMap
    (host: (map (target host) ([ "node" ] ++ lib.optionals (host.role == "backend") [ "nginx" "osteoview" ])) ++ [
      (rule {
        uid = "ov-logs-${host.host}";
        title = "Journal heartbeat missing";
        environment = host.environment;
        inherit (host) host;
        duration = "2m";
        source = lokiUid;
        expr = "absent_over_time({job=\"systemd-journal\",environment=\"${host.environment}\",host=\"${host.host}\",unit=\"telemetry-heartbeat.service\"}[15m])";
      })
    ])
    cfg.telemetryHosts;
  watchdog = (rule {
    uid = "ov-telemetry-watchdog";
    title = "TelemetryWatchdog";
    expr = "up{job=\"prometheus\",instance=\"127.0.0.1:9090\"}";
    source = prometheusUid;
    duration = "0s";
    extraData = [ (query prometheusUid "time()" "T") ];
    annotations = { watchdog_evaluated_at = "{{ printf \"%.0f\" $values.T.Value }}"; };
  }) // {
    labels = { watchdog = "central"; };
    # Only a confirmed self-scrape of 1 can fire; NoData or errors must resolve.
    noDataState = "OK";
    execErrState = "OK";
  };
in
{
  options.custom.services.grafana.alerting = {
    enable = lib.mkEnableOption "central telemetry alerting (requires operator-prepared SOPS secrets)";
    secretsFile = lib.mkOption {
      type = lib.types.path;
      description = "Operator-prepared encrypted secrets/telemetry-alerts.enc.yml; never placed in the Nix store as plaintext.";
    };
  };

  config = lib.mkIf (cfg.enable && alert.enable) {
    sops.secrets = lib.mapAttrs
      (_: key: {
        inherit key;
        sopsFile = alert.secretsFile;
        owner = config.users.users.grafana.name;
        restartUnits = [ "grafana.service" ];
      })
      {
        telemetrySmtpUser = "smtp/user";
        telemetrySmtpPassword = "smtp/password";
        telemetryStagingRecipient = "recipients/staging";
        telemetryProductionRecipient = "recipients/production";
      };
    services.grafana.settings.smtp = {
      enabled = true;
      host = "mail.your-server.de:465";
      user = "$__file{${config.sops.secrets.telemetrySmtpUser.path}}";
      password = "$__file{${config.sops.secrets.telemetrySmtpPassword.path}}";
      from_address = "$__file{${config.sops.secrets.telemetrySmtpUser.path}}";
      startTLS_policy = "NoStartTLS"; # Port 465 uses implicit TLS, not STARTTLS.
    };
    services.grafana.provision.alerting = {
      rules.settings = {
        apiVersion = 1;
        groups = [{
          orgId = 1;
          name = "Telemetry";
          folder = "Telemetry";
          interval = "1m";
          rules = let allRules = resources ++ hostRules ++ [ watchdog ]; in
            assert lib.assertMsg (lib.all (r: builtins.stringLength r.uid <= 40) allRules) "Grafana telemetry alert rule UID exceeds 40 characters";
            allRules;
        }];
      };
      contactPoints.settings = {
        apiVersion = 1;
        contactPoints = [
          { orgId = 1; name = "Telemetry staging"; receivers = [{ uid = "ov-receiver-staging"; type = "email"; settings = { addresses = "$__file{${config.sops.secrets.telemetryStagingRecipient.path}}"; subject = "[STAGING] {{ .CommonLabels.alertname }}"; }; }]; }
          { orgId = 1; name = "Telemetry production"; receivers = [{ uid = "ov-receiver-production"; type = "email"; settings = { addresses = "$__file{${config.sops.secrets.telemetryProductionRecipient.path}}"; subject = "[PRODUCTION] {{ .CommonLabels.alertname }}"; }; }]; }
          {
            orgId = 1;
            name = "Telemetry watchdog";
            receivers = [{
              uid = "ov-receiver-watchdog";
              type = "webhook";
              disableResolveMessage = true;
              settings = {
                url = "http://127.0.0.1:3103/watchdog";
                httpMethod = "POST";
                authorization_scheme = "Bearer";
                authorization_credentials = "$__file{${config.sops.secrets.telemetryWatchdogToken.path}}";
              };
            }];
          }
        ];
      };
      policies.settings = {
        apiVersion = 1;
        policies = [{
          orgId = 1;
          receiver = "Telemetry production";
          group_by = [ "alertname" "environment" "instance" ];
          routes = [
            { receiver = "Telemetry watchdog"; object_matchers = [ [ "watchdog" "=" "central" ] ]; group_wait = "0s"; group_interval = "1m"; repeat_interval = "1m"; continue = false; }
            { receiver = "Telemetry staging"; object_matchers = [ [ "environment" "=" "staging" ] ]; continue = false; }
            { receiver = "Telemetry production"; object_matchers = [ [ "environment" "=" "production" ] ]; continue = false; }
          ];
        }];
      };
    };
  };
}
