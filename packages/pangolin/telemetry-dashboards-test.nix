{ pkgs }:
let
  nodes = ../../modules/dashboards/nodes.json;
  requests = ../../modules/dashboards/request-handling-performance.json;
in
pkgs.runCommand "telemetry-dashboards-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -eu
  test "$(jq -r .uid ${nodes})" = xfpJB9FGz
  test "$(jq -r .uid ${requests})" = 4GFbkOsZk
  jq -se 'map(.uid) | length == (unique | length)' ${../../modules/dashboards}/*.json >/dev/null
  jq -e '.templating.list | map(.name) | index("environment") and index("node")' ${nodes} >/dev/null
  jq -e '.templating.list[] | select(.name == "environment") | .includeAll and .allValue == ".*" and .type == "custom" and .query == "banditlair,staging,production"' ${nodes} >/dev/null
  jq -e '.templating.list[] | select(.name == "node") | .includeAll and ((.allValue // "") != ".*") and (.query.query == "label_values(node_uname_info{environment=~\"$environment\",job=~\"$job\",nodename=~\"$hostname\"},instance)")' ${nodes} >/dev/null
  jq -e '[.panels[].targets[]?.expr | select(contains("$node"))] | length == 60 and all(.[]; contains("instance=~\"$node\"") or contains("instance=~\u0027$node\u0027"))' ${nodes} >/dev/null
  jq -e '[.panels[].targets[]? | .expr | select(contains("origin_prometheus"))] | length == 0' ${nodes} >/dev/null
  jq -e '[.panels[].targets[]? | .expr | select(contains("environment=~"))] | length >= 20' ${nodes} >/dev/null
  jq -e '.templating.list | map(.name) == ["environment", "instance"]' ${requests} >/dev/null
  jq -e '.templating.list[] | select(.name == "environment") | (.multi == false and .includeAll == false)' ${requests} >/dev/null
  jq -e '[.panels[].targets[].expr | select(contains("job=\"nginx\"") and contains("environment=\"$environment\"") and contains("instance=~\"$instance\"") and (contains("$host") | not))] | length == 13' ${requests} >/dev/null
  jq -e '[.panels[].targets[].expr | scan("\\{[^{}]+\\}")] | length == 20 and all(.[]; startswith("{job=\"nginx\",environment=\"$environment\",instance=~\"$instance\","))' ${requests} >/dev/null
  jq -e '[.panels[].targets[].expr | select(contains("nginx_http_response_count_total")) | select(contains("job=\"nginx\"") | not)] | length == 0' ${requests} >/dev/null
  jq -e '.panels | length == 9' ${requests} >/dev/null
  touch "$out"
''
