#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Create or update a Matrix user through Synapse Admin API.

Usage:
  create-matrix-user.sh [options]

Defaults:
  --homeserver-url URL      Base URL (default: http://127.0.0.1:8008)
  --server-name NAME        Matrix server_name (default: banditlair.com)
  --admin-user USER         Admin username for password login (default: paultrial)

Required:
  --user LOCALPART          Username without @ and :domain

Authentication (choose one):
  --access-token TOKEN      Admin access token
  --admin-user USER         Admin username for password login
  --admin-password PASS     Admin password for password login

Optional:
  --password PASS           Password for new user (auto-generated if omitted)
  --display-name NAME       Display name (defaults to username)
  --admin                   Create as admin user
  --help                    Show this help

Examples:
  ./scripts/create-matrix-user.sh \
    --user hermes-accounting \
    --admin-user admin

  ./scripts/create-matrix-user.sh \
    --access-token syt_... \
    --password 'strong-password'
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
new_user=""
new_password=""
display_name=""
admin_flag=false
access_token=""
admin_user="paultrial"
admin_password=""

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
		new_user="$2"
		shift 2
		;;
	--password)
		new_password="$2"
		shift 2
		;;
	--display-name)
		display_name="$2"
		shift 2
		;;
	--admin)
		admin_flag=true
		shift
		;;
	--access-token)
		access_token="$2"
		shift 2
		;;
	--admin-user)
		admin_user="$2"
		shift 2
		;;
	--admin-password)
		admin_password="$2"
		shift 2
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

if [[ -z "$new_user" ]]; then
	printf 'Missing required argument: --user\n\n' >&2
	usage
	exit 1
fi

if [[ "$new_user" == @* || "$new_user" == *:* ]]; then
	printf '--user must be a localpart only (example: hermes-accounting)\n' >&2
	exit 1
fi

if [[ -z "$display_name" ]]; then
	display_name="$new_user"
fi

homeserver_url="${homeserver_url%/}"

if [[ -z "$access_token" ]]; then
	if [[ -z "$admin_user" ]]; then
		read -r -p 'Admin username: ' admin_user
	fi

	if [[ -z "$admin_password" ]]; then
		admin_password="$(read_secret 'Admin password: ')"
	fi

	login_payload=$(
		cat <<EOF
{"type":"m.login.password","identifier":{"type":"m.id.user","user":$(json_escape "$admin_user")},"password":$(json_escape "$admin_password")}
EOF
	)

	login_response="$(curl -sS -X POST "${homeserver_url}/_matrix/client/v3/login" \
		-H 'Content-Type: application/json' \
		--data "$login_payload")"

	access_token="$(printf '%s' "$login_response" | json_get access_token)"
	if [[ -z "$access_token" ]]; then
		printf 'Failed to get admin access token. Response:\n%s\n' "$login_response" >&2
		exit 1
	fi
fi

generated_password=false
if [[ -z "$new_password" ]]; then
	new_password="$(python3 -c 'import secrets, string; alphabet=string.ascii_letters+string.digits+"-_"; print("".join(secrets.choice(alphabet) for _ in range(32)))')"
	generated_password=true
fi

admin_json=false
if [[ "$admin_flag" == true ]]; then
	admin_json=true
fi

mxid="@${new_user}:${server_name}"
user_payload=$(
	cat <<EOF
{"password":$(json_escape "$new_password"),"displayname":$(json_escape "$display_name"),"admin":${admin_json},"deactivated":false}
EOF
)

tmp_response="$(mktemp)"
trap 'rm -f "$tmp_response"' EXIT

http_code=$(curl -sS -o "$tmp_response" -w '%{http_code}' \
	-X PUT "${homeserver_url}/_synapse/admin/v2/users/${mxid}" \
	-H "Authorization: Bearer ${access_token}" \
	-H 'Content-Type: application/json' \
	--data "$user_payload")

if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
	printf 'Failed to create/update user (HTTP %s). Response:\n' "$http_code" >&2
	cat "$tmp_response" >&2
	printf '\n' >&2
	exit 1
fi

printf 'User ready: %s\n' "$mxid"
if [[ "$generated_password" == true ]]; then
	printf 'Generated password: %s\n' "$new_password"
fi
printf 'Response:\n'
cat "$tmp_response"
printf '\n'
