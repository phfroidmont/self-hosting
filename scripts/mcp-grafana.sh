#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
secrets_file="$repository_root/secrets.enc.yml"

if ! token="$(sops --decrypt --extract '["grafana"]["mcp_service_account_token"]' "$secrets_file")"; then
	echo "Unable to decrypt the Grafana MCP service-account token" >&2
	exit 1
fi

if [[ -z "$token" ]]; then
	echo "The Grafana MCP service-account token is empty" >&2
	exit 1
fi

export GRAFANA_URL="https://grafana.banditlair.com"
export GRAFANA_SERVICE_ACCOUNT_TOKEN="$token"

exec mcp-grafana \
	--enabled-tools search,datasource,prometheus,loki,alerting,dashboard,navigation \
	--disable-write \
	--max-loki-log-limit 100
