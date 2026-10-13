"""Build and test a prepared release against disposable PostgreSQL schemas."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import secrets
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--release', required=True); p.add_argument('--tag', required=True)
    args = p.parse_args()
    release = Path(args.release).resolve()
    assert os.geteuid() == 0
    assert release.parent == Path('/opt/semesteros/releases') and release.is_dir()
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,70}', args.tag)
    env = {**os.environ, 'APP_TAG': args.tag}
    command = ['docker', 'compose', '--env-file', '/opt/semesteros/.env', '-f', str(release / 'deploy/compose.cloud.yaml')]
    subprocess.run([*command, 'build', 'api'], env=env, check=True)
    password = secrets.token_hex(20)
    # Migration and concurrency tests use a disposable DB, not production schemas.
    container = subprocess.check_output(['docker', 'run', '-d', '--rm',
        '--name', 'semesteros-release-test-' + args.tag, '--memory=512m', '--cpus=.5',
        '--tmpfs', '/var/lib/postgresql/data:rw,size=384m',
        '-p', '127.0.0.1:55439:5432', '-e', 'POSTGRES_USER=tests',
        '-e', 'POSTGRES_DB=semesteros_test', '-e', 'POSTGRES_PASSWORD=' + password,
        'postgres:17-alpine', '-c', 'max_wal_size=128MB', '-c', 'min_wal_size=32MB']).decode().strip()
    try:
        for _ in range(30):
            if subprocess.run(['docker', 'exec', container, 'pg_isready', '-U', 'tests', '-d', 'semesteros_test'],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0: break
            time.sleep(1)
        else: raise RuntimeError('Isolated PostgreSQL did not become ready')
        url = 'postgresql+psycopg://tests:' + password + '@127.0.0.1:55439/semesteros_test'
        subprocess.run(['docker', 'run', '--rm', '--network=host', '--memory=1024m', '--cpus=1',
            '--entrypoint', 'python', '--volume', str(release/'services/api/tests')+':/app/tests:ro',
            '--env', 'POSTGRES_TEST_URL='+url, '--env', 'MEDIA_ROOT=/tmp/semesteros-release-test-media',
            'semesteros-api:'+args.tag, '-m', 'pytest', '-q', 'tests'], check=True)
    finally:
        # Only remove the exact container this invocation created.
        subprocess.run(['docker', 'rm', '-f', '-v', container], check=False)


if __name__ == '__main__': main()
