"""Build and test a prepared release against disposable PostgreSQL schemas."""
import argparse
import os
from pathlib import Path
import re
import subprocess


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
    # Each test creates a unique test_* schema and drops only that schema.
    # The normal services remain on their old image throughout verification.
    subprocess.run([*command, 'run', '--rm', '--no-deps', '--entrypoint', 'python',
        '--volume', str(release / 'services/api/tests') + ':/app/tests:ro',
        '--env', 'MEDIA_ROOT=/tmp/semesteros-release-test-media', 'api', '-c',
        # The migration-chain test intentionally allows only localhost:55439.
        # This release has no new migration; keep that protection intact.
        "import os,pytest; os.environ['POSTGRES_TEST_URL']=os.environ['DATABASE_URL']; raise SystemExit(pytest.main(['-q','tests','-k','not test_postgres_full_chain_and_notice_delta_preserve_populated_records']))"],
        env=env, check=True)


if __name__ == '__main__': main()
