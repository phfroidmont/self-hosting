{ pkgs, helConfiguration }:
let
  providers = helConfiguration.config.services.grafana.provision.dashboards.settings.providers;
  environments = {
    banditlair = "banditlair";
    osteoview-production = "production";
    osteoview-staging = "staging";
  };
  checkFolder = provider: ''
    check ${provider.folderUid} ${environments.${provider.folderUid}} ${provider.options.path}
  '';
in
assert map (provider: provider.folderUid) providers == builtins.attrNames environments;
pkgs.runCommand "telemetry-dashboards-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -eu
  check() {
    folder=$1 environment=$2 directory=$3
    for dashboard in "$directory"/*.json; do
      if ! jq -e --arg environment "$environment" '
        (.uid | startswith($environment + "-") and length <= 40)
        and .tags == [$environment]
        and ([.templating.list[] | select(.name == "environment")]
          | length == 1 and .[0].type == "constant" and .[0].query == $environment)
        and (tostring | contains("''${DS_") | not)
        and ([.. | objects | .datasource? | objects | .uid]
          - ["PBFA97CFB590B2093", "P8E80F9AEF21F6940", "grafana", "-- Grafana --"] | length == 0)
      ' "$dashboard" >/dev/null; then
        echo "Invalid dashboard $dashboard in folder $folder" >&2
        exit 1
      fi
    done
    cat "$directory"/*.json >> all.json
  }
  ${pkgs.lib.concatMapStrings checkFolder providers}
  jq -se 'map(.uid) | length == 23 and length == (unique | length)' all.json >/dev/null
  touch "$out"
''
