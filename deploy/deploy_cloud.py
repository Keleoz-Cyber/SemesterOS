"""Deploy a reviewed release on the existing SemesterOS test host.

Build first, back up database/media/config, migrate additively, then replace only
the SemesterOS API and worker. On failure restore the former image/config.
Never resets data volumes or modifies the blog/Nginx routes.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path('/opt/semesteros')


def run(args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', required=True)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0, 'Run with sudo'
    release = Path(args.release).resolve()
    assert release.parent == ROOT / 'releases' and release.is_dir(), 'Unexpected release path'
    assert re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,70}', args.tag), 'Unexpected image tag'
    current = ROOT / 'current'
    assert current.is_symlink(), 'Current release must be a managed symlink'
    previous = current.resolve()
    assert previous.parent == ROOT / 'releases', 'Unexpected previous release'
    env_file = ROOT / '.env'; original_env = env_file.read_bytes()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    config_backup = ROOT / 'backups' / ('release-' + stamp)
    config_backup.mkdir(mode=0o700)
    (config_backup / 'server.env').write_bytes(original_env)
    (config_backup / 'server.env').chmod(0o600)
    (config_backup / 'previous-release.txt').write_text(str(previous))
    new_env = {**os.environ, 'APP_TAG': args.tag}

    def compose(path, *command, env=None):
        run(['docker', 'compose', '--env-file', str(env_file), '-f', str(path / 'deploy/compose.cloud.yaml'), *command], env=env)

    print('Building release image', flush=True)
    compose(release, 'build', 'api', env=new_env)
    print('Backing up existing database and media', flush=True)
    run(['bash', str(previous / 'deploy/backup_cloud.sh')])
    try:
        lines = original_env.decode().splitlines()
        lines = [line for line in lines if not line.startswith('APP_TAG=')]
        env_file.write_text('\n'.join(lines + ['APP_TAG=' + args.tag]) + '\n')
        env_file.chmod(0o600)
        compose(release, 'run', '--rm', '--no-deps', 'migrate', env=new_env)
        compose(release, 'up', '-d', '--no-deps', '--wait', '--wait-timeout', '100', 'api', 'worker', env=new_env)
        with urllib.request.urlopen('http://127.0.0.1:8871/health', timeout=10) as response:
            health = json.load(response)
        assert health['status'] == 'ok' and health['version'] == '0.2.0', 'Unexpected API health'
        temporary = ROOT / ('current-' + stamp)
        temporary.symlink_to(release)
        os.replace(temporary, current)
    except Exception:
        print('Restoring former service image; additive tables are preserved', flush=True)
        env_file.write_bytes(original_env); env_file.chmod(0o600)
        compose(previous, 'up', '-d', '--no-deps', '--wait', '--wait-timeout', '100', 'api', 'worker')
        raise
    print(json.dumps({'deployed': str(release), 'config_backup': str(config_backup), 'health': health}))


if __name__ == '__main__':
    main()
