{ config, lib, ... }:
let
  enrollment = config.custom.services.grafana.telemetryEnrollment;
  inventory = (builtins.fromJSON (builtins.readFile ../telemetry-inventory.json)).machines;
  rollout = config.custom.services.grafana.telemetryRollout;
  alertingState = builtins.fromJSON (builtins.readFile ../telemetry-alerting.json);
  alertsPrepared = alertingState == { schemaVersion = 1; prepared = true; };
  enrolled = enrollment != { };
  machines = enrollment.machines or { };
  selected = builtins.filter (machine: builtins.elem machine.host rollout) inventory;
  nonempty = value: builtins.isString value && value != "";
  validMachine = expected:
    let machine = machines.${expected.host} or { };
    in builtins.isAttrs machine
      && builtins.isInt (machine.clientId or null) && machine.clientId > 0
      && lib.all (field: nonempty (machine.${field} or null)) [ "niceId" "olmId" ]
      && lib.all (field: (machine.${field} or null) == expected.${field})
      [ "name" "environment" "role" "secretKey" ];
  collector = builtins.head (builtins.filter (machine: machine.host == "hel1") inventory);
in
{
  imports = [ ./pangolin-telemetry-client.nix ./grafana-alerting.nix ./telemetry-watchdog.nix ];

  options.custom.services.grafana.telemetryEnrollment = lib.mkOption {
    type = lib.types.attrs;
    default = builtins.fromJSON (builtins.readFile ../telemetry-enrollment.json);
    description = "Public machine enrollment metadata; credentials remain exclusively in SOPS.";
  };
  options.custom.services.grafana.telemetryRollout = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = import ../telemetry-rollout.nix;
    description = "Canonical hosts admitted to central telemetry in the current deployment stage.";
  };

  config = lib.mkIf (config.custom.services.grafana.enable && enrolled) {
    assertions = [
      {
        assertion = alertingState == { } || alertsPrepared;
        message = "Invalid telemetry-alerting.json; prepare the dedicated ciphertext with the operator helper.";
      }
      {
        assertion = builtins.isAttrs enrollment
          && (enrollment.schemaVersion or null) == 1
          && (enrollment.endpoint or null) == "https://pangolin.banditlair.com"
          && nonempty (enrollment.orgId or null)
          && nonempty (enrollment.utilitySubnet or null)
          && nonempty (enrollment.dnsAddress or null)
          && builtins.isAttrs machines && validMachine collector;
        message = "Invalid telemetry enrollment manifest or central collector identity; run the operator enrollment workflow.";
      }
      {
        assertion = builtins.length selected == builtins.length rollout
          && builtins.length (lib.unique rollout) == builtins.length rollout
          && lib.all (machine: machine.environment != "banditlair" && validMachine machine) selected;
        message = "Telemetry rollout contains an unknown, duplicate, or unenrolled source host.";
      }
    ];

    sops.secrets.telemetryClient = {
      key = "telemetry/clients/hel1";
      restartUnits = [ "pangolin-telemetry.service" ];
    };

    services.pangolin-telemetry = {
      enable = true;
      inherit (enrollment) endpoint utilitySubnet dnsAddress;
      credentialsFile = config.sops.secrets.telemetryClient.path;
      consumerUnit = "prometheus";
      consumerUser = "prometheus";
      allowedTCPPorts = [ 9100 9117 30091 ];
    };

    custom.services.grafana.telemetryHosts = map
      (machine: { inherit (machine) host environment role; })
      selected;

    custom.services.grafana.alerting = lib.mkIf alertsPrepared {
      enable = lib.mkDefault true;
      secretsFile = ../secrets/telemetry-alerts.enc.yml;
    };
    custom.services.telemetryWatchdog = lib.mkIf alertsPrepared {
      enable = lib.mkDefault true;
      mode = "sender";
      secretsFile = ../secrets/telemetry-alerts.enc.yml;
      inherit (enrollment) utilitySubnet dnsAddress;
    };

    services.newt.blueprint.private-resources.osteoview-loki-ingest = {
      name = "Osteoview log ingestion";
      mode = "http";
      destination = "127.0.0.1";
      destination-port = 3102;
      scheme = "http";
      full-domain = "telemetry.banditlair.com";
      ssl = true;
      roles = [ ];
      users = [ ];
      machines = map (machine: machines.${machine.host}.niceId) selected;
    };
  };
}
