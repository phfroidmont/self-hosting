#!/usr/bin/env python3
"""Offline mock executable for sops, ssh and curl; synthetic data only."""
import base64
import json
import os
import pathlib
import re
import sys
from urllib.parse import urlsplit, parse_qs

args = sys.argv[1:]
root = pathlib.Path(os.environ['MOCK_ROOT'])
name = pathlib.Path(sys.argv[0]).name
if name == 'mock.py' and args and args[0] in {'ssh', 'curl', 'sops', 'jq', 'gpg'}:
    name = args.pop(0)
sentinel = 'syntheticSecretNeverPublish123'


def record():
    # Refuse a plaintext secret in argv/environment (before recording anything).
    if sentinel in repr(args) or sentinel in repr(dict(os.environ)):
        sys.exit(91)


def store(path, value):
    path.write_text(json.dumps(value))


def load(path, fallback):
    return json.loads(path.read_text()) if path.exists() else fallback


record()
if name == 'jq':
    os.execv(os.environ['REAL_JQ'], [os.environ['REAL_JQ'], *args])

if name == 'gpg':
    if args[:3] != ['--batch', '--no-auto-key-retrieve', '--list-keys'] or args[3:] != ['A' * 40]:
        sys.exit(95)
    sys.exit(1 if load(root / 'mode.json', {}).get('missing_public_key') else 0)

if name == 'ssh':
    if '-O' in args:
        sys.exit(0)
    sock = pathlib.Path(args[args.index('-L') + 1].split(':127.0.0.1:3003')[0])
    sock.touch()  # Test shim: real SSH creates a UNIX socket.
    # The production code checks -S; simulate socket type with a real AF_UNIX bind.
    sock.unlink()
    import socket
    s = socket.socket(socket.AF_UNIX)
    s.bind(str(sock))
    s.close()
    sys.exit(0)

if name == 'sops':
    if args[:1] == ['--config']:
        args = args[2:]
    command = args[0]
    if command == 'encrypt':
        nfile = root / 'encrypt_count'
        number = int(nfile.read_text()) + 1 if nfile.exists() else 1
        nfile.write_text(str(number))
        settings = load(root / 'mode.json', {})
        if settings.get('encrypt_fail') or settings.get('fail_encrypt_number') == number:
            sys.exit(1)
        raw = sys.stdin.read()
        data = json.loads(raw)
        print(json.dumps({'sops': {'pgp': [{'fp': 'A' * 40}]},
                          'ciphertext': base64.b64encode(json.dumps(data).encode()).decode()}))
    elif command == 'decrypt':
        path = args[-1]
        doc = json.loads(sys.stdin.read() if path == '/dev/stdin' else pathlib.Path(path).read_text())
        data = json.loads(base64.b64decode(doc['ciphertext'])) if 'ciphertext' in doc else doc
        if '--extract' in args:
            keys = re.findall(r'\["([^"]+)"\]', args[args.index('--extract') + 1])
            for key in keys:
                if key not in data:
                    sys.exit(1)
                data = data[key]
        print(json.dumps(data))
    elif command == 'set':
        if load(root / 'mode.json', {}).get('set_fail_once') and not (root / 'set_failed').exists():
            (root / 'set_failed').touch()
            sys.exit(1)
        value = json.loads(sys.stdin.read())
        path = pathlib.Path(args[-2])
        keys = re.findall(r'\["([^"]+)"\]', args[-1])
        doc = json.loads(path.read_text())
        data = json.loads(base64.b64decode(doc['ciphertext']))
        node = data
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        node[keys[-1]] = value
        doc['ciphertext'] = base64.b64encode(json.dumps(data).encode()).decode()
        store(path, doc)
    else:
        sys.exit(2)
    sys.exit(0)

if name == 'curl':
    if '--unix-socket' not in args or '--retry' in args and args[args.index('--retry') + 1] != '0':
        sys.exit(92)
    url = args[-1]
    if url == 'http://localhost/v1/':
        print('200', end='')
        sys.exit(0)
    cfg = pathlib.Path('/dev/fd/3').read_text()
    if cfg != 'header = "Authorization: Bearer synthetic.idSecret"\n':
        print('{"private":"WRONG_AUTH_BODY"}\n401', end='')
        sys.exit(0)
    method = args[args.index('-X') + 1]
    urlparts = urlsplit(url)
    path = urlparts.path
    statefile = root / 'api.json'
    state = load(statefile, {'clients': [], 'puts': 0})
    mode = load(root / 'mode.json', {})
    data = {}
    status = 200
    if path == '/v1/org/demo':
        if mode.get('auth401'):
            print('{"private":"WRONG_AUTH_BODY"}\n401', end='')
            sys.exit(0)
        data = {'org': {'utilitySubnet': '100.96.0.0/24'}}
    elif path == '/v1/org/demo/clients':
        query = parse_qs(urlparts.query)
        page = int(query['page'][0])
        if mode.get('foreign') and not state['clients']:
            state['clients'].append({'clientId': 99, 'niceId': 'foreign', 'olmId': 'foreign', 'name': 'hel1-osteoview-metrics'})
        if mode.get('duplicate') and len(state['clients']) == 1:
            state['clients'].append({**state['clients'][0], 'clientId': 98})
        total = len(state['clients'])
        # Force multiple pages at two items even when requesting 100, but report actual pageSize 100?
        # Pagination contract pageSize=100: inject 101 foreign unrelated clients for multipage test.
        items = state['clients'][(page - 1) * 100:page * 100]
        data = {'clients': [{k: v for k, v in client.items() if k != 'olmId'} for client in items],
                'pagination': {'total': total, 'page': page, 'pageSize': 100}}
    elif path == '/v1/org/demo/pick-client-defaults':
        n = state.get('defaults', 0) + 1
        state['defaults'] = n
        data = {'olmId': f'synthetic-olm-{n}', 'olmSecret': sentinel, 'subnet': f'100.96.0.{n + 1}'}
    elif path == '/v1/org/demo/client' and method == 'PUT':
        # Check durable attempted checkpoint before any network create request.
        payload = json.load(sys.stdin)
        state['puts'] += 1
        checkpoint = root / 'repo' / 'state' / (payload['name'].replace('osteoview-', '').replace('-logs', '') + '.json')
        if payload['name'] == 'hel1-osteoview-metrics':
            checkpoint = root / 'repo' / 'state' / 'hel1.json'
        if not checkpoint.exists() or 'ciphertext' not in checkpoint.read_text() or sentinel in checkpoint.read_text():
            sys.exit(93)
        checkpoint_value = json.loads(base64.b64decode(json.loads(checkpoint.read_text())['ciphertext']))
        if checkpoint_value['phase'] != 'attempted':
            sys.exit(96)
        next_id = max((client['clientId'] for client in state['clients']), default=0) + 1
        client = {'clientId': next_id, 'niceId': f'nice-{next_id}',
                  'olmId': payload['olmId'], 'name': payload['name']}
        state['clients'].append(client)
        data = client
        status = 201
        if mode.get('lost') and state['puts'] == 1:
            store(statefile, state)
            sys.exit(7)
        if mode.get('no_commit') and state['puts'] == 1:
            state['clients'].pop()
            store(statefile, state)
            sys.exit(7)
    elif path.startswith('/v1/client/'):
        client_id = int(path.rsplit('/', 1)[1])
        data = next(c for c in state['clients'] if c['clientId'] == client_id)
    else:
        sys.exit(94)
    store(statefile, state)
    print(json.dumps({'data': data}) + '\n' + str(status), end='')
