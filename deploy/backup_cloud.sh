#!/usr/bin/env bash
# Run with sudo; briefly pauses only SemesterOS API/worker for a consistent backup.
set -euo pipefail
umask 077
task_root=/opt/semesteros
task_release=$(readlink -f "$task_root/current")
[[ "$task_release" == "$task_root"/releases/* ]] || { echo 'Unexpected release path'; exit 1; }
compose() { docker compose --env-file "$task_root/.env" -f "$task_release/deploy/compose.cloud.yaml" "$@"; }
task_backup="$task_root/backups/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$task_backup"
task_api_id=$(compose ps -q api)
task_worker_id=$(compose ps -q worker)
test -n "$task_api_id" && test -n "$task_worker_id"
task_image=$(docker inspect --format '{{.Config.Image}}' "$task_api_id")
trap 'docker start "$task_api_id" "$task_worker_id" >/dev/null' EXIT
compose stop api worker >/dev/null
compose exec -T db pg_dump -U semesteros -Fc semesteros >"$task_backup/database.dump"
docker run --rm --network none --volumes-from "$task_api_id" --entrypoint tar "$task_image" -czf - -C /app/.local-data/media . >"$task_backup/media.tar.gz"
cp "$task_root/.env" "$task_backup/server.env"
printf '%s\n' "$task_release" >"$task_backup/release.txt"
echo "Backup saved: $task_backup"
