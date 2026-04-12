#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Get a Matrix access token using password login.

Usage:
  get-matrix-access-token.sh --user USER [options]

Required:
  --user USER               Localpart or full mxid

Optional:
  --password PASS           User password (prompted if omitted)
  --homeserver-url URL      Base URL (default: http://127.0.0.1:8008)
  --server-name NAME        Matrix server_name for localpart users (default: banditlair.com)
  --device-id ID            Device ID (default: HERMES_ACCOUNTING_BOT)
  --display-name NAME       Device display name (default: Hermes Accounting Bot)
  --raw                     Print only the access token
  --help                    Show this help

Example:
  ./scripts/get-matrix-access-token.sh --user hermes-accounting
EOF
}

json_get() {
	local key="$1"
	python3 -c 'import json, sys; data=json.load(sys.stdin); value=data.get(sys.argv[1], ""); print(value if isinstance(value, str) else "")' "$key"
}

json_escape() {
	python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

read_secret() {
	local prompt="$1"
	local value
	read -r -s -p "$prompt" value
	printf '\n' >&2
	printf '%s' "$value"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'Missing required command: %s\n' "$1" >&2
		exit 1
	}
}

require_cmd curl
require_cmd python3

homeserver_url="http://127.0.0.1:8008"
server_name="banditlair.com"
user_input=""
user_password=""
device_id="HERMES_ACCOUNTING_BOT"
display_name="Hermes Accounting Bot"
raw_output=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--homeserver-url)
		homeserver_url="$2"
		shift 2
		;;
	--server-name)
		server_name="$2"
		shift 2
		;;
	--user)
		user_input="$2"
		shift 2
		;;
	--password)
		user_password="$2"
		shift 2
		;;
	--device-id)
		device_id="$2"
		shift 2
		;;
	--display-name)
		display_name="$2"
		shift 2
		;;
	--raw)
		raw_output=true
		shift
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		printf 'Unknown argument: %s\n\n' "$1" >&2
		usage
		exit 1
		;;
	esac
done

if [[ -z "$user_input" ]]; then
	printf 'Missing required argument: --user\n\n' >&2
	usage
	exit 1
fi

homeserver_url="${homeserver_url%/}"

mxid="$user_input"
if [[ "$user_input" != @* ]]; then
	mxid="@${user_input}:${server_name}"
fi

if [[ -z "$user_password" ]]; then
	user_password="$(read_secret "Password for ${mxid}: ")"
fi

login_payload=$(
	cat <<EOF
{"type":"m.login.password","identifier":{"type":"m.id.user","user":$(json_escape "$mxid")},"password":$(json_escape "$user_password"),"device_id":$(json_escape "$device_id"),"initial_device_display_name":$(json_escape "$display_name")}
EOF
)

login_response="$(curl -sS -X POST "${homeserver_url}/_matrix/client/v3/login" \
	-H 'Content-Type: application/json' \
	--data "$login_payload")"

access_token="$(printf '%s' "$login_response" | json_get access_token)"
if [[ -z "$access_token" ]]; then
	printf 'Failed to get access token. Response:\n%s\n' "$login_response" >&2
	exit 1
fi

if [[ "$raw_output" == true ]]; then
	printf '%s\n' "$access_token"
	exit 0
fi

printf 'User: %s\n' "$(printf '%s' "$login_response" | json_get user_id)"
printf 'Device: %s\n' "$(printf '%s' "$login_response" | json_get device_id)"
printf 'Access token: %s\n' "$access_token"
