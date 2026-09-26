{ pkgs, helConfiguration }:
let
  lib = pkgs.lib;
  inventory = (builtins.fromJSON (builtins.readFile ../../telemetry-inventory.json)).machines;
  sources = builtins.filter (machine: machine.host != "hel1") inventory;
  sourceNames = map (machine: machine.host) sources;
  stagingNames = map (machine: machine.host) (builtins.filter (machine: machine.environment == "staging") sources);
  enrollment = {
    schemaVersion = 1;
    orgId = "fixture";
    endpoint = "https://pangolin.banditlair.com";
    utilitySubnet = "100.96.128.0/20";
    dnsAddress = "100.96.128.1";
    machines = builtins.listToAttrs (lib.imap0
      (index: machine: {
        name = machine.host;
        value = builtins.removeAttrs machine [ "host" ] // {
          clientId = index + 1;
          niceId = "fixture-${machine.host}";
          olmId = "fixture-olm-${machine.host}";
        };
      })
      inventory);
  };
  evaluate = rollout: metadata: (helConfiguration.extendModules {
    modules = [{
      custom.services.grafana = {
        telemetryEnrollment = metadata;
        telemetryRollout = rollout;
        alerting.enable = lib.mkForce false;
      };
      custom.services.telemetryWatchdog.enable = lib.mkForce false;
    }];
  }).config;
  valid = configuration: lib.all (assertion: assertion.assertion) configuration.assertions;
  pending = evaluate [ "backup1-staging" ] { };
  job = configuration: name: builtins.head (builtins.filter (item: item.job_name == name) configuration.services.prometheus.scrapeConfigs);
  checkRollout = rollout:
    let
      configuration = evaluate rollout enrollment;
      resources = configuration.services.newt.blueprint.private-resources;
      selected = builtins.filter (machine: builtins.elem machine.host rollout) sources;
      backends = builtins.filter (machine: machine.role == "backend") selected;
      nodeTargets = builtins.tail (job configuration "node").static_configs;
      sorted = builtins.sort builtins.lessThan;
    in
    assert valid configuration;
    assert configuration.services.pangolin-telemetry.enable;
    assert configuration.services.pangolin-telemetry.consumerUser == "prometheus";
    assert configuration.services.pangolin-telemetry.allowedTCPPorts == [ 9100 9117 30091 ];
    assert resources.osteoview-loki-ingest.machines == map (machine: "fixture-${machine.host}") selected;
    assert resources.osteoview-loki-ingest.roles == [ ];
    assert resources.osteoview-loki-ingest.users == [ ];
    assert resources.osteoview-loki-ingest.destination-port == 3102;
    assert resources.osteoview-loki-ingest.ssl;
    assert resources.grafana.roles == [ "Personal" ];
    assert resources.hel1-ssh.tcp-ports == "22";
    assert sorted (map (target: target.labels.instance) nodeTargets) == sorted rollout;
    assert lib.all
      (target:
        target.targets == [ "${target.labels.host}-metrics.ov.internal:9100" ]
        && target.labels.instance == target.labels.host
        && target.labels.environment == enrollment.machines.${target.labels.host}.environment
      )
      nodeTargets;
    assert backends == [ ] || (
      sorted (map (target: target.labels.host) (job configuration "nginx").static_configs) == sorted (map (host: host.host) backends)
        && lib.all (target: target.targets == [ "${target.labels.host}-metrics.ov.internal:9117" ]) (job configuration "nginx").static_configs
        && lib.all (target: target.targets == [ "${target.labels.host}-metrics.ov.internal:30091" ]) (job configuration "osteoview").static_configs
        && (job configuration "osteoview").metrics_path == "/_metrics"
    );
    assert configuration.sops.secrets.telemetryClient.key == "telemetry/clients/hel1";
    true;
  wrongEndpoint = evaluate [ "backup1-staging" ] (enrollment // { endpoint = "https://untrusted.invalid"; });
  wrongIdentity = evaluate [ "backup1-staging" ] (enrollment // {
    machines = enrollment.machines // {
      hel1 = enrollment.machines.hel1 // { clientId = "1"; };
    };
  });
in
assert valid pending;
assert !pending.services.pangolin-telemetry.enable;
assert pending.custom.services.grafana.telemetryHosts == [ ];
assert !(pending.services.newt.blueprint.private-resources ? osteoview-loki-ingest);
assert !valid wrongEndpoint;
assert !valid wrongIdentity;
assert checkRollout [ "backup1-staging" ];
assert checkRollout stagingNames;
assert checkRollout sourceNames;
pkgs.runCommand "telemetry-central-fixture" { } ''
  touch "$out"
''
