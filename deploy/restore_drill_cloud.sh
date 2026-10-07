#!/usr/bin/env bash
# Restore into disposable, network-isolated resources. Never attaches live volumes.
set -euo pipefail
umask 077
task_root=/opt/semesteros
task_tools=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $(id -u) == 0 && $# == 1 ]] || { echo 'Usage: sudo restore_drill_cloud.sh /opt/semesteros/backups/<backup>' >&2; exit 1; }
task_backup=$(readlink -f -- "$1")
[[ "$task_backup" == "$task_root/backups/"* && -f "$task_backup/manifest.json" ]] || { echo 'Unexpected or incomplete backup path' >&2; exit 1; }
exec 8>"$task_root/restore-drill.lock"
flock -n 8 || { echo 'Another restore drill is running' >&2; exit 1; }
python3 "$task_tools/backup_integrity.py" verify --backup "$task_backup"
task_stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
task_name="semesteros-restore-drill-$task_stamp"
task_api_name="$task_name-api"
task_label="semesteros.restore-drill=$task_name"
task_work=$(mktemp -d "$task_root/maintenance/.restore-drill-XXXXXXXX")
task_db_volume="$task_name-db"
task_media_volume="$task_name-media"
task_db_created=false
task_media_created=false
task_container_created=false
task_api_created=false
cleanup() {
    task_rc=$?
    trap - EXIT INT TERM
    for task_container in "$task_api_name" "$task_name"; do
        [[ "$task_container" == "$task_api_name" && "$task_api_created" != true ]] && continue
        [[ "$task_container" == "$task_name" && "$task_container_created" != true ]] && continue
        task_owner=$(docker inspect --format '{{index .Config.Labels "semesteros.restore-drill"}}' "$task_container" 2>/dev/null || true)
        if [[ "$task_owner" == "$task_name" ]]; then docker rm -f "$task_container" >/dev/null || task_rc=1; else echo 'Unexpected drill container owner' >&2; task_rc=1; fi
    done
    for task_volume in "$task_db_volume" "$task_media_volume"; do
        [[ "$task_volume" == "$task_db_volume" && "$task_db_created" != true ]] && continue
        [[ "$task_volume" == "$task_media_volume" && "$task_media_created" != true ]] && continue
        task_owner=$(docker volume inspect --format '{{index .Labels "semesteros.restore-drill"}}' "$task_volume" 2>/dev/null || true)
        if [[ "$task_owner" == "$task_name" ]]; then docker volume rm "$task_volume" >/dev/null || task_rc=1; else echo 'Unexpected drill volume owner' >&2; task_rc=1; fi
    done
    if [[ -d "$task_work" && ! -L "$task_work" && "$task_work" == "$task_root/maintenance/.restore-drill-"* ]]; then rm -rf -- "$task_work"; fi
    printf 'Restore drill resources cleaned: %s\n' "$task_name"
    exit "$task_rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
task_db_image=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["db_image"])' "$task_backup/manifest.json")
task_app_image=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["app_image"])' "$task_backup/manifest.json")
[[ "$task_db_image" =~ ^sha256:[0-9a-f]{64}$ && "$task_app_image" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'Backup images must be immutable local IDs' >&2; exit 1; }
install -m 600 "$task_backup/server.env" "$task_work/server.env"
cmp -s "$task_backup/server.env" "$task_work/server.env"
python3 -c 'import secrets,sys; open(sys.argv[1],"w").write(secrets.token_hex(32)+"\n")' "$task_work/db.password"
chmod 600 "$task_work/db.password"
if docker volume inspect "$task_db_volume" >/dev/null 2>&1 || docker volume inspect "$task_media_volume" >/dev/null 2>&1; then
    echo 'Refusing to reuse existing drill volumes' >&2
    exit 1
fi
docker volume create --label "$task_label" "$task_db_volume" >/dev/null
task_db_created=true
docker volume create --label "$task_label" "$task_media_volume" >/dev/null
task_media_created=true
docker create --name "$task_name" --label "$task_label" --network none --memory 256m --cpus 0.5 \
    --mount "type=volume,source=$task_db_volume,target=/var/lib/postgresql/data" \
    --mount "type=bind,source=$task_work/db.password,target=/run/secrets/db.password,readonly" \
    -e POSTGRES_PASSWORD_FILE=/run/secrets/db.password -e POSTGRES_DB=semesteros -e POSTGRES_USER=semesteros "$task_db_image" >/dev/null
task_container_created=true
docker start "$task_name" >/dev/null
task_ready=false
for ((task_i=0; task_i<60; task_i++)); do
    # Initialization briefly starts a temporary server; only PID 1 postgres is final.
    if docker exec "$task_name" sh -c 'test "$(cat /proc/1/comm)" = postgres && pg_isready -U semesteros -d semesteros' >/dev/null 2>&1; then task_ready=true; break; fi
    sleep 1
done
[[ "$task_ready" == true ]] || { echo 'Isolated PostgreSQL did not become ready' >&2; exit 1; }
docker exec -i "$task_name" pg_restore --exit-on-error --no-owner --no-privileges -U semesteros -d semesteros <"$task_backup/database.dump" >"$task_work/restore.log" 2>&1 || { echo 'Isolated pg_restore failed; private diagnostics retained until cleanup' >&2; exit 1; }
docker run --rm --network none --user 0:0 --label "$task_label" --mount "type=volume,source=$task_media_volume,target=/restore-media" \
    --mount "type=bind,source=$task_backup/media.tar.gz,target=/restore-input/media.tar.gz,readonly" \
    --entrypoint tar "$task_app_image" -xzf /restore-input/media.tar.gz -C /restore-media
python3 "$task_tools/backup_integrity.py" database --container "$task_name" --output "$task_work/database.json"
docker run --rm --network none --user 0:0 --label "$task_label" --mount "type=volume,source=$task_media_volume,target=/restore-media,readonly" \
    --entrypoint tar "$task_app_image" -cf - -C /restore-media . | \
    python3 "$task_tools/backup_integrity.py" media --archive - --output "$task_work/media.json"
python3 "$task_tools/backup_integrity.py" compare --backup "$task_backup" --database "$task_work/database.json" --media "$task_work/media.json"
printf 'Private config byte comparison: ok\n'
[[ -f "$task_tools/restore_application_smoke.py" && -d "$task_root/models" ]] || { echo 'Missing application smoke helper or read-only models' >&2; exit 1; }
docker run --rm --network none --user 0:0 --label "$task_label" --memory 128m --cpus 0.5 \
    --mount "type=bind,source=$task_work,target=/restore-work" \
    --mount "type=bind,source=$task_tools/restore_application_smoke.py,target=/restore-tools/smoke.py,readonly" \
    --entrypoint python "$task_app_image" /restore-tools/smoke.py prepare-env --work-dir /restore-work
docker create --name "$task_api_name" --label "$task_label" --network "container:$task_name" \
    --memory 768m --cpus 1 --init --env-file "$task_work/api.env" \
    --mount "type=volume,source=$task_media_volume,target=/app/.local-data/media" \
    --mount "type=bind,source=$task_root/models,target=/models,readonly" \
    "$task_app_image" uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 >/dev/null
task_api_created=true
python3 "$task_tools/restore_application_smoke.py" assert-isolation --db-container "$task_name" \
    --api-container "$task_api_name" --db-volume "$task_db_volume" --media-volume "$task_media_volume"
docker start "$task_api_name" >/dev/null
docker exec -i "$task_api_name" python - smoke <"$task_tools/restore_application_smoke.py"
