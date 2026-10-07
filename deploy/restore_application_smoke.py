#!/usr/bin/env python3
"""Prepare private clone settings and verify a tiny synthetic API workflow."""
import argparse
from datetime import date, timedelta
import json
from pathlib import Path
import secrets
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, ProxyHandler, build_opener


def prepare_env(work_dir):
    from dotenv import dotenv_values
    root = Path(work_dir)
    config = {key: value for key, value in dotenv_values(root / 'server.env').items() if value is not None}
    password = (root / 'db.password').read_text().strip()
    config.update({
        'DATABASE_URL': f'postgresql+psycopg://semesteros:{password}@127.0.0.1:5432/semesteros',
        'POSTGRES_PASSWORD': password,
        'MEDIA_ROOT': '/app/.local-data/media', 'MEDIA_WORKER_MODE': 'external',
        'SENSEVOICE_MODEL_DIR': '/models/sensevoice', 'RAPIDOCR_MODEL_DIR': '/models/rapidocr',
        'OMP_NUM_THREADS': '2', 'OPENBLAS_NUM_THREADS': '1',
    })
    if any('\n' in value or '\r' in value for value in config.values()):
        raise RuntimeError('Private configuration contains unsupported multiline values')
    target = root / 'api.env'
    target.write_text(''.join(f'{key}={value}\n' for key, value in sorted(config.items())), encoding='utf-8')
    target.chmod(0o600)
    print(json.dumps({'private_clone_env': 'prepared', 'worker_mode': 'external'}))


def assert_isolation(args):
    inspected = subprocess.run(['docker', 'inspect', args.db_container, args.api_container],
                               check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    db, api = json.loads(inspected.stdout)
    if db['HostConfig']['NetworkMode'] != 'none' or api['HostConfig']['NetworkMode'] not in {
            'container:' + db['Id'], 'container:' + args.db_container}:
        raise RuntimeError('Unexpected clone network configuration')
    for container in (db, api):
        if container['HostConfig']['PortBindings'] or any((container['NetworkSettings'].get('Ports') or {}).values()):
            raise RuntimeError('Clone must not publish ports')
    db_mounts = {m['Destination']: m for m in db['Mounts']}
    api_mounts = {m['Destination']: m for m in api['Mounts']}
    if set(db_mounts) != {'/var/lib/postgresql/data', '/run/secrets/db.password'}:
        raise RuntimeError('Unexpected database clone mounts')
    if db_mounts['/var/lib/postgresql/data'].get('Name') != args.db_volume:
        raise RuntimeError('Database volume is not the drill volume')
    if set(api_mounts) != {'/app/.local-data/media', '/models'}:
        raise RuntimeError('Unexpected API clone mounts')
    if api_mounts['/app/.local-data/media'].get('Name') != args.media_volume or api_mounts['/models']['RW']:
        raise RuntimeError('Media must use the drill volume and models must be read-only')
    if api_mounts['/models']['Source'] != '/opt/semesteros/models':
        raise RuntimeError('Unexpected read-only model path')
    env = dict(value.split('=', 1) for value in api['Config']['Env'] if '=' in value)
    url = urlsplit(env.get('DATABASE_URL', ''))
    if url.hostname != '127.0.0.1' or url.port != 5432 or env.get('MEDIA_WORKER_MODE') != 'external':
        raise RuntimeError('API clone must use the isolated loopback DB and external worker mode')
    print(json.dumps({'clone_isolation': 'ok', 'db_network': 'none', 'api_network': 'database_container_loopback',
                      'published_ports': 0, 'production_data_mounts': 0, 'models_read_only': True, 'worker_started': False}))


def smoke():
    opener = build_opener(ProxyHandler({}))
    base = 'http://127.0.0.1:8000'
    def request(method, path, expected=200, body=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = Request(base + path, data=json.dumps(body).encode() if body is not None else None,
                      headers=headers, method=method)
        try:
            with opener.open(req, timeout=3) as response:
                if response.status != expected:
                    raise RuntimeError('Unexpected HTTP status in synthetic smoke')
                return json.load(response)
        except HTTPError as error:
            # Response bodies and authentication credentials are intentionally private.
            raise RuntimeError(f'Synthetic {method} endpoint returned HTTP {error.code}') from None
    deadline = time.monotonic() + 75
    while True:
        try:
            health = request('GET', '/health')
            if health.get('status') != 'ok' or health.get('database') != 'postgresql':
                raise RuntimeError('Recovered API health is not ready')
            break
        except (URLError, RuntimeError):
            if time.monotonic() >= deadline:
                raise RuntimeError('Recovered API did not become healthy') from None
            time.sleep(1)
    credentials = {'username': 'restore_' + secrets.token_hex(8), 'password': secrets.token_urlsafe(24)}
    registered = request('POST', '/api/v1/auth/register', expected=201, body=credentials)
    logged_in = request('POST', '/api/v1/auth/login', body=credentials)
    if logged_in['user']['id'] != registered['user']['id']:
        raise RuntimeError('Synthetic login returned a different owner')
    token = logged_in['access_token']
    today = date.today()
    semester_payload = {'name': 'Restore drill synthetic semester',
                        'first_monday': (today - timedelta(days=today.weekday())).isoformat(), 'total_weeks': 16,
                        'periods': [{'number': 1, 'start': '08:00', 'end': '08:50'}]}
    semester = request('POST', '/api/v1/semesters', expected=201, body=semester_payload, token=token)
    task_payload = {'semester_id': semester['id'], 'kind': 'task', 'title': 'Restore drill synthetic task',
                    'certainty': 'formal', 'category_id': 'study', 'time': {'precision': 'unknown'}}
    task = request('POST', '/api/v1/items', expected=201, body=task_payload, token=token)
    restored = request('GET', '/api/v1/items/' + task['id'], token=token)
    semesters = request('GET', '/api/v1/semesters', token=token)
    if restored.get('title') != task_payload['title'] or restored.get('semester_id') != semester['id'] or restored.get('kind') != 'task':
        raise RuntimeError('Synthetic task readback mismatch')
    if not any(value['id'] == semester['id'] and value['name'] == semester_payload['name'] for value in semesters):
        raise RuntimeError('Synthetic semester readback mismatch')
    print(json.dumps({'application_smoke': 'ok', 'health': 'ok', 'registration': 'ok', 'login': 'ok',
                      'semester_create_and_read': 'ok', 'task_create_and_read': 'ok',
                      'synthetic_account_count': 1, 'synthetic_semester_count': 1, 'synthetic_task_count': 1}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare-env')
    prepare.add_argument('--work-dir', required=True)
    isolation = commands.add_parser('assert-isolation')
    for name in ('db-container', 'api-container', 'db-volume', 'media-volume'):
        isolation.add_argument('--' + name, required=True)
    commands.add_parser('smoke')
    args = parser.parse_args()
    if args.command == 'prepare-env':
        prepare_env(args.work_dir)
    elif args.command == 'assert-isolation':
        assert_isolation(args)
    else:
        smoke()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Restore application check failed: {type(error).__name__}', file=sys.stderr)
        sys.exit(1)
