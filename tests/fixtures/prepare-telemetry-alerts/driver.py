"""Synthetic, disposable SOPS/GPG end-to-end test; no repository secrets read."""
from contextlib import ExitStack
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with ExitStack() as stack:
    base = Path(stack.enter_context(tempfile.TemporaryDirectory()))
    repo = base / 'self-hosting'
    infra = base / 'infrastructure'
    (repo / 'scripts').mkdir(parents=True)
    (repo / 'secrets').mkdir()
    for env_name in ('production', 'staging'):
        (infra / 'environments' / env_name).mkdir(parents=True)
    script = repo / 'scripts' / 'prepare-telemetry-alerts.sh'
    shutil.copyfile(root / 'scripts' / 'prepare-telemetry-alerts.sh', script)
    marker = repo / 'telemetry-alerting.json'
    marker.write_text('{}\n')
    home = base / 'gnupg'
    home.mkdir(mode=0o700)
    environment = {'PATH': os.environ['PATH'], 'GNUPGHOME': str(home), 'HOME': str(base),
                   'XDG_STATE_HOME': str(base / 'state'), 'LC_ALL': 'C'}
    stack.callback(lambda: subprocess.run(['gpgconf', '--homedir', str(home), '--kill', 'gpg-agent'],
                                          env=environment, stdout=subprocess.DEVNULL,
                                          stderr=subprocess.DEVNULL, check=False))

    def command(args, *, data=None, success=True):
        result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=environment)
        assert (result.returncode == 0) == success, (args[0], result.returncode, result.stderr[:300])
        return result

    keys = []
    for index in range(4):
        command(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
                 f'Synthetic {index} <synthetic{index}@example.test>', 'default', 'default', 'never'])
        result = command(['gpg', '--batch', '--with-colons', '--list-keys', f'synthetic{index}@example.test'])
        keys.append(re.search(rb'^fpr:+([A-F0-9]{40}):', result.stdout, re.M).group(1).decode())
    source = script.read_text()
    originals = ['3AC6F170F01133CE393BCD94BE948AFD7E7873BE',
                 '0F0C4C2F9877CB8A53EFADACB90613A2AF502673',
                 '515A19EF3F9B98442331D89B2997D83EE1948D54']
    for old, new in zip(originals, keys):
        source = source.replace(old, new)
    script.write_text(source)

    def encrypt_payload(payload, path, recipient_keys):
        return command(['sops', '--config', '/dev/null', 'encrypt', '--input-type', 'json',
                        '--output-type', 'yaml', '--filename-override', str(path),
                        '--pgp', ','.join(recipient_keys), '/dev/stdin'], data=json.dumps(payload).encode()).stdout

    def encrypt_source(env_name, alerts):
        path = infra / 'environments' / env_name / f'secrets-{env_name}.yaml'
        path.write_bytes(encrypt_payload({'alerts': alerts, 'unrelated': 'must-not-be-copied'}, path, keys[:1]))
        return path

    staging = encrypt_source('staging', {'user': 'stage@example.test', 'smtp_password': 'stage-secret',
                                        'contact_point': 'Stage <stage-alert@example.test>,other@example.test\nthird@example.test'})
    production = encrypt_source('production', {'user': 'relay@example.test', 'smtp_password': 'synthetic-smtp-secret',
                                                'contact_point': 'Ops <ops@example.test>;pager@example.test'})
    args = ['bash', str(script), 'prepare', '--infrastructure-repo', str(infra)]
    assert 'synthetic-smtp-secret' not in repr(args) + repr(environment)
    check = command(['bash', str(script), 'check', '--infrastructure-repo', str(infra)])
    assert b'no decryption' in check.stdout and json.loads(marker.read_text()) == {}
    target = repo / 'secrets' / 'telemetry-alerts.enc.yml'

    # Reject injection before ciphertext/marker creation, without echoing input.
    encrypt_source('production', {'user': 'relay@example.test', 'smtp_password': 'bad\nset alert attacker@example.test',
                                  'contact_point': 'ops@example.test'})
    rejected = command(args, success=False)
    assert not target.exists() and json.loads(marker.read_text()) == {}
    assert b'attacker@example.test' not in rejected.stderr + rejected.stdout
    for password, recipient in [('bad"quote', 'ops@example.test'), ('bad\\slash', 'ops@example.test'),
                                ('valid-password', 'ops%tag@example.test'),
                                ('valid-password', 'ops@localhost')]:
        encrypt_source('production', {'user': 'relay@example.test', 'smtp_password': password,
                                      'contact_point': recipient})
        rejected = command(args, success=False)
        assert not target.exists() and json.loads(marker.read_text()) == {}
        assert recipient.encode() not in rejected.stdout + rejected.stderr
    encrypt_source('production', {'user': 'relay%tag@example.test', 'smtp_password': 'valid-password',
                                  'contact_point': 'ops@example.test'})
    command(args, success=False)
    assert not target.exists() and json.loads(marker.read_text()) == {}
    production.write_bytes(production.read_bytes().replace(b'mac: ENC[', b'mac: ENX[', 1))
    command(args, success=False)
    assert not target.exists() and json.loads(marker.read_text()) == {}
    encrypt_source('production', {'user': 'relay@example.test', 'smtp_password': 'valid-password',
                                  'contact_point': 'ops@example.test; set alert attacker@example.test'})
    rejected = command(args, success=False)
    assert not target.exists() and json.loads(marker.read_text()) == {}
    assert b'attacker@example.test' not in rejected.stderr + rejected.stdout
    encrypt_source('production', {'user': 'relay@example.test', 'smtp_password': 'synthetic-smtp-secret',
                                  'contact_point': 'Ops <ops@example.test>;pager@example.test'})

    prepared = command(args)
    assert b'synthetic-smtp-secret' not in prepared.stdout + prepared.stderr
    assert b'synthetic-smtp-secret' not in marker.read_bytes()
    assert json.loads(marker.read_text()) == {'schemaVersion': 1, 'prepared': True}
    assert b'synthetic-smtp-secret' not in target.read_bytes()
    metadata = json.loads(command(['yq', '-o=json', '.sops', str(target)]).stdout)
    assert {recipient['fp'].upper() for recipient in metadata['pgp']} == set(keys[:3])
    assert len(metadata['pgp']) == 3
    original = target.read_bytes()
    decoded = json.loads(command(['sops', 'decrypt', '--output-type', 'json', str(target)]).stdout)
    assert set(decoded) == {'smtp', 'recipients', 'watchdog'}
    assert decoded['smtp'] == {'user': 'relay@example.test', 'password': 'synthetic-smtp-secret'}
    assert decoded['recipients'] == {'staging': 'Stage <stage-alert@example.test>,other@example.test\nthird@example.test',
                                     'production': 'Ops <ops@example.test>;pager@example.test'}
    assert re.fullmatch('[0-9a-f]{64}', decoded['watchdog']['token'])
    assert decoded['watchdog']['monit_config'] == (
        'set mailserver mail.your-server.de port 465 username "relay@example.test" '
        'password "synthetic-smtp-secret" using ssl\n'
        'set mail-format { from: relay@example.test }\n'
        'set alert ops@example.test\nset alert pager@example.test\n')
    if shutil.which('monit', path=environment['PATH']):
        # Only synthetic values reach this disposable Monit configuration.
        config = base / 'synthetic.monitrc'
        config.write_text(decoded['watchdog']['monit_config'])
        config.chmod(0o600)
        command(['monit', '-t', '-c', str(config)])
    staging_before, production_before = staging.read_bytes(), production.read_bytes()
    command(args)
    assert target.read_bytes() == original
    assert staging.read_bytes() == staging_before and production.read_bytes() == production_before
    assert json.loads(command(['sops', 'decrypt', '--output-type', 'json', str(target)]).stdout)['watchdog']['token'] == decoded['watchdog']['token']
    # A partial publish (ciphertext present, marker still {}) is recoverable.
    marker.write_text('{}\n')
    command(args)
    assert target.read_bytes() == original and json.loads(marker.read_text())['prepared'] is True
    # Reject decryptable, MAC-valid ciphertext with extra recipients or a
    # modified Monit directive; do not publish a partial {} marker.
    marker.write_text('{}\n')
    for recipient_keys, payload in [(keys, decoded),
                                     (keys[:3], {**decoded, 'watchdog': {
                                         **decoded['watchdog'],
                                         'monit_config': decoded['watchdog']['monit_config'] + 'set alert attacker@example.test\n'}}),
                                     (keys[:3], {**decoded, 'smtp': {
                                         **decoded['smtp'], 'password': 'unsafe"password'}})]:
        altered = encrypt_payload(payload, target, recipient_keys)
        target.write_bytes(altered)
        rejected = command(args, success=False)
        assert target.read_bytes() == altered and json.loads(marker.read_text()) == {}
        assert b'attacker@example.test' not in rejected.stdout + rejected.stderr
    target.write_bytes(original)
    command(args)
    assert target.read_bytes() == original and json.loads(marker.read_text())['prepared'] is True
    # A corrupt existing bundle is never overwritten or rotated.
    target.write_bytes(b'not sops ciphertext\n')
    rejected = command(args, success=False)
    assert target.read_bytes() == b'not sops ciphertext\n'
    assert b'synthetic-smtp-secret' not in rejected.stdout + rejected.stderr
    assert json.loads(marker.read_text())['prepared'] is True
    print('synthetic telemetry alert preparation: passed')
