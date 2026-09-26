#!/usr/bin/env bash
# Run locally by an operator with their own SOPS private key; never in CI.
set +x
set -euo pipefail
umask 077
ulimit -c 0

fail() {
	printf 'Telemetry alert preparation stopped: %s\n' "$1" >&2
	exit 1
}
usage() { fail 'usage: prepare-telemetry-alerts.sh check|prepare --infrastructure-repo PATH [--state-dir PATH]'; }
(($#)) || usage
action=$1
shift
[[ $action == check || $action == prepare ]] || usage
infra='' state_dir=''
while (($#)); do
	(($# >= 2)) || usage
	case $1 in
	--infrastructure-repo) infra=$2 ;;
	--state-dir) state_dir=$2 ;;
	*) usage ;;
	esac
	shift 2
done
[[ -n $infra && -d $infra ]] || usage
for tool in python3 sops gpg openssl flock mktemp yq; do
	command -v "$tool" >/dev/null || fail "missing dependency: $tool"
done
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
infra=$(cd -- "$infra" && pwd -P)
stage=$infra/environments/staging/secrets-staging.yaml
prod=$infra/environments/production/secrets-production.yaml
target=$repo/secrets/telemetry-alerts.enc.yml
public=$repo/telemetry-alerting.json
recipients=(3AC6F170F01133CE393BCD94BE948AFD7E7873BE 0F0C4C2F9877CB8A53EFADACB90613A2AF502673 515A19EF3F9B98442331D89B2997D83EE1948D54)
[[ -d $repo/secrets && ! -L $repo/secrets ]] || fail 'missing ciphertext directory'
[[ -f $stage && ! -L $stage && -f $prod && ! -L $prod ]] || fail 'missing source ciphertext'
[[ ! -L $target && ! -L $public ]] || fail 'output symlink refused'
for fingerprint in "${recipients[@]}"; do
	[[ $(gpg --batch --no-auto-key-retrieve --export "$fingerprint" 2>/dev/null | wc -c) -gt 0 ]] || fail 'recipient public key unavailable'
done
if [[ $action == check ]]; then
	printf 'Public recipient keys and source ciphertext paths available; no decryption or network access performed.\n'
	exit 0
fi

[[ -n $state_dir ]] || state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/prepare-telemetry-alerts
[[ ! -L $state_dir ]] || fail 'state directory symlink refused'
mkdir -p -- "$state_dir" || fail 'cannot create state directory'
state_dir=$(cd -- "$state_dir" && pwd -P)
[[ -O $state_dir && $(stat -c %a "$state_dir") == 700 ]] || fail 'state directory must be owned and mode 0700'
exec 9>"$state_dir/lock"
flock -n 9 || fail 'preparation already running'

# The public marker is published only after the ciphertext is durable. Never
# replace a previously prepared marker with an empty one on a failed rerun.
python3 - "$public" "$target" 2>/dev/null <<'PY' || fail 'unexpected public metadata'
import json, os, sys
marker, ciphertext = sys.argv[1:]
if os.path.exists(marker):
    with open(marker, encoding='utf-8') as stream:
        value = json.load(stream)
    assert value == {} or (os.path.isfile(ciphertext) and value == {'schemaVersion': 1, 'prepared': True})
PY

validate_bundle() {
	local file=$1
	# Validate the PUBLIC SOPS recipients before decrypting; even decryptable
	# ciphertext with an extra recipient must not enable the readiness marker.
	yq -o=json '.sops' "$file" 2>/dev/null | python3 -c '
import json, sys
try:
    meta = json.load(sys.stdin)
    expected = set(sys.argv[1].split(","))
    assert isinstance(meta, dict) and isinstance(meta.get("pgp"), list)
    assert len(meta["pgp"]) == len(expected)
    assert {entry["fp"].upper() for entry in meta["pgp"]} == expected
    assert all(not meta.get(key) for key in ("age", "kms", "gcp_kms", "azure_kv", "hc_vault", "key_groups"))
except (ValueError, TypeError, KeyError, AttributeError, AssertionError):
    sys.exit(1)
' "$pgp" 2>/dev/null || return 1
	sops decrypt --input-type yaml --output-type json "$file" 2>/dev/null | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
    assert isinstance(data, dict)
    assert set(data) == {"smtp", "recipients", "watchdog"}
    assert all(isinstance(data[key], dict) for key in data)
    assert set(data["smtp"]) == {"user", "password"}
    assert set(data["recipients"]) == {"staging", "production"}
    assert set(data["watchdog"]) == {"token", "monit_config"}
    assert all(isinstance(value, str) and value for group in data.values() for value in group.values())
    email = r"[A-Za-z0-9_+-]+(?:\.[A-Za-z0-9_+-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+"
    address = re.compile(r"(?:[A-Za-z][A-Za-z0-9 ._-]*\s*<(" + email + r")>|(" + email + r"))\Z")
    user = data["smtp"]["user"]
    password = data["smtp"]["password"]
    assert re.fullmatch(email, user)
    assert not re.search(r"[\x00-\x1f\x7f\"\\]", password)
    def addresses(value):
        assert not re.search(r"[\x00-\x09\x0b-\x1f\x7f]", value)
        matches = [address.fullmatch(item.strip()) for item in re.split(r"[;,\n]", value)]
        assert matches and all(matches)
        return [match.group(1) or match.group(2) for match in matches]
    addresses(data["recipients"]["staging"])
    recipients = addresses(data["recipients"]["production"])
    assert re.fullmatch(r"[0-9a-f]{64}", data["watchdog"]["token"])
    monit = ("set mailserver mail.your-server.de port 465 username \"" + user +
             "\" password \"" + password + "\" using ssl\n" +
             "set mail-format { from: " + user + " }\n" +
             "".join("set alert " + recipient + "\n" for recipient in recipients))
    assert data["watchdog"]["monit_config"] == monit
except (ValueError, TypeError, KeyError, AttributeError, AssertionError):
    sys.exit(1)
' 2>/dev/null
}
pgp=$(
	IFS=,
	printf '%s' "${recipients[*]}"
)
if [[ -e $target ]]; then
	[[ -f $target ]] || fail 'ciphertext path is not a file'
	# No token regeneration, source decryption, or overwrite on a rerun.
	validate_bundle "$target" || fail 'existing ciphertext cannot be validated; left untouched'
else
	tmp=$(mktemp "$repo/secrets/.telemetry-alerts.XXXXXXXX") || fail 'cannot create ciphertext temporary file'
	cleanup() { rm -f -- "$tmp"; }
	trap cleanup EXIT
	# Python reads decrypted JSON only from SOPS pipes in this process. Never
	# pass plaintext through argv, environment, or a temporary file.
	python3 /dev/fd/3 "$stage" "$prod" 3<<'PY' 2>/dev/null | sops --config /dev/null encrypt --input-type json --output-type yaml --filename-override secrets/telemetry-alerts.enc.yml --pgp "$pgp" /dev/stdin >"$tmp" 2>/dev/null || fail 'source verification, validation or encryption failed; no outputs published'
import json
import re
import subprocess
import sys

def source(path):
    result = subprocess.run(['sops', 'decrypt', '--output-type', 'json', path],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    return json.loads(result.stdout)['alerts']

def text(value):
    assert isinstance(value, str) and value and not re.search(r'[\x00-\x1f\x7f]', value)
    return value

email = r'[A-Za-z0-9_+-]+(?:\.[A-Za-z0-9_+-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+'
address = re.compile(r'(?:[A-Za-z][A-Za-z0-9 ._-]*\s*<(' + email + r')>|(' + email + r'))\Z')
def addresses(value):
    assert isinstance(value, str) and value and not re.search(r'[\x00-\x09\x0b-\x1f\x7f]', value)
    items = re.split(r'[;,\n]', value)
    # Newline is allowed only as a recipient separator, never in a Monit field.
    result = []
    for item in items:
        match = address.fullmatch(item.strip())
        assert match is not None
        result.append(match.group(1) or match.group(2))
    assert result
    return value, result

production = source(sys.argv[2])
staging = source(sys.argv[1])
user = text(production['user'])
password = text(production['smtp_password'])
assert re.fullmatch(email, user)
assert not re.search(r'["\\]', password)
staging_value, _ = addresses(staging['contact_point'])
production_value, production_addresses = addresses(production['contact_point'])
token = subprocess.run(['openssl', 'rand', '-hex', '32'], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, check=True).stdout.decode('ascii').strip()
assert re.fullmatch('[0-9a-f]{64}', token)
monit = ('set mailserver mail.your-server.de port 465 username "' + user +
         '" password "' + password + '" using ssl\n' +
         'set mail-format { from: ' + user + ' }\n' +
         ''.join('set alert ' + recipient + '\n' for recipient in production_addresses))
json.dump({'smtp': {'user': user, 'password': password},
           'recipients': {'staging': staging_value, 'production': production_value},
           'watchdog': {'token': token, 'monit_config': monit}}, sys.stdout)
PY
	[[ -s $tmp ]] || fail 'empty ciphertext'
	validate_bundle "$tmp" || fail 'encrypted bundle failed validation; no outputs published'
	# The hard link is exclusive: even an external writer cannot be overwritten.
	python3 - "$tmp" "$target" <<'PY' || fail 'ciphertext publication failed; existing file untouched'
import os, sys
temporary, target = sys.argv[1:]
with open(temporary, 'rb') as stream:
    os.fsync(stream.fileno())
os.link(temporary, target)
directory = os.open(os.path.dirname(target), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
fi

python3 - "$public" <<'PY' || fail 'ciphertext ready but public marker publication failed; rerun prepare'
import json, os, sys, tempfile
path = sys.argv[1]
directory = os.path.dirname(path)
fd, temporary = tempfile.mkstemp(prefix='.telemetry-alerting.', dir=directory)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump({'schemaVersion': 1, 'prepared': True}, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    handle = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(handle)
    finally:
        os.close(handle)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
printf 'Ciphertext ready; public preparation marker published. No deployment performed.\n'
