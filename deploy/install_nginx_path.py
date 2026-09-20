"""Install the SemesterOS HTTPS path without replacing the existing site routes.

Run with sudo on the selected host after its private API health check passes.
"""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,subprocess,urllib.request


def main():
    with urllib.request.urlopen('http://127.0.0.1:8871/health',timeout=5) as response:
        assert response.status==200
    site=Path('/etc/nginx/sites-available/keleoz')
    old=site.read_bytes();text=old.decode()
    marker='    server_name keleoz.com;'
    include='    include /etc/nginx/snippets/semesteros-location.conf;'
    assert text.count(marker)==1,'Expected exactly one main HTTPS site'
    source=Path(__file__).with_name('nginx-semesteros-location.conf').read_bytes()
    snippet=Path('/etc/nginx/snippets/semesteros-location.conf')
    previous_snippet=snippet.read_bytes() if snippet.exists() else None
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup=Path('/opt/semesteros/backups')/f'nginx-keleoz-{stamp}.conf'
    backup.write_bytes(old);backup.chmod(0o600)
    updated=text if include in text else text.replace(marker,marker+'\n'+include)
    snippet.write_bytes(source);snippet.chmod(0o644)
    assert site.read_bytes()==old,'Site changed concurrently; no overwrite'
    site.write_text(updated)
    try:
        subprocess.run(['nginx','-t'],check=True)
        subprocess.run(['systemctl','reload','nginx'],check=True)
    except Exception:
        site.write_bytes(old)
        if previous_snippet is not None:snippet.write_bytes(previous_snippet)
        subprocess.run(['nginx','-t'],check=True)
        subprocess.run(['systemctl','reload','nginx'],check=True)
        raise
    print('SemesterOS HTTPS path installed; previous site hash',hashlib.sha256(old).hexdigest())


if __name__=='__main__':main()
