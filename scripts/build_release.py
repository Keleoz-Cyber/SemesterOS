"""Build, sign and verify the current Android release without retaining copies.

Windows: python scripts/build_release.py --build
Uses JDK 21, Android SDK and the existing upgrade-compatible signing certificate.
Custom keystore passwords are read from SEMESTEROS_KEYSTORE_PASSWORD, never CLI.
"""
from pathlib import Path
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / 'apps/mobile'
OUT = ROOT / 'output/release'
WORK = ROOT / 'output/closeout/android'
API_URL = 'https://semesteros.keleoz.com'
CERT = 'e19f8c3a6f68146814d9aebe08d98092aa7b724a54422e8d4ba89bd62a763b51'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def elf_64bit_16kb_aligned(data):
    """Static LOAD-segment check; this is not a 16 KB device runtime test."""
    assert data[:6] == b'\x7fELF\x02\x01', 'Expected little-endian 64-bit ELF'
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    loads = [struct.unpack_from('<IIQQQQQQ', data, offset + size * i)
             for i in range(count)]
    loads = [segment for segment in loads if segment[0] == 1]
    return bool(loads) and all(segment[7] >= 16384 and segment[7] % 16384 == 0
                              and segment[2] % 16384 == segment[3] % 16384 for segment in loads)


def sources():
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    paths = {name for name in tracked if name.startswith(('apps/mobile/', 'services/api/app/version.py'))
             and not name.startswith(('apps/mobile/test', 'apps/mobile/integration_test'))
             and (ROOT / name).is_file()}
    paths.update(p.relative_to(ROOT).as_posix() for folder in ('lib', 'assets', 'tool')
                 for p in (MOBILE / folder).rglob('*') if p.is_file())
    paths.add('scripts/build_release.py')
    paths.add('services/api/app/version.py')
    files = {name: digest(ROOT / name) for name in sorted(paths)}
    aggregate = hashlib.sha256(''.join(f'{n}\0{h}\n' for n, h in files.items()).encode()).hexdigest()
    return aggregate, files


