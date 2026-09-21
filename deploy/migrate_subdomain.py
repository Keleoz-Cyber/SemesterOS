"""Stage HTTP, enable TLS, then explicitly retire the old path on keleoz-tencent.

Run with sudo. Does not alter containers, database or blog routes.
Configuration snapshots live under /opt/semesteros/backups/domain-*.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

DOMAIN = 'semesteros.keleoz.com'
MARKER = '# Managed by SemesterOS subdomain migration.'
SITE = Path('/etc/nginx/sites-available/semesteros')
LINK = Path('/etc/nginx/sites-enabled/semesteros')
SNIPPET = Path('/etc/nginx/snippets/semesteros-location.conf')


def health(url):
    with urllib.request.urlopen(url, timeout=15) as response:
        assert response.status == 200
        assert json.load(response)['status'] == 'ok'


def nginx_reload():
    subprocess.run(['nginx', '-t'], check=True)
    subprocess.run(['systemctl', 'reload', 'nginx'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['prepare-http', 'enable-https', 'retire-old'])
    phase = parser.parse_args().phase
    assert os.geteuid() == 0, 'Run with sudo'
    health('http://127.0.0.1:8871/health')
    template = Path(__file__).with_name('nginx-semesteros-subdomain.conf').read_text()
    if phase == 'retire-old':
        health(f'https://{DOMAIN}/health')
        assert SNIPPET.is_file() and not SNIPPET.is_symlink()
        replacement = Path(__file__).with_name('nginx-semesteros-location.conf').read_bytes()
        assert b'410' in replacement and b'proxy_pass' not in replacement
        target = SNIPPET
    else:
        assert not SITE.is_symlink(), 'Unexpected site symlink'
        if SITE.exists():
            assert SITE.read_text().startswith(MARKER), 'Existing site is not managed by this script'
        if os.path.lexists(LINK):
            assert LINK.is_symlink() and LINK.resolve() == SITE, 'Existing enabled site conflicts'
        if phase == 'prepare-http':
            assert not SITE.exists() or 'listen 443' not in SITE.read_text(), 'Do not downgrade active TLS'
            template = template.split('\nserver {\n    listen 443', 1)[0]
            Path('/var/www/semesteros-acme/.well-known/acme-challenge').mkdir(parents=True, exist_ok=True)
        else:
            assert Path(f'/etc/letsencrypt/live/{DOMAIN}/fullchain.pem').is_file(), 'Issue certificate first'
        target, replacement = SITE, template.encode()
    previous = target.read_bytes() if target.exists() else None
    link_existed = os.path.lexists(LINK)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = Path('/opt/semesteros/backups') / f'domain-{phase}-{stamp}'
    backup.mkdir(mode=0o700, parents=True)
    if previous is not None:
        snapshot = backup / target.name
        snapshot.write_bytes(previous)
        snapshot.chmod(0o600)
    assert (target.read_bytes() if target.exists() else None) == previous, 'Configuration changed concurrently'
    try:
        target.write_bytes(replacement)
        target.chmod(0o644)
        if phase != 'retire-old' and not link_existed:
            LINK.symlink_to(SITE)
        nginx_reload()
        if phase == 'enable-https':
            command = [
                'curl', '--noproxy', '*', '--fail', '--silent', '--show-error',
                '--max-time', '15', '--resolve', f'{DOMAIN}:443:127.0.0.1',
                f'https://{DOMAIN}/health',
            ]
            # systemctl reload returns before new nginx workers necessarily serve TLS.
            # Verify the certificate on every attempt; never bypass TLS verification.
            for attempt in range(10):
                response = subprocess.run(command, text=True, capture_output=True)
                if response.returncode == 0:
                    assert json.loads(response.stdout)['status'] == 'ok'
                    break
                if attempt == 9:
                    raise RuntimeError(response.stderr)
                time.sleep(0.5)
    except Exception:
        if previous is None:
            target.unlink(missing_ok=True)
        else:
            target.write_bytes(previous)
        if phase != 'retire-old' and not link_existed:
            LINK.unlink(missing_ok=True)
        nginx_reload()
        raise
    print(f'{phase} complete; configuration backup: {backup}')


if __name__ == '__main__':
    main()
