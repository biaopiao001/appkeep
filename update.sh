#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"

API_BASE="${APPKEEP_API_BASE:-http://localhost:9420}"
APPKEEP_BIN="${APPKEEP_BIN:-$TARGET_HOME/.local/bin/appkeep}"
STATE_DIR="${APPKEEP_UPDATE_STATE_DIR:-$TARGET_HOME/.appkeep/update-history}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_FILE="$STATE_DIR/status-$TIMESTAMP.json"
RUNLIST_FILE="$STATE_DIR/running-$TIMESTAMP.json"
UPDATE_LOG="$STATE_DIR/update-$TIMESTAMP.log"
APPKEEP_LOG="$STATE_DIR/appkeep-$TIMESTAMP.log"

mkdir -p "$STATE_DIR"
touch "$UPDATE_LOG"

log() {
    printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$UPDATE_LOG"
}

fail() {
    log "ERROR: $*"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

api_get() {
    curl -fsS --connect-timeout 2 --max-time 10 "$API_BASE$1"
}

wait_for_api_up() {
    local timeout="${1:-60}"
    local end=$((SECONDS + timeout))

    while (( SECONDS < end )); do
        if api_get "/api/status" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

wait_for_api_down() {
    local timeout="${1:-30}"
    local end=$((SECONDS + timeout))

    while (( SECONDS < end )); do
        if ! api_get "/api/status" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

wait_for_pids_exit() {
    local timeout="$1"
    shift || true
    local pids=("$@")
    local end=$((SECONDS + timeout))
    local alive=()
    local pid

    if ((${#pids[@]} == 0)); then
        return 0
    fi

    while (( SECONDS < end )); do
        alive=()
        for pid in "${pids[@]}"; do
            if [[ -n "$pid" && -d "/proc/$pid" ]]; then
                alive+=("$pid")
            fi
        done

        if ((${#alive[@]} == 0)); then
            return 0
        fi

        sleep 1
    done

    printf '%s\n' "${alive[@]}"
    return 1
}

find_appkeep_pids() {
    pgrep -u "$TARGET_USER" -x appkeep 2>/dev/null || true
}

capture_running_state() {
    log "Capturing AppKeep status from $API_BASE"
    curl -fsS --connect-timeout 2 --max-time 10 "$API_BASE/api/status" -o "$SNAPSHOT_FILE" \
        || fail "AppKeep API is not reachable at $API_BASE"

    local count
    count="$(
        python3 - "$SNAPSHOT_FILE" "$RUNLIST_FILE" "$API_BASE" <<'PY'
import datetime
import json
import sys

snapshot_path, runlist_path, api_base = sys.argv[1:4]

with open(snapshot_path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

if isinstance(payload, dict):
    data = payload.get("data", [])
elif isinstance(payload, list):
    data = payload
else:
    data = []
items = []

for summary in data:
    cfg = summary.get("config") or {}
    config_id = cfg.get("id") or ""
    name = cfg.get("name") or config_id
    instances = summary.get("instances") or []
    running_instances = [
        {
            "id": inst.get("instanceId"),
            "pid": inst.get("pid"),
            "source": inst.get("source"),
        }
        for inst in instances
        if inst.get("status") == "running"
    ]

    if summary.get("status") == "running" or running_instances:
        if not config_id:
            raise SystemExit(f"Running app {name!r} has no config id")
        items.append(
            {
                "id": config_id,
                "name": name,
                "runningCount": max(1, len(running_instances)),
                "instances": running_instances,
            }
        )

with open(runlist_path, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "apiBase": api_base,
            "items": items,
        },
        fh,
        ensure_ascii=False,
        indent=2,
    )
    fh.write("\n")

print(len(items))
PY
    )"

    log "Saved status snapshot: $SNAPSHOT_FILE"
    log "Saved running-service list: $RUNLIST_FILE"
    log "Running configs to restore: $count"
}

running_instance_pids() {
    python3 - "$RUNLIST_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

for item in data.get("items", []):
    for inst in item.get("instances", []):
        pid = inst.get("pid")
        if pid:
            print(pid)
PY
}

stop_recorded_instances() {
    log "Stopping instances that were running before the update"
    python3 - "$RUNLIST_FILE" "$API_BASE" <<'PY'
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

runlist_path, api_base = sys.argv[1:3]

with open(runlist_path, "r", encoding="utf-8") as fh:
    runlist = json.load(fh)

def post(path):
    req = urllib.request.Request(api_base + path, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()

errors = []
for item in runlist.get("items", []):
    for inst in item.get("instances", []):
        instance_id = inst.get("id")
        if not instance_id:
            continue
        name = item.get("name") or item.get("id")
        try:
            post("/api/instances/stop?id=" + urllib.parse.quote(instance_id, safe=""))
            print(f"stopped {name}: {instance_id}")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            errors.append(f"{name}: HTTP {exc.code}: {body}")
        except Exception as exc:
            errors.append(f"{name}: {exc}")

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    raise SystemExit(1)
PY
}

restart_appkeep() {
    local pids=("$@")
    local still_alive=()
    local wait_output=""
    local appkeep_env=(
        "HOME=$TARGET_HOME"
        "USER=$TARGET_USER"
        "DISPLAY=${DISPLAY:-}"
        "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
        "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"
        "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$TARGET_UID/bus}"
        "PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}"
    )

    log "Stopping AppKeep process"
    if ((${#pids[@]} > 0)); then
        kill "${pids[@]}" 2>/dev/null || true
        if ! wait_output="$(wait_for_pids_exit 20 "${pids[@]}")"; then
            mapfile -t still_alive <<<"$wait_output"
            log "AppKeep did not exit after SIGTERM; sending SIGKILL to: ${still_alive[*]}"
            kill -KILL "${still_alive[@]}" 2>/dev/null || true
            wait_for_pids_exit 10 "${still_alive[@]}" >/dev/null \
                || fail "Could not stop AppKeep process"
        fi
    else
        log "No appkeep process found by name; continuing after API down check"
    fi

    wait_for_api_down 30 || fail "AppKeep API is still responding after stopping AppKeep"

    log "Starting AppKeep from $APPKEEP_BIN"
    [[ -x "$APPKEEP_BIN" ]] || fail "AppKeep binary is not executable: $APPKEEP_BIN"

    if [[ "$(id -u)" == "0" && "$TARGET_USER" != "root" ]]; then
        sudo -u "$TARGET_USER" env "${appkeep_env[@]}" setsid -f "$APPKEEP_BIN" </dev/null >>"$APPKEEP_LOG" 2>&1
    else
        env "${appkeep_env[@]}" setsid -f "$APPKEEP_BIN" </dev/null >>"$APPKEEP_LOG" 2>&1
    fi

    wait_for_api_up 60 || fail "AppKeep API did not become ready after restart. See $APPKEEP_LOG"
    log "AppKeep API is ready"
}

restore_recorded_configs() {
    log "Restoring previously running configs"
    python3 - "$RUNLIST_FILE" "$API_BASE" <<'PY'
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

runlist_path, api_base = sys.argv[1:3]

with open(runlist_path, "r", encoding="utf-8") as fh:
    runlist = json.load(fh)

def get_status():
    with urllib.request.urlopen(api_base + "/api/status", timeout=10) as resp:
        payload = json.load(resp)
    return payload.get("data", [])

def is_running(config_id):
    for item in get_status():
        if (item.get("config") or {}).get("id") == config_id:
            return item.get("status") == "running"
    return False

def post(path):
    req = urllib.request.Request(api_base + path, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", "replace")

errors = []
for item in runlist.get("items", []):
    config_id = item.get("id")
    name = item.get("name") or config_id
    count = int(item.get("runningCount") or 1)

    for index in range(count):
        try:
            if is_running(config_id):
                print(f"skip running {name}", flush=True)
                break
            print(f"starting {name} ({index + 1}/{count})", flush=True)
            post("/api/apps/start?id=" + urllib.parse.quote(config_id, safe=""))
            print(f"started {name} ({index + 1}/{count})", flush=True)
            time.sleep(1)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            errors.append(f"{name}: HTTP {exc.code}: {body}")
        except Exception as exc:
            errors.append(f"{name}: {exc}")

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    raise SystemExit(1)
PY
}

main() {
    require_cmd curl
    require_cmd python3
    require_cmd pgrep
    require_cmd setsid
    [[ -x "$SCRIPT_DIR/install.sh" ]] || fail "install.sh is not executable in $SCRIPT_DIR"

    if [[ "$(id -u)" != "0" ]]; then
        require_cmd sudo
    fi

    local appkeep_pids=()
    local instance_pids=()
    local still_running=()
    local wait_output=""

    mapfile -t appkeep_pids < <(find_appkeep_pids)
    capture_running_state
    mapfile -t instance_pids < <(running_instance_pids)

    if [[ "$(id -u)" != "0" ]]; then
        log "Checking sudo access"
        sudo -v || fail "sudo authentication failed"
    fi

    log "Running install.sh"
    if [[ "$(id -u)" == "0" ]]; then
        "$SCRIPT_DIR/install.sh" 2>&1 | tee -a "$UPDATE_LOG"
    else
        sudo "$SCRIPT_DIR/install.sh" 2>&1 | tee -a "$UPDATE_LOG"
    fi
    log "install.sh completed"

    stop_recorded_instances 2>&1 | tee -a "$UPDATE_LOG"
    if ! wait_output="$(wait_for_pids_exit 30 "${instance_pids[@]}")"; then
        mapfile -t still_running <<<"$wait_output"
        fail "Some recorded app instances are still running after stop: ${still_running[*]}"
    fi

    restart_appkeep "${appkeep_pids[@]}"
    restore_recorded_configs 2>&1 | tee -a "$UPDATE_LOG"

    log "Update completed"
    log "Log file: $UPDATE_LOG"
}

main "$@"
