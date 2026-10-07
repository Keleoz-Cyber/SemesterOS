#!/usr/bin/env bash
# Run as root. Stop only originally running API/worker during the snapshot.
set -euo pipefail
umask 077
task_root=/opt/semesteros
task_tools=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $(id -u) == 0 ]] || { echo 'Run as root' >&2; exit 1; }
install -d -m 700 "$task_root/backups"
exec 9>"$task_root/backup.lock"
flock -n 9 || { echo 'Another SemesterOS backup is running' >&2; exit 1; }
task_release=$(readlink -f "$task_root/current")
[[ "$task_release" == "$task_root"/releases/* && -d "$task_release" ]] || { echo 'Unexpected release path' >&2; exit 1; }
[[ -f "$task_root/.env" && -f "$task_tools/backup_integrity.py" ]] || { echo 'Missing config or integrity helper' >&2; exit 1; }
compose() { docker compose --env-file "$task_root/.env" -f "$task_release/deploy/compose.cloud.yaml" "$@"; }
task_api_id=$(compose ps -aq api)
task_worker_id=$(compose ps -aq worker)
task_db_id=$(compose ps -q db)
[[ -n "$task_api_id" && -n "$task_worker_id" && -n "$task_db_id" ]] || { echo 'Missing SemesterOS containers' >&2; exit 1; }
task_image=$(docker inspect --format '{{.Image}}' "$task_api_id")
task_db_image=$(docker inspect --format '{{.Image}}' "$task_db_id")
task_running=()
task_services=()
for task_service in api worker; do
    task_id=$task_api_id
    [[ "$task_service" == worker ]] && task_id=$task_worker_id
    task_state=$(docker inspect --format '{{.State.Status}}' "$task_id")
    case "$task_state" in
        running) task_running+=("$task_id"); task_services+=("$task_service");;
        exited|created) ;;
        *) echo "Unsupported $task_service state: $task_state" >&2; exit 1;;
    esac
done
task_stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
task_partial="$task_root/backups/.partial-$task_stamp"
task_backup="$task_root/backups/$task_stamp"
task_pause_started=-1
cleanup() {
    task_rc=$?
    trap - EXIT INT TERM
    if (( ${#task_running[@]} )); then
        if ! docker start "${task_running[@]}" >/dev/null; then
            echo 'Failed to restore original service running state' >&2
            task_rc=1
        else
            for task_id in "${task_running[@]}"; do
                task_ready=false
                for ((task_i=0; task_i<45; task_i++)); do
                    task_state=$(docker inspect --format '{{.State.Running}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$task_id")
                    if [[ "$task_state" == 'true healthy' || "$task_state" == 'true none' ]]; then task_ready=true; break; fi
                    sleep 2
                done
                if [[ "$task_ready" != true ]]; then echo 'Service did not regain its original healthy/running state' >&2; task_rc=1; fi
            done
        fi
    fi
    if [[ -d "$task_partial" && ! -L "$task_partial" && "$task_partial" == "$task_root/backups/.partial-"* ]]; then
        rm -rf -- "$task_partial"
    fi
    if (( task_pause_started >= 0 )); then printf 'Service pause/recovery seconds: %s\n' "$((SECONDS-task_pause_started))"; fi
    exit "$task_rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
install -d -m 700 "$task_partial"
if (( ${#task_running[@]} )); then
    task_pause_started=$SECONDS
    docker stop --time 45 "${task_running[@]}" >/dev/null
fi
docker exec "$task_db_id" pg_dump -U semesteros -Fc semesteros >"$task_partial/database.dump"
docker run --rm --network none --volumes-from "$task_api_id:ro" --entrypoint tar "$task_image" -czf - -C /app/.local-data/media . >"$task_partial/media.tar.gz"
install -m 600 "$task_root/.env" "$task_partial/server.env"
printf '%s\n' "$task_release" >"$task_partial/release.txt"
python3 "$task_tools/backup_integrity.py" snapshot --backup "$task_partial" --db-container "$task_db_id" --app-image "$task_image" --db-image "$task_db_image" --initially-running "${task_services[*]}"
python3 "$task_tools/backup_integrity.py" verify --backup "$task_partial"
mv -- "$task_partial" "$task_backup"
printf 'Backup saved: %s\n' "$task_backup"