def run(command, log, *, cwd=ROOT, environment=None, stdin=None):
    result = subprocess.run(command, cwd=cwd, env=environment, input=stdin,
                            capture_output=True, text=True, encoding='utf-8', errors='replace',
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    output = result.stdout + result.stderr
    (OUT / log).write_text(output, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{log} failed (exit {result.returncode}); inspect output/release/{log}')
    return output


def jdk21():
    choices = [os.environ.get('SEMESTEROS_JDK_HOME'), os.environ.get('JAVA_HOME')]
    for vendor in ('Microsoft', 'Java', 'Eclipse Adoptium'):
        parent = Path(os.environ.get('ProgramFiles', r'C:\Program Files')) / vendor
        if parent.is_dir(): choices.extend(str(p) for p in parent.iterdir() if p.is_dir())
    for choice in choices:
        if choice and (Path(choice) / 'release').is_file():
            if re.search(r'^JAVA_VERSION="21\.', (Path(choice) / 'release').read_text(encoding='utf-8'), re.M):
                return Path(choice)
    raise RuntimeError('JDK 21 required; set SEMESTEROS_JDK_HOME')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--keystore', type=Path, default=Path.home() / '.android/debug.keystore')
    parser.add_argument('--key-alias', default='androiddebugkey')
    parser.add_argument('--expected-cert', default=CERT)
    args = parser.parse_args()
    assert os.name == 'nt', 'Use this packaging entry on Windows with the Android SDK'
    version, build = re.search(r'^version:\s*([\d.]+)\+(\d+)\s*$',
                              (MOBILE / 'pubspec.yaml').read_text(encoding='utf-8'), re.M).groups()
    api_version = re.search(r'^VERSION\s*=\s*"([^\"]+)"',
                            (ROOT / 'services/api/app/version.py').read_text(encoding='utf-8'), re.M)[1]
    assert version == api_version, 'Client/API release versions differ'
    assert args.keystore.is_file(), 'Existing signing keystore required; no key is generated'
    java = jdk21()
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
               or str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk'))
    build_tools = max((p for p in (sdk / 'build-tools').iterdir()
                       if re.fullmatch(r'\d+\.\d+\.\d+', p.name)),
                      key=lambda p: tuple(map(int, p.name.split('.'))))
    flutter = shutil.which('flutter.bat') or shutil.which('flutter')
    if not flutter:
        fallback = Path.home() / 'flutter/bin/flutter.bat'
        assert fallback.is_file(), 'Flutter SDK required on PATH'
        flutter = str(fallback)
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    assert OUT.resolve().is_relative_to(ROOT) and WORK.resolve().is_relative_to(ROOT)
    if not args.build:
        print(json.dumps({'version': version, 'build_number': int(build), 'tools_verified': True}))
        return
    environment = {**os.environ, 'JAVA_HOME': str(java), 'ANDROID_HOME': str(sdk),
                   'ANDROID_SDK_ROOT': str(sdk)}
    environment['PATH'] = str(java / 'bin') + os.pathsep + environment.get('PATH', '')
    environment['GRADLE_OPTS'] = (environment.get('GRADLE_OPTS', '') +
        f' -Dorg.gradle.java.installations.paths="{java}"').strip()
    run([flutter, 'build', 'apk', '--release', '--config-only', '--target-platform',
         'android-arm,android-arm64,android-x64', '--dart-define=API_BASE_URL=' + API_URL],
        'flutter-config.log', cwd=MOBILE, environment=environment)
    source_hash, files = sources()
    defines = base64.b64encode(('API_BASE_URL=' + API_URL).encode()).decode()
    run([str(MOBILE / 'android/gradlew.bat'), ':app:assembleRelease', '--offline',
         '-Ptarget-platform=android-arm,android-arm64,android-x64', '-Ptarget=lib/main.dart',
         '-Pdart-defines=' + defines, '-Pdart-obfuscation=false', '-Ptree-shake-icons=true',
         '-Ptrack-widget-creation=false', '-PsemesterosQa=false'],
        'android-build.log', cwd=MOBILE / 'android', environment=environment)
    assert sources() == (source_hash, files), 'Source changed during release build'
    unsigned = MOBILE / 'build/app/outputs/flutter-apk/app-release.apk'
    assert unsigned.is_file()
    aligned, signed = WORK / 'aligned.apk', WORK / 'signed.apk'
    run([str(build_tools / 'zipalign.exe'), '-P', '16', '-f', '4', str(unsigned), str(aligned)], 'zipalign.log')
    password = os.environ.get('SEMESTEROS_KEYSTORE_PASSWORD', 'android')
    signer = [str(java / 'bin/java.exe'), '-jar', str(build_tools / 'lib/apksigner.jar')]
    run([*signer, 'sign', '--ks', str(args.keystore), '--ks-key-alias', args.key_alias,
         '--ks-pass', 'stdin', '--key-pass', 'stdin', '--out', str(signed), str(aligned)],
        'sign.log', stdin=password + '\n' + password + '\n')
    signature = run([*signer, 'verify', '--verbose', '--print-certs', str(signed)], 'signature.log')
    actual_cert = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)', signature)[1]
    assert actual_cert == args.expected_cert, 'Signing certificate changed'
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
    assert 'Verified using v3 scheme (APK Signature Scheme v3): true' in signature
    run([str(build_tools / 'zipalign.exe'), '-c', '-P', '16', '4', str(signed)], 'alignment-check.log')
    badging = run([str(build_tools / 'aapt.exe'), 'dump', 'badging', str(signed)], 'apk-badging.log')
    assert "name='cn.semesteros.semester_os'" in badging
    assert f"versionCode='{build}'" in badging and f"versionName='{version}'" in badging
    assert 'application-debuggable' not in badging and "application-label:'拾日'" in badging
    with zipfile.ZipFile(signed) as package:
        abis = sorted(p.split('/')[1] for p in package.namelist() if re.fullmatch(r'lib/[^/]+/libapp\.so', p))
        assert abis == ['arm64-v8a', 'armeabi-v7a', 'x86_64']
        for abi in abis: assert API_URL.encode() in package.read(f'lib/{abi}/libapp.so')
        elf_libraries = sorted(name for name in package.namelist()
                               if re.fullmatch(r'lib/(arm64-v8a|x86_64)/[^/]+\.so', name))
        assert elf_libraries and all(elf_64bit_16kb_aligned(package.read(name))
                                     for name in elf_libraries), '64-bit ELF LOAD alignment failed'
        assert 'assets/flutter_assets/assets/hlju_reader.js' in package.namelist()
        resources = run([str(build_tools / 'aapt.exe'), 'dump', 'resources', str(signed)], 'apk-resources.log')
        assert 'drawable/ic_notification' in resources
    apk_folder = ROOT / 'output/apk'; apk_folder.mkdir(exist_ok=True)
    destination = apk_folder / f'拾日-{version}.apk'
    assert destination.resolve().is_relative_to(ROOT), 'Delivery path escaped the project'
    assert sources() == (source_hash, files), 'Source changed before publishing the APK'
    os.replace(signed, destination)
    receipt = {'version': version, 'build_number': int(build), 'application_id': 'cn.semesteros.semester_os',
               'build_mode': 'release', 'debuggable': False, 'api_base_url': API_URL,
               'certificate_sha256': actual_cert, 'abis': abis, 'alignment_kb': 16,
               'elf_64bit_16kb_aligned': True, 'elf_checked_libraries': elf_libraries,
               'apk': destination.relative_to(ROOT).as_posix(), 'bytes': destination.stat().st_size,
               'sha256': digest(destination), 'source_sha256': source_hash,
               'built_at_utc': datetime.now(timezone.utc).isoformat(), 'installed': False}
    (OUT / 'manifest.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUT / 'source-manifest.json').write_text(json.dumps(files, indent=2), encoding='utf-8')
    (OUT / 'SHA256SUMS.txt').write_text(receipt['sha256'] + '  ' + destination.name + '\n', encoding='utf-8')
    assert sources() == (source_hash, files), 'Source changed after packaging'
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'): sys.stdout.reconfigure(encoding='utf-8')
    main()
