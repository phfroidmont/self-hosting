#!/usr/bin/env python3
"""PTY-driven synthetic enrollment regression suite; never contacts real services."""
import base64
import fcntl
import json
import os
import pathlib
import pty
import shutil
import subprocess
import sys
import tempfile
import termios

root = pathlib.Path(sys.argv[1])
mock = root / 'tests/fixtures/pangolin-enroll/mock.py'
SENTINEL = 'syntheticSecretNeverPublish123'
real_sops = shutil.which('sops')
real_python = sys.executable
real_jq = shutil.which('jq')


def cipher(data):
    return {'sops': {'pgp': [{'fp': 'A' * 40}]},
            'ciphertext': base64.b64encode(json.dumps(data).encode()).decode()}


def plain(path):
    return json.loads(base64.b64decode(json.loads(path.read_text())['ciphertext']))


def setup(tmp):
    repo = tmp / 'repo'
    infra = tmp / 'infra'
    binpath = tmp / 'bin'
    for path in [repo / 'scripts', repo / 'state', infra / 'environments/staging',
                 infra / 'environments/production', binpath]:
        path.mkdir(parents=True, exist_ok=True)
    (repo / 'state').chmod(0o700)
    shutil.copy(root / 'scripts/pangolin-enroll-telemetry.sh', repo / 'scripts/pangolin-enroll-telemetry.sh')
    shutil.copy(root / 'telemetry-inventory.json', repo / 'telemetry-inventory.json')
    (repo / 'telemetry-inventory.json').chmod(0o600)
    for path in [repo / 'secrets.enc.yml', infra / 'environments/staging/secrets-staging.yaml',
                 infra / 'environments/production/secrets-production.yaml']:
        path.write_text(json.dumps(cipher({'unrelated': {'keep': 'synthetic-other'}})))
    for tool in ['ssh', 'curl', 'sops', 'jq', 'gpg']:
        executable = binpath / tool
        executable.write_text(f'#!/bin/sh\nexec "{real_python}" "{mock}" {tool} "$@"\n')
        executable.chmod(0o755)
    env = dict(os.environ, MOCK_ROOT=str(tmp), REAL_JQ=real_jq,
               PATH=str(binpath) + ':' + os.environ['PATH'])
    return repo, infra, env


def run(tmp, repo, infra, env, action='enroll', key='synthetic.idSecret', extra=()):
    args = ['bash', str(repo / 'scripts/pangolin-enroll-telemetry.sh'), action, '--org', 'demo',
            '--infrastructure-repo', str(infra), '--state-dir', str(repo / 'state'), *extra]
    master, slave = pty.openpty()

    def tty():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(args, env=env, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=tty)
    os.close(slave)
    # Feed only after the hidden prompt is actually written to the controlling terminal.
    prompt = b''
    if action == 'enroll' and '--api-key' not in extra:
        import select
        for _ in range(200):
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    prompt += os.read(master, 4096)
                except OSError:
                    break
            if b'API key (id.secret): ' in prompt:
                os.write(master, (key + '\n').encode())
                break
            if proc.poll() is not None:
                break
        else:
            proc.kill()
            raise AssertionError('no hidden prompt')
    out, err = proc.communicate(timeout=150)
    os.close(master)
    combined = prompt + out + err
    assert SENTINEL.encode() not in combined, combined
    assert key.encode() not in combined, combined
    assert b'WRONG_AUTH_BODY' not in combined, combined
    return proc.returncode, combined.decode(errors='replace')


def mode(tmp, **opts):
    (tmp / 'mode.json').write_text(json.dumps(opts))


def counts(tmp):
    return json.loads((tmp / 'api.json').read_text()) if (tmp / 'api.json').exists() else {'puts': 0}


