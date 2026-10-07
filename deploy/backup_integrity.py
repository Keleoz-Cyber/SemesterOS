#!/usr/bin/env python3
"""Private backup manifests and aggregate restore checks; never emits row data."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile


def digest_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def run(command):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        # PostgreSQL errors can contain user values; don't copy stderr to logs.
        raise RuntimeError(f'{command[0]} failed (exit {result.returncode})')
    return result.stdout.decode('utf-8')


def database(container):
    prefix = ['docker', 'exec', container]
    psql = prefix + ['psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-U', 'semesteros', '-d', 'semesteros', '-c']
    catalog = run(psql + ["SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' ORDER BY 1,2;"])
    tables = [line.split('|') for line in catalog.splitlines() if line]
    def ident(value):
        return '"' + value.replace('"', '""') + '"'
    def literal(value):
        return "'" + value.replace("'", "''") + "'"
    queries = []
    for schema, name in tables:
        row_hash = "encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex')"
        queries.append(f"SELECT {literal(schema + '.' + name)}, count(*), encode(sha256(convert_to(coalesce(string_agg({row_hash},'' ORDER BY {row_hash}),''),'UTF8')),'hex') FROM {ident(schema)}.{ident(name)} t")
    rows = run(psql + [' UNION ALL '.join(queries) + ' ORDER BY 1']) if queries else ''
    counts = [int(line.split('|')[1]) for line in rows.splitlines()]
    schema_dump = run(prefix + ['pg_dump', '-U', 'semesteros', '--schema-only', '--no-owner', '--no-privileges', 'semesteros'])
    # Recent PostgreSQL versions generate random psql restriction tokens.
    schema_text = '\n'.join(line for line in schema_dump.splitlines() if not line.startswith(('\\restrict ', '\\unrestrict '))) + '\n'
    sequences = run(psql + ["SELECT schemaname, sequencename, coalesce(last_value::text,'NULL') FROM pg_sequences WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2;"])
    return {
        'table_count': len(tables), 'row_count': sum(counts),
        'schema_sha256': hashlib.sha256(schema_text.encode()).hexdigest(),
        'data_sha256': hashlib.sha256(rows.encode()).hexdigest(),
        'sequence_count': len(sequences.splitlines()),
        'sequences_sha256': hashlib.sha256(sequences.encode()).hexdigest(),
    }


def media(archive):
    stream = sys.stdin.buffer if archive == '-' else None
    kwargs = {'fileobj': stream, 'mode': 'r|*'} if stream else {'name': archive, 'mode': 'r:*'}
    entries = []
    total_bytes = file_count = 0
    with tarfile.open(**kwargs) as bundle:
        for member in bundle:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                raise RuntimeError('Media archive contains an unsafe or unsupported entry')
            name = str(path)
            if name == '.':
                continue
            digest = hashlib.sha256()
            if member.isfile():
                file_count += 1
                total_bytes += member.size
                with bundle.extractfile(member) as source:
                    for block in iter(lambda: source.read(1024 * 1024), b''):
                        digest.update(block)
            entries.append([name, 'file' if member.isfile() else 'dir', member.mode, member.size, digest.hexdigest()])
    names = [entry[0] for entry in entries]
    if len(names) != len(set(names)):
        raise RuntimeError('Media archive contains duplicate paths')
    canonical = json.dumps(sorted(entries), ensure_ascii=False, separators=(',', ':')).encode()
    return {'entry_count': len(entries), 'file_count': file_count, 'bytes': total_bytes, 'tree_sha256': hashlib.sha256(canonical).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    path.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    snapshot = commands.add_parser('snapshot')
    snapshot.add_argument('--backup', required=True)
    snapshot.add_argument('--db-container', required=True)
    snapshot.add_argument('--app-image', required=True)
    snapshot.add_argument('--db-image', required=True)
    snapshot.add_argument('--initially-running', required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--backup', required=True)
    db = commands.add_parser('database')
    db.add_argument('--container', required=True)
    db.add_argument('--output', required=True)
    med = commands.add_parser('media')
    med.add_argument('--archive', required=True)
    med.add_argument('--output', required=True)
    compare = commands.add_parser('compare')
    compare.add_argument('--backup', required=True)
    compare.add_argument('--database', required=True)
    compare.add_argument('--media', required=True)
    args = parser.parse_args()
    if args.command == 'snapshot':
        root = Path(args.backup)
        filenames = ('database.dump', 'media.tar.gz', 'server.env', 'release.txt')
        manifest = {
            'format_version': 1, 'created_at_utc': datetime.now(timezone.utc).isoformat(),
            'release': (root / 'release.txt').read_text().strip(),
            'app_image': args.app_image, 'db_image': args.db_image,
            'initially_running': args.initially_running.split(),
            'database': database(args.db_container), 'media': media(str(root / 'media.tar.gz')),
            'artifacts': {name: digest_file(root / name) for name in filenames},
        }
        write_json(root / 'manifest.json', manifest)
        print(json.dumps({'snapshot': 'ok', 'database': manifest['database'], 'media': manifest['media']}))
    elif args.command == 'verify':
        root = Path(args.backup)
        manifest = json.loads((root / 'manifest.json').read_text())
        expected = {'database.dump', 'media.tar.gz', 'server.env', 'release.txt'}
        if manifest['format_version'] != 1 or set(manifest['artifacts']) != expected:
            raise RuntimeError('Unsupported backup manifest')
        for name in expected:
            path = root / name
            if path.is_symlink() or digest_file(path) != manifest['artifacts'][name]:
                raise RuntimeError('Backup artifact integrity mismatch')
        if media(str(root / 'media.tar.gz')) != manifest['media']:
            raise RuntimeError('Media fingerprint mismatch')
        print(json.dumps({'backup_integrity': 'ok', 'artifact_count': len(expected)}))
    elif args.command == 'database':
        write_json(Path(args.output), database(args.container))
    elif args.command == 'media':
        write_json(Path(args.output), media(args.archive))
    elif args.command == 'compare':
        manifest = json.loads((Path(args.backup) / 'manifest.json').read_text())
        restored_db = json.loads(Path(args.database).read_text())
        restored_media = json.loads(Path(args.media).read_text())
        if restored_db != manifest['database'] or restored_media != manifest['media']:
            raise RuntimeError('Restored database or media differs from the backup snapshot')
        print(json.dumps({'restore_comparison': 'ok', 'database': restored_db, 'media': restored_media}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Integrity check failed: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
