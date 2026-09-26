#!/usr/bin/env bash
# Operator-run only. Never pass a bootstrap key through argv, environment or a file.
set +x
set -euo pipefail
ulimit -c 0
umask 077
fail() {
	printf 'Enrollment stopped: %s\n' "$1" >&2
	exit 1
}
usage() { fail 'usage: pangolin-enroll-telemetry.sh check|enroll --org ORG --infrastructure-repo PATH [--state-dir PATH] [--gateway root@pangolin.banditlair.com]'; }
(($#)) || usage
action=$1
shift
[[ $action == check || $action == enroll ]] || usage
org='' infra='' state_dir='' gateway=root@pangolin.banditlair.com
while (($#)); do
	(($# >= 2)) || usage
	case $1 in
	--org) org=$2 ;; --infrastructure-repo) infra=$2 ;;
	--state-dir) state_dir=$2 ;; --gateway) gateway=$2 ;;
	*) usage ;;
	esac
	shift 2
done
[[ $org =~ ^[A-Za-z0-9_-]+$ && -d $infra && $gateway =~ ^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$ ]] || usage
for tool in jq yq sops gpg ssh curl flock sha256sum mktemp stat sync; do
	command -v "$tool" >/dev/null || fail "missing dependency: $tool"
done
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
infra=$(cd -- "$infra" && pwd -P)
inventory=$repo/telemetry-inventory.json
jq -e '
  .schemaVersion == 1 and (.machines|length) >= 15 and
  ([.machines[].host]|unique|length) == (.machines|length) and
  ([.machines[].name]|unique|length) == (.machines|length) and
  ([.machines[] | select(
    (.host|type)!="string" or (.name|type)!="string" or
    (.host|test("^[a-z0-9-]+$")|not) or (.name|test("^[a-z0-9-]+$")|not) or
    .secretKey != ("telemetry/clients/"+.host) or
    (if .environment=="banditlair" then .host!="hel1" or .name!="hel1-osteoview-metrics" or .role!="collector"
     else (.environment|IN("staging","production")|not) or
       .name != ("osteoview-"+.host+"-logs") or
       (if .role=="backend" then (.host|test("^backend[1-9][0-9]*-(staging|production)$")|not)
        elif .role=="db" then (.host|test("^db[1-9][0-9]*-(staging|production)$")|not)
        elif .role=="backup" then (.host|test("^backup[1-9][0-9]*-(staging|production)$")|not)
        elif .role=="bastion" then (.host|test("^bastion[1-9][0-9]*-(staging|production)$")|not)
        else true end) or (. as $machine | $machine.host|endswith("-"+$machine.environment)|not) end)
  )]|length)==0 and
  ([.machines[]|select(.environment=="staging")]|length)>=7 and
  ([.machines[]|select(.environment=="production")]|length)>=7
' "$inventory" >/dev/null 2>&1 || fail 'invalid inventory'
mapfile -t rows < <(jq -c '.machines[]' "$inventory")
[[ -n $state_dir ]] || state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/pangolin-enroll-telemetry
[[ ! -L $state_dir ]] || fail 'state directory symlink'
mkdir -p -- "$state_dir"
state_dir=$(cd -- "$state_dir" && pwd -P)
[[ -O $state_dir && $(stat -c %a "$state_dir") == 700 ]] || fail 'state directory must be owned and mode 0700'
exec 9>"$state_dir/lock"
flock -n 9 || fail 'enrollment already running'
target_for() {
	if [[ $1 == banditlair ]]; then
		target=$repo/secrets.enc.yml
	else target=$infra/environments/$1/secrets-$1.yaml; fi
}
recipients() {
	[[ -f $target && ! -L $target ]] || fail 'missing ciphertext destination'
	local meta
	meta=$(yq -o=json '.sops' "$target" 2>/dev/null) || fail 'invalid SOPS metadata'
	jq -e '(.pgp|type)=="array" and (.pgp|length)>0 and
    ([.pgp[].fp|select(type!="string" or (test("^[A-Fa-f0-9]{40}$")|not))]|length)==0 and
    ((.age//[])|length)==0 and ((.kms//[])|length)==0 and
    ((.gcp_kms//[])|length)==0 and ((.azure_kv//[])|length)==0 and
    ((.hc_vault//[])|length)==0' <<<"$meta" >/dev/null 2>&1 || fail 'unsupported SOPS recipients'
	pgp=$(jq -r '[.pgp[].fp]|join(",")' <<<"$meta")
}
for environment in banditlair staging production; do
	target_for "$environment"
	recipients
done
[[ $action == enroll ]] || {
	printf 'Inventory and public SOPS metadata checked; no API calls.\n'
	exit 0
}

# Operator may unlock their own ciphertext. Probe both encrypt and decrypt before any API create.
for environment in banditlair staging production; do
	target_for "$environment"
	recipients
	while IFS= read -r fingerprint; do
		gpg --batch --no-auto-key-retrieve --list-keys "$fingerprint" >/dev/null 2>&1 || fail 'public recipient key unavailable; import destination public keys before enrollment'
	done < <(printf '%s\n' "$pgp" | tr ',' '\n')
	sops decrypt "$target" >/dev/null 2>&1 || fail 'cannot unlock destination ciphertext'
	probe=$(printf '{"probe":"synthetic"}' | sops --config /dev/null encrypt --input-type json --output-type json \
		--filename-override probe.json --pgp "$pgp" 2>/dev/null) || fail 'cannot encrypt with destination recipients'
	[[ $(printf '%s' "$probe" | sops decrypt --input-type json --output-type json /dev/stdin 2>/dev/null | jq -r .probe) == synthetic ]] || fail 'recipient round-trip failed'
done
public_repo=$repo/telemetry-enrollment.json
public_infra=$infra/telemetry-enrollment.json
for file in "$public_repo" "$public_infra"; do
	[[ ! -L $file ]] || fail 'manifest symlink'
done
# Capture hashes at read time, not immediately before write.
fingerprint() { if [[ -e $1 ]]; then sha256sum "$1" | cut -d ' ' -f1; else printf 'absent'; fi; }
repo_hash=$(fingerprint "$public_repo")
infra_hash=$(fingerprint "$public_infra")

tmpdir=$(mktemp -d) || fail 'cannot allocate SSH socket directory'
[[ $(stat -c %a "$tmpdir") == 700 ]] || fail 'insecure SSH socket directory'
socket=$tmpdir/api.sock control=$tmpdir/control
tunnel_started=false
cipher_tmp='' manifest_tmp=''
cleanup() {
	if [[ $tunnel_started == true ]]; then
		ssh -F /dev/null -S "$control" -O exit "$gateway" >/dev/null 2>&1 || :
	fi
	[[ -z $cipher_tmp ]] || rm -f -- "$cipher_tmp" 2>/dev/null || :
	[[ -z $manifest_tmp ]] || rm -f -- "$manifest_tmp" 2>/dev/null || :
	rm -f -- "$socket" "$control" "$tmpdir/control.old" 2>/dev/null || :
	rmdir -- "$tmpdir" 2>/dev/null || :
}
trap cleanup EXIT
ssh -F /dev/null -f -N -M -S "$control" -o BatchMode=yes -o StrictHostKeyChecking=yes \
	-o ExitOnForwardFailure=yes -o ForwardAgent=no -o ProxyCommand=none -o ProxyJump=none \
	-L "$socket:127.0.0.1:3003" -- "$gateway" >/dev/null || fail 'SSH tunnel failed; check known_hosts and default identity or SSH agent'
tunnel_started=true
ssh -F /dev/null -S "$control" -O check "$gateway" >/dev/null 2>&1 || fail 'SSH tunnel is not controlled by this process'
[[ -S $socket ]] || fail 'SSH socket is not ready'
health=$(curl --disable --silent --noproxy '*' --unix-socket "$socket" --proto '=http' \
	--max-time 10 --output /dev/null -w '%{http_code}' 'http://localhost/v1/' 2>/dev/null) || fail 'SSH API health request failed'
[[ $health == 2* ]] || fail 'SSH API health request was not successful'
[[ -r /dev/tty ]] || fail 'a controlling terminal is required'
printf 'Pangolin administrative API key (id.secret): ' >/dev/tty
IFS= read -r -s api_key </dev/tty || fail 'unable to read API key'
printf '\n' >/dev/tty
[[ $api_key =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || fail 'invalid API key format'
api() {
	local method=$1 path=$2 payload=${3-} result
	local -a body=()
	[[ $method != PUT ]] || body=(--data-binary @-)
	result=$(printf '%s' "$payload" | curl --disable --silent --noproxy '*' --proto '=http' \
		--max-redirs 0 --retry 0 --connect-timeout 5 --max-time 25 --unix-socket "$socket" \
		--config /dev/fd/3 -X "$method" "${body[@]}" -H 'Content-Type: application/json' \
		-w '\n%{http_code}' "http://localhost$path" \
		3< <(printf 'header = "Authorization: Bearer %s"\n' "$api_key") 2>/dev/null) || fail "API transport failure ($method); pending intent must be reconciled"
	status=${result##*$'\n'}
	response=${result%$'\n'*}
	[[ $status == 2* ]] || fail "API rejected $method (HTTP $status); pending intent must be reconciled"
	jq -e . <<<"$response" >/dev/null 2>&1 || fail 'invalid API JSON'
}
api GET "/v1/org/$org"
utility=$(jq -er '.data.org.utilitySubnet|select(type=="string")' <<<"$response") || fail 'missing utility subnet'
[[ $utility =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/([0-9]+)$ ]] || fail 'invalid utility subnet'
a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]} prefix=${BASH_REMATCH[5]}
for octet in "$a" "$b" "$c" "$d"; do
	if ! [[ $octet =~ ^(0|[1-9][0-9]{0,2})$ ]] || ! ((octet <= 255)); then
		fail 'invalid IPv4 octet'
	fi
done
if ! [[ $prefix =~ ^(0|[1-9][0-9]?)$ ]] || ! ((prefix >= 1 && prefix <= 30)); then
	fail 'invalid utility prefix'
fi
base=$(((a << 24) | (b << 16) | (c << 8) | d))
(((base & ((0xffffffff << (32 - prefix)) & 0xffffffff)) == base)) || fail 'noncanonical utility subnet'
dns=$a.$b.$c.$((d + 1))
list_clients() {
	local page=1 total=0 pagesize=100 data
	clients='[]'
	while :; do
		api GET "/v1/org/$org/clients?page=$page&pageSize=100&status=active,blocked,archived"
		data=$response
		jq -e --argjson page "$page" '.data.clients|type=="array"' <<<"$data" >/dev/null 2>&1 || fail 'invalid client list'
		jq -e --argjson page "$page" '.data.pagination|.page==$page and .pageSize==100 and (.total|type=="number" and .>=0)' <<<"$data" >/dev/null 2>&1 || fail 'invalid pagination'
		total=$(jq -r .data.pagination.total <<<"$data")
		clients=$(jq -cn --slurpfile a <(printf '%s' "$clients") --slurpfile b <(jq -c .data.clients <<<"$data") '$a[0]+$b[0]')
		((page * pagesize >= total)) && break
		((page++))
		((page <= 10000)) || fail 'pagination limit exceeded'
	done
}
save_intent() {
	local file=$1 value=$2 phase=$3 tmp
	tmp=$(mktemp "$state_dir/.checkpoint.XXXXXXXX") || fail 'cannot stage checkpoint'
	cipher_tmp=$tmp
	if ! printf '%s' "$value" | jq -c --arg phase "$phase" '.phase=$phase' |
		sops --config /dev/null encrypt --input-type json --output-type json --filename-override checkpoint.json --pgp "$pgp" >"$tmp" 2>/dev/null; then
		rm -f -- "$tmp"
		fail 'checkpoint encryption failed'
	fi
	sync -f "$tmp" || fail 'checkpoint staging sync failed; no PUT sent'
	mv -- "$tmp" "$file" || fail 'checkpoint save failed'
	cipher_tmp=
	if ! sync -f "$file" || ! sync -f "$state_dir"; then
		fail 'checkpoint sync failed; no PUT sent'
	fi
}
read_leaf() {
	# A failed extraction is NOT evidence of absence until the MAC has been checked.
	if ! leaf=$(sops decrypt --extract "$index" "$target" 2>/dev/null); then
		sops decrypt "$target" >/dev/null 2>&1 || fail 'destination decryption failed; existing credential cannot be treated as absent'
		leaf=
	fi
	if [[ -n $leaf ]]; then
		leaf=$(jq -Sce 'if type=="string" then fromjson else . end | select(type=="object" and (.id|type)=="string" and (.secret|type)=="string") | {id,secret}' <<<"$leaf" 2>/dev/null) || fail 'invalid existing credential leaf'
	fi
}
publish_leaf() {
	local initial tmp
	initial=$(fingerprint "$target")
	read_leaf
	if [[ -n $leaf ]]; then
		[[ $leaf == "$credential" ]] || fail 'different credential already published; manual reconciliation required'
		return
	fi
	tmp=$(mktemp "$(dirname "$target")/.telemetry.XXXXXXXX") || fail 'cannot stage ciphertext'
	cipher_tmp=$tmp
	cp -- "$target" "$tmp"
	if ! printf '%s' "$credential" | jq -Rc . | sops set --input-type yaml --output-type yaml \
		--value-stdin --idempotent "$tmp" "$index" >/dev/null 2>&1; then
		rm -f -- "$tmp"
		fail 'SOPS ciphertext update failed'
	fi
	[[ $(fingerprint "$target") == "$initial" ]] || {
		rm -f -- "$tmp"
		fail 'destination changed concurrently'
	}
	chmod --reference="$target" "$tmp"
	mv -- "$tmp" "$target" || fail 'ciphertext publish failed'
	cipher_tmp=
	sync -f "$target" || fail 'ciphertext sync failed'
}
manifest=$(jq -cn --arg org "$org" --arg subnet "$utility" --arg dns "$dns" \
	'{schemaVersion:1,orgId:$org,endpoint:"https://pangolin.banditlair.com",utilitySubnet:$subnet,dnsAddress:$dns,machines:{}}')
for row in "${rows[@]}"; do
	host=$(jq -r .host <<<"$row")
	name=$(jq -r .name <<<"$row")
	environment=$(jq -r .environment <<<"$row")
	role=$(jq -r .role <<<"$row")
	secret_key=$(jq -r .secretKey <<<"$row")
	target_for "$(jq -r .environment <<<"$row")"
	recipients
	index=$(jq -rn --arg host "$host" '["telemetry","clients",$host]|map("["+tojson+"]")|join("")')
	pending=$state_dir/$host.json
	[[ ! -L $pending ]] || fail 'checkpoint symlink'
	[[ ! -e $pending || (-f $pending && -O $pending && $(stat -c %a "$pending") == 600) ]] || fail 'unsafe checkpoint'
	read_leaf
	if [[ -f $pending ]]; then
		intent=$(sops decrypt --input-type json --output-type json "$pending" 2>/dev/null) || fail 'checkpoint decryption failed'
		jq -e --arg org "$org" --arg host "$host" --arg name "$name" --arg gateway "$gateway" \
			--arg environment "$environment" --arg role "$role" --arg secretKey "$secret_key" \
			--arg repo "$repo" --arg infra "$infra" \
			'.org==$org and .host==$host and .name==$name and .environment==$environment and .role==$role and
       .secretKey==$secretKey and .gateway==$gateway and .repo==$repo and .infra==$infra and
       (.id|type)=="string" and (.secret|type)=="string" and (.subnet|type)=="string" and (.phase|IN("prepared","attempted"))' \
			<<<"$intent" >/dev/null 2>&1 || fail 'checkpoint binding mismatch; preserve the encrypted checkpoint and reconcile manually'
		credential=$(jq -Sc '{id,secret}' <<<"$intent")
		[[ -z $leaf || $leaf == "$credential" ]] || fail 'checkpoint conflicts with published credential'
	elif [[ -n $leaf ]]; then
		credential=$leaf
	else
		list_clients
		[[ $(jq -r --arg name "$name" '[.[]|select(.name==$name)]|length' <<<"$clients") == 0 ]] || fail "foreign same-name client: $host"
		api GET "/v1/org/$org/pick-client-defaults"
		intent=$(jq -ce --arg org "$org" --arg host "$host" --arg name "$name" \
			--arg gateway "$gateway" --arg repo "$repo" --arg infra "$infra" \
			--arg environment "$environment" --arg role "$role" --arg secretKey "$secret_key" \
			'.data|select((.olmId|type)=="string" and (.olmId|length)>0 and (.olmSecret|type)=="string" and (.olmSecret|length)>0 and (.subnet|type)=="string")|
       {org:$org,host:$host,name:$name,environment:$environment,role:$role,secretKey:$secretKey,
        gateway:$gateway,repo:$repo,infra:$infra,id:.olmId,secret:.olmSecret,subnet,phase:"prepared"}' \
			<<<"$response" 2>/dev/null) || fail 'invalid client defaults'
		ip=$(jq -r .subnet <<<"$intent")
		[[ $ip =~ ^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$ ]] || fail 'invalid client subnet'
		IFS=. read -r x y z w <<<"$ip"
		((x <= 255 && y <= 255 && z <= 255 && w <= 255)) || fail 'invalid client subnet'
		credential=$(jq -Sc '{id,secret}' <<<"$intent")
		save_intent "$pending" "$intent" prepared
	fi
	list_clients
	matches=$(jq -c --arg name "$name" '[.[]|select(.name==$name)]' <<<"$clients")
	[[ $(jq -r length <<<"$matches") -le 1 ]] || fail "duplicate client name: $host"
	if [[ $(jq -r length <<<"$matches") == 0 ]]; then
		[[ -f $pending ]] || fail "published credential has no client: $host"
		phase=$(jq -r .phase <<<"$intent")
		[[ $phase == prepared ]] || fail "ambiguous attempted creation: $host; manual reconciliation required"
		save_intent "$pending" "$intent" attempted
		payload=$(jq -c '{name,type:"olm",olmId:.id,secret,subnet}' <<<"$intent")
		api PUT "/v1/org/$org/client" "$payload"
		[[ $status == 201 ]] || fail 'create response not 201; reconcile manually'
		jq -e --arg id "$(jq -r .id <<<"$intent")" '.data.olmId==$id and (.data.clientId|type)=="number"' <<<"$response" >/dev/null 2>&1 || fail 'create response identity mismatch'
		list_clients
		matches=$(jq -c --arg name "$name" '[.[]|select(.name==$name)]' <<<"$clients")
		[[ $(jq -r length <<<"$matches") == 1 ]] || fail 'created client absent or ambiguous; reconcile manually'
	fi
	client_id=$(jq -er '.[0].clientId|select(type=="number")' <<<"$matches") || fail 'missing client ID'
	api GET "/v1/client/$client_id"
	expected=$(jq -r .id <<<"$credential")
	jq -e --arg id "$expected" --arg name "$name" --argjson client "$client_id" \
		'.data.olmId==$id and .data.name==$name and .data.clientId==$client' <<<"$response" >/dev/null 2>&1 || fail "foreign client identity: $host"
	nice=$(jq -er '.data.niceId|select(type=="string")' <<<"$response") || fail 'missing nice ID'
	publish_leaf
	entry=$(jq -cn --argjson row "$row" --argjson id "$client_id" --arg nice "$nice" --arg olm "$expected" \
		'{clientId:$id,niceId:$nice,olmId:$olm,name:$row.name,environment:$row.environment,role:$row.role,secretKey:$row.secretKey}')
	manifest=$(jq -cn --argjson m "$manifest" --arg host "$host" --argjson entry "$entry" '$m|.machines[$host]=$entry')
	printf 'Verified %s\n' "$host"
done
publish_manifest() {
	local file=$1 original=$2 old tmp
	[[ $(fingerprint "$file") == "$original" ]] || fail 'manifest changed concurrently'
	if [[ -f $file ]]; then
		old=$(jq -c . "$file") || fail 'invalid existing manifest'
		[[ $old != "$manifest" ]] || return 0
		if [[ $old != '{}' ]]; then
			jq -e --argjson desired "$manifest" '
        .schemaVersion==$desired.schemaVersion and .orgId==$desired.orgId and
        .endpoint==$desired.endpoint and .utilitySubnet==$desired.utilitySubnet and
        .dnsAddress==$desired.dnsAddress and (.machines|type)=="object" and
        (.machines|to_entries|all(.[]; $desired.machines[.key]==.value))
      ' <<<"$old" >/dev/null 2>&1 || fail 'conflicting existing manifest'
		fi
	fi
	tmp=$(mktemp "$(dirname "$file")/.telemetry-manifest.XXXXXXXX") || fail 'cannot stage manifest'
	manifest_tmp=$tmp
	printf '%s\n' "$manifest" >"$tmp"
	[[ $(fingerprint "$file") == "$original" ]] || {
		rm -f -- "$tmp"
		fail 'manifest changed concurrently'
	}
	chmod 644 "$tmp"
	mv -- "$tmp" "$file" || fail 'manifest publish failed'
	manifest_tmp=
	sync -f "$file" || fail 'manifest sync failed'
}
publish_manifest "$public_repo" "$repo_hash"
publish_manifest "$public_infra" "$infra_hash"
printf 'Enrollment complete: published non-secret manifests in both repositories.\n'