with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    status, output = run(tmp, repo, infra, env, 'check')
    assert status == 0, output
    assert not (tmp / 'api.json').exists()
    status, output = run(tmp, repo, infra, env, extra=('--api-key', SENTINEL))
    assert status != 0 and not (tmp / 'api.json').exists(), output
    status, output = run(tmp, repo, infra, env, extra=('--local-port', '33003'))
    assert status != 0 and not (tmp / 'api.json').exists(), output
    status, output = run(tmp, repo, infra, env)
    assert status == 0, output
    assert counts(tmp)['puts'] == 15
    manifest = json.loads((repo / 'telemetry-enrollment.json').read_text())
    assert manifest == json.loads((infra / 'telemetry-enrollment.json').read_text())
    assert len(manifest['machines']) == 15 and SENTINEL not in json.dumps(manifest)
    for dest in [repo / 'secrets.enc.yml', infra / 'environments/staging/secrets-staging.yaml',
                 infra / 'environments/production/secrets-production.yaml']:
        assert SENTINEL not in dest.read_text()
        assert plain(dest)['unrelated'] == {'keep': 'synthetic-other'}
    assert all('ciphertext' in f.read_text() and SENTINEL not in f.read_text()
               for f in (repo / 'state').glob('*.json'))
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    # Equivalent JSON key ordering must not be mistaken for a changed credential.
    central = repo / 'secrets.enc.yml'
    central_plain = plain(central)
    hel1 = json.loads(central_plain['telemetry']['clients']['hel1'])
    central_plain['telemetry']['clients']['hel1'] = json.dumps({'secret': hel1['secret'], 'id': hel1['id']})
    central.write_text(json.dumps(cipher(central_plain)))
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    # Lost local checkpoint, published ciphertext and server identity still recover.
    (repo / 'state/hel1.json').unlink()
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    print('success15 / exact empty pagination / no-op / lost checkpoint / preservation: PASS')
    inventory_path = repo / 'telemetry-inventory.json'
    inventory = json.loads(inventory_path.read_text())
    inventory_path.write_text(json.dumps(inventory, indent=4))
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    inventory['machines'].append({'host': 'backend3-staging', 'environment': 'staging',
                                  'role': 'backend', 'name': 'osteoview-backend3-staging-logs',
                                  'secretKey': 'telemetry/clients/backend3-staging'})
    inventory_path.write_text(json.dumps(inventory))
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 16, output
    assert len(json.loads((repo / 'telemetry-enrollment.json').read_text())['machines']) == 16
    print('format-only inventory change / future host addition: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, lost=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1 and (repo / 'state/hel1.json').exists(), output
    assert not (repo / 'telemetry-enrollment.json').exists()
    mode(tmp)
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    print('committed create / lost response / GET identity recovery / no second PUT: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, no_commit=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1, output
    mode(tmp)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1 and 'manual reconciliation' in output, output
    print('ambiguous zero-match conservatively halts: PASS')

for scenario in ('foreign', 'auth401'):
    with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
        tmp = pathlib.Path(temp)
        repo, infra, env = setup(tmp)
        mode(tmp, **{scenario: True})
        status, output = run(tmp, repo, infra, env)
        assert status != 0 and counts(tmp)['puts'] == 0, output
        print(scenario + ' stops without PUT or body disclosure: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    status, output = run(tmp, repo, infra, env, key='synthetic.wrongSecret')
    assert status != 0 and counts(tmp)['puts'] == 0 and '401' in output, output
    print('wrong administrative key rejects without leaking HTTP body: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, lost=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1, output
    state = counts(tmp)
    state['clients'].append({**state['clients'][0], 'clientId': 999})
    (tmp / 'api.json').write_text(json.dumps(state))
    mode(tmp)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1 and 'duplicate' in output, output
    print('duplicate same-name clients halt without second PUT: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, missing_public_key=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 0 and 'public recipient key unavailable' in output, output
    print('missing public recipient preflight halts before creation: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, encrypt_fail=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 0, output
    print('recipient encryption failure before creation: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, fail_encrypt_number=5)  # 3 destination probes, prepared checkpoint, attempted checkpoint
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 0 and (repo / 'state/hel1.json').exists(), output
    assert plain(repo / 'state/hel1.json')['phase'] == 'prepared'
    mode(tmp)
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    print('prepared checkpoint before PUT, failed encryption, safe resume: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    mode(tmp, set_fail_once=True)
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 1 and not (repo / 'telemetry-enrollment.json').exists(), output
    mode(tmp)
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    print('partial ciphertext publish resumes without duplicate PUT: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    infra_manifest = infra / 'telemetry-enrollment.json'
    infra_manifest.write_text('{"unexpected":"synthetic"}\n')
    status, output = run(tmp, repo, infra, env)
    assert status != 0 and counts(tmp)['puts'] == 15 and (repo / 'telemetry-enrollment.json').exists(), output
    infra_manifest.write_text('{}\n')
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    assert json.loads((repo / 'telemetry-enrollment.json').read_text()) == json.loads(infra_manifest.read_text())
    print('partial cross-repository manifest publish recovers: PASS')

with tempfile.TemporaryDirectory(prefix='pangolin-synthetic-') as temp:
    tmp = pathlib.Path(temp)
    repo, infra, env = setup(tmp)
    api_state = {'clients': [{'clientId': i + 100, 'niceId': f'unrelated-{i}',
                              'olmId': f'unrelated-id-{i}', 'name': f'unrelated-{i}'}
                             for i in range(101)], 'puts': 0}
    (tmp / 'api.json').write_text(json.dumps(api_state))
    status, output = run(tmp, repo, infra, env)
    assert status == 0 and counts(tmp)['puts'] == 15, output
    print('pagination with >100 existing clients: PASS')

# Isolated REAL SOPS encryption round trip with throwaway synthetic GPG identity.
with tempfile.TemporaryDirectory(prefix='pangolin-gpg-synthetic-') as temp:
    home = pathlib.Path(temp)
    home.chmod(0o700)
    (home / '.sops.yaml').write_text('creation_rules:\n  - path_regex: ^never-matches-this-document$\n    pgp: ' + 'B' * 40 + '\n')
    gpg_env = dict(os.environ, GNUPGHOME=str(home))
    subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                    '--quick-generate-key', 'Synthetic Telemetry Test <synthetic@example.invalid>',
                    'default', 'default', '0'], env=gpg_env, capture_output=True, check=True)
    fingerprints = subprocess.check_output(['gpg', '--with-colons', '--list-keys'], env=gpg_env, text=True)
    fp = next(line.split(':')[9] for line in fingerprints.splitlines() if line.startswith('fpr:'))
    content = '{"telemetry":{"clients":{"test":"{\\"id\\":\\"synthetic-id\\",\\"secret\\":\\"synthetic-secret\\"}"}}}'
    blocked = subprocess.run([real_sops, 'encrypt', '--input-type', 'json', '--output-type', 'json',
                              '--filename-override', 'test.json', '--pgp', fp], input=content,
                             text=True, capture_output=True, env=gpg_env, cwd=home)
    assert blocked.returncode != 0  # The fixture .sops.yaml really rejects this path.
    encrypted_result = subprocess.run([real_sops, '--config', '/dev/null', 'encrypt', '--input-type', 'json', '--output-type', 'json',
                                       '--filename-override', 'test.json', '--pgp', fp], input=content,
                                      text=True, capture_output=True, env=gpg_env, cwd=home)
    assert encrypted_result.returncode == 0, encrypted_result.stderr
    encrypted = encrypted_result.stdout
    decrypted = subprocess.run([real_sops, 'decrypt', '--input-type', 'json', '--output-type', 'json', '/dev/stdin'],
                               input=encrypted, text=True, capture_output=True, env=gpg_env, check=True).stdout
    value = json.loads(decrypted)['telemetry']['clients']['test']
    assert isinstance(value, str) and json.loads(value) == {'id': 'synthetic-id', 'secret': 'synthetic-secret'}
    yaml_cipher = subprocess.run([real_sops, '--config', '/dev/null', 'encrypt', '--input-type', 'yaml',
                                  '--output-type', 'yaml', '--filename-override', 'synthetic.yaml', '--pgp', fp],
                                 input='unrelated: synthetic-other\n', text=True, capture_output=True,
                                 env=gpg_env, cwd=home, check=True).stdout
    dest = home / 'synthetic.yaml'
    dest.write_text(yaml_cipher)
    set_result = subprocess.run([real_sops, 'set', '--input-type', 'yaml', '--output-type', 'yaml',
                                 '--value-stdin', '--idempotent', str(dest), '["telemetry"]["clients"]["test"]'],
                                input=json.dumps(value), text=True, capture_output=True, env=gpg_env)
    assert set_result.returncode == 0, set_result.stderr
    extracted = subprocess.run([real_sops, 'decrypt', '--extract', '["telemetry"]["clients"]["test"]',
                                str(dest)], text=True, capture_output=True, env=gpg_env, check=True).stdout
    assert json.loads(extracted) == json.loads(value)
    unrelated = subprocess.run([real_sops, 'decrypt', '--extract', '["unrelated"]', str(dest)],
                               text=True, capture_output=True, env=gpg_env, check=True).stdout
    assert unrelated.strip() == 'synthetic-other'
    print('isolated real SOPS JSON string and YAML set round trip: PASS')
